import Foundation

/// Source-preserving edits of our scalar settings, not a general TOML serializer.
/// Unsupported/ambiguous representations fail closed; unrelated bytes are retained.
/// Lexical rules: https://toml.io/en/v1.0.0#string
public enum ProviderConfigurationEditor {
    public static func updating(_ source: String, original: APIProvider, replacement: APIProvider) throws -> String {
        let replacement = try replacement.validated()
        let prefix = ["model_providers", "codex_multi"]
        let fields: [([String], String)] = [
            (["cli_auth_credentials_store"], quote("file")),
            (["model_provider"], quote("codex_multi")),
            (["model"], quote(replacement.modelID)),
            (prefix + ["name"], quote(replacement.name)),
            (prefix + ["base_url"], quote(replacement.baseURL)),
            (prefix + ["wire_api"], quote("responses")),
            (prefix + ["requires_openai_auth"], "true")
        ]
        var parser = Scanner(source)
        let entries = try parser.parse()
        var changes: [(Range<Int>, String)] = []
        for (path, value) in fields {
            let matches = entries.filter { $0.path == path }
            guard matches.count == 1, let entry = matches.first,
                  !entries.contains(where: { $0.path != path && (path.starts(with: $0.path) || $0.path.starts(with: path)) }),
                  !parser.tables.contains(where: { $0.starts(with: path) }) else { throw conflict() }
            let old = try scalar(entry.value)
            switch path {
            case ["cli_auth_credentials_store"]: guard old == "file" else { throw conflict() }
            case ["model_provider"]: guard old == "codex_multi" else { throw conflict() }
            case prefix + ["wire_api"]: guard old == "responses" else { throw conflict() }
            case prefix + ["requires_openai_auth"]: guard entry.value == "true" else { throw conflict() }
            case prefix + ["base_url"]:
                let actual = try APIProvider(name: original.name, baseURL: old, modelID: original.modelID).validated()
                guard actual.baseURL == original.baseURL else { throw conflict() }
            default: break
            }
            changes.append((entry.range, value))
        }
        // Do not rotate a key into externally changed authentication or endpoint settings.
        let unsafe = ["env_key", "http_headers", "env_http_headers", "experimental_bearer_token", "bearer_token", "query_params"]
        guard !entries.contains(where: { entry in unsafe.contains { entry.path.starts(with: prefix + [$0]) } }),
              !parser.tables.contains(where: { table in unsafe.contains { table.starts(with: prefix + [$0]) } }) else { throw conflict() }
        var bytes = Array(source.utf8)
        for (range, value) in changes.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            bytes.replaceSubrange(range, with: value.utf8)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func quote(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(data: try! encoder.encode(value), encoding: .utf8)!
    }

    private static func scalar(_ source: String) throws -> String {
        if source == "true" { return source }
        var scanner = Scanner(source)
        let result = try scanner.string(multiline: false)
        guard scanner.index == scanner.bytes.count else { throw conflict() }
        return result
    }

    private static func conflict() -> LauncherError {
        LauncherError("配置中的供应商、认证方式或格式与启动器记录不一致，已保留原文件。请打开空间文件夹检查 config.toml。", "Provider, authentication, or configuration format differs from the launcher record. The original is preserved; inspect config.toml in the profile folder.")
    }

    private struct Entry {
        let path: [String]
        let range: Range<Int>
        let value: String
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0
        var tables: [[String]] = []
        init(_ source: String) { bytes = Array(source.utf8) }
        var current: UInt8? { index < bytes.count ? bytes[index] : nil }
        mutating func space() { while current == 32 || current == 9 { index += 1 } }
        mutating func comment() { while let c = current, c != 10 { index += 1 } }

        mutating func parse() throws -> [Entry] {
            guard bytes.count <= 1_048_576 else { throw conflict() }
            var entries: [Entry] = []
            var table: [String] = []
            var arrayTable = false
            while current != nil {
                space()
                if current == 35 { comment() }
                if current == 10 || current == 13 { index += 1; continue }
                guard current != nil else { break }
                if current == 91 {
                    index += 1
                    arrayTable = current == 91
                    if arrayTable { index += 1 }
                    table = try key(ending: 93)
                    index += 1
                    if arrayTable {
                        guard current == 93 else { throw conflict() }
                        index += 1
                    }
                    // Repeated or array tables overlapping managed configuration are ambiguous.
                    if table.first == "model_providers" || ["model", "model_provider", "cli_auth_credentials_store"].contains(table.first ?? "") {
                        guard !arrayTable, !tables.contains(table) else { throw conflict() }
                    }
                    tables.append(table)
                    try endLine()
                } else {
                    let path = table + (try key(ending: 61))
                    index += 1
                    space()
                    let start = index
                    try value()
                    var end = index
                    while end > start && [UInt8(32), 9, 13].contains(bytes[end - 1]) { end -= 1 }
                    guard end > start else { throw conflict() }
                    // Unrelated array table entries cannot masquerade as root settings.
                    if !arrayTable { entries.append(Entry(path: path, range: start..<end, value: String(decoding: bytes[start..<end], as: UTF8.self))) }
                    try endLine()
                }
            }
            return entries
        }

        mutating func endLine() throws {
            space()
            if current == 35 { comment() }
            if current == 13 { index += 1; guard current == 10 else { throw conflict() } }
            guard current == nil || current == 10 else { throw conflict() }
            if current == 10 { index += 1 }
        }

        mutating func key(ending: UInt8) throws -> [String] {
            var parts: [String] = []
            while true {
                space()
                if current == 34 || current == 39 {
                    parts.append(try string(multiline: false))
                } else {
                    let start = index
                    while let c = current, (65...90).contains(c) || (97...122).contains(c) || (48...57).contains(c) || c == 95 || c == 45 { index += 1 }
                    guard index > start else { throw conflict() }
                    parts.append(String(decoding: bytes[start..<index], as: UTF8.self))
                }
                space()
                if current == ending { return parts }
                guard current == 46 else { throw conflict() }
                index += 1
            }
        }

        mutating func value() throws {
            var brackets: [UInt8] = []
            while let c = current {
                if c == 34 || c == 39 { _ = try string(multiline: true); continue }
                if c == 35 {
                    if brackets.isEmpty { return }
                    comment(); continue
                }
                if (c == 10 || c == 13) && brackets.isEmpty { return }
                if c == 91 || c == 123 { brackets.append(c) }
                if c == 93 || c == 125 {
                    guard brackets.popLast() == (c == 93 ? 91 : 123) else { throw conflict() }
                }
                index += 1
            }
            guard brackets.isEmpty else { throw conflict() }
        }

        mutating func string(multiline allowed: Bool) throws -> String {
            guard let quote = current, quote == 34 || quote == 39 else { throw conflict() }
            let triple = index + 2 < bytes.count && bytes[index + 1] == quote && bytes[index + 2] == quote
            guard allowed || !triple else { throw conflict() }
            index += triple ? 3 : 1
            var decoded: [UInt8] = []
            while let c = current {
                if c == quote {
                    if !triple { index += 1; return String(decoding: decoded, as: UTF8.self) }
                    var count = 0
                    while index + count < bytes.count && bytes[index + count] == quote { count += 1 }
                    if count >= 3 {
                        guard count <= 5 else { throw conflict() }
                        index += count
                        return String(decoding: decoded, as: UTF8.self)
                    }
                }
                guard triple || (c != 10 && c != 13) else { throw conflict() }
                if c == 92 && quote == 34 {
                    index += 1
                    guard let escape = current else { throw conflict() }
                    if triple && [UInt8(32), 9, 10, 13].contains(escape) {
                        while let char = current, [UInt8(32), 9, 10, 13].contains(char) { index += 1 }
                        continue
                    }
                    let escapes: [UInt8: UInt8] = [34: 34, 92: 92, 98: 8, 116: 9, 110: 10, 102: 12, 114: 13]
                    if let char = escapes[escape] { decoded.append(char); index += 1; continue }
                    guard escape == 117 || escape == 85 else { throw conflict() }
                    let digits = escape == 117 ? 4 : 8
                    index += 1
                    guard index + digits <= bytes.count,
                          let number = UInt32(String(decoding: bytes[index..<(index + digits)], as: UTF8.self), radix: 16),
                          let scalar = UnicodeScalar(number) else { throw conflict() }
                    decoded.append(contentsOf: String(scalar).utf8)
                    index += digits
                } else {
                    guard c >= 32 || c == 9 || (triple && (c == 10 || c == 13)) else { throw conflict() }
                    decoded.append(c)
                    index += 1
                }
            }
            throw conflict()
        }
    }
}

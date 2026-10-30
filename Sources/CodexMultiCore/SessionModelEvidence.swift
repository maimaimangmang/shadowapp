import Foundation

/// Local client evidence only; never infers the provider's upstream model.
public struct SessionModelEvidence: Equatable {
    public let sessionID: String
    public let model: String
    public let provider: String
    public let timestamp: String?
    public let file: URL

    public static func latest(in paths: ProfilePaths) throws -> SessionModelEvidence? {
        let fm = FileManager.default
        let original = paths.codex.appendingPathComponent("sessions", isDirectory: true)
        let base = paths.root.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
        let root = base.appendingPathComponent("profiles").appendingPathComponent(paths.root.lastPathComponent)
            .appendingPathComponent("codex/sessions").standardizedFileURL
        guard fm.fileExists(atPath: root.path) else { return nil }
        // Do not follow a profile or session directory into another account.
        guard original.resolvingSymlinksInPath().path == root.path else {
            throw unavailable()
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        var enumerationFailed = false
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles], errorHandler: { _, _ in enumerationFailed = true; return false }) else { throw unavailable() }
        var latest: (URL, Date)?
        var visited = 0
        for case let file as URL in enumerator {
            visited += 1
            guard visited <= 20_000 else { throw unavailable() }
            let attrs = try file.resourceValues(forKeys: Set(keys))
            if attrs.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard attrs.isRegularFile == true, file.pathExtension == "jsonl" else { continue }
            let date = attrs.contentModificationDate ?? .distantPast
            if latest == nil || date > latest!.1 { latest = (file, date) }
        }
        guard !enumerationFailed else { throw unavailable() }
        guard let file = latest?.0 else { return nil }
        guard file.resolvingSymlinksInPath().path == file.standardizedFileURL.path else { throw unavailable() }
        let attrs = try file.resourceValues(forKeys: [.fileSizeKey])
        guard let size = attrs.fileSize, size <= 32 * 1024 * 1024 else { throw unavailable() }
        let data = try Data(contentsOf: file)
        guard data.count <= 32 * 1024 * 1024 else { throw unavailable() }
        var sessionID: String?
        var provider: String?
        var model: String?
        var timestamp: String?
        // Chat text and tool outputs are ignored. Only typed metadata is used.
        for line in data.split(separator: 10) {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = row["payload"] as? [String: Any] else { continue }
            if row["type"] as? String == "session_meta" {
                sessionID = safeString(payload["id"])
                provider = safeString(payload["model_provider"])
            } else if row["type"] as? String == "turn_context" {
                // Missing metadata on a newer turn must not reuse an older model.
                model = safeString(payload["model"])
                timestamp = safeString(row["timestamp"])
            }
        }
        guard let sessionID, let provider, let model else { throw unavailable() }
        return Self(sessionID: sessionID, model: model, provider: provider, timestamp: timestamp, file: file)
    }

    private static func safeString(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text.count <= 300,
              text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return text
    }

    private static func unavailable() -> LauncherError {
        LauncherError("无法完整读取最近会话的模型记录，请在 Codex 内查看；不会用配置值代替。", "Could not read complete model metadata for the latest session. Check inside Codex; configured defaults are not used as a substitute.")
    }
}

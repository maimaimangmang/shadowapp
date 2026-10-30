import Foundation

public enum Texts {
    public static var chinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    public static func t(_ chinese: String, _ english: String) -> String {
        self.chinese ? chinese : english
    }
}

public struct LauncherError: LocalizedError {
    public let errorDescription: String?
    public init(_ chinese: String, _ english: String) {
        errorDescription = Texts.t(chinese, english)
    }
}

public struct ProcessReceipt: Codable, Equatable {
    public let pid: Int32
    public let launchedAt: Date
    public let bundlePath: String

    public init(pid: Int32, launchedAt: Date, bundlePath: String) {
        self.pid = pid
        self.launchedAt = launchedAt
        self.bundlePath = bundlePath
    }

    public func matches(pid: Int32, launchedAt: Date?, bundlePath: String?) -> Bool {
        guard let launchedAt, let bundlePath else { return false }
        return self.pid == pid && abs(self.launchedAt.timeIntervalSince(launchedAt)) < 0.01
            && self.bundlePath == URL(fileURLWithPath: bundlePath).resolvingSymlinksInPath().path
    }
}

public struct Profile: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public let colorIndex: Int
    public let createdAt: Date
    public var receipt: ProcessReceipt?
    public var apiProvider: APIProvider?
    public var directoryName: String?
    public var archived: Bool?

    public init(id: UUID = UUID(), name: String, colorIndex: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.createdAt = createdAt
    }
}

public struct Registry: Codable {
    public var schemaVersion = 2
    public var application: ManagedApplication?
    public var applicationPath: String?
    public var profiles: [Profile] = []
    public init() {}
}

public struct ProfilePaths: Equatable {
    public let root: URL
    public let id: UUID
    public let claudeAPI: Bool
    public var codex: URL { root.appendingPathComponent("codex", isDirectory: true) }
    public var workbuddyHome: URL { root.appendingPathComponent("home", isDirectory: true) }
    public var workbuddyConfig: URL { root.appendingPathComponent("workbuddy", isDirectory: true) }
    public var workbuddyAuth: URL { workbuddyHome.appendingPathComponent("Library/Application Support/CodeBuddyExtension/Data/Public/auth", isDirectory: true) }
    public var workbuddyAppConfig: URL { desktop.appendingPathComponent("app-config.json") }
    public var claudeConfig: URL { root.appendingPathComponent("claude-code", isDirectory: true) }
    public var desktop: URL { root.appendingPathComponent(claudeAPI ? "desktop-3p" : "desktop", isDirectory: true) }
    public var claudeLibrary: URL { desktop.appendingPathComponent("configLibrary", isDirectory: true) }
    public var claudeProvider: URL { claudeLibrary.appendingPathComponent(id.uuidString.lowercased() + ".json") }
    public var claudeLibraryMetadata: URL { claudeLibrary.appendingPathComponent("_meta.json") }
    public var claudeDesktopConfig: URL { desktop.appendingPathComponent("claude_desktop_config.json") }
    public var config: URL { codex.appendingPathComponent("config.toml") }
    public var auth: URL { codex.appendingPathComponent("auth.json") }
    public var singletonLock: URL { desktop.appendingPathComponent("SingletonLock") }
    public var wechatIdentifier: String { "org.shadowapp.wechat.space." + id.uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
    public var wechatApplication: URL { root.appendingPathComponent("WeChat.app", isDirectory: true) }
    public var wechatManifest: URL { root.appendingPathComponent("wechat.json") }
    public var wechatContainer: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/" + wechatIdentifier, isDirectory: true)
    }

    public init(base: URL, id: UUID, directoryName: String? = nil, claudeAPI: Bool = false) {
        self.id = id
        self.claudeAPI = claudeAPI
        let component = directoryName.flatMap { ProfileDirectory.isValid($0, id: id) ? $0 : nil } ?? id.uuidString.lowercased()
        root = base.appendingPathComponent("profiles", isDirectory: true)
            .appendingPathComponent(component, isDirectory: true)
    }
}

/// Names are immutable path components, independent of subsequent display-name changes.
public enum ProfileDirectory {
    public static func name(for profile: Profile) -> String {
        let parts = profile.name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }
        let stem = parts.joined().split(separator: "-").joined(separator: "-")
        let readable = String(stem.prefix(24))
        return (readable.isEmpty ? "space" : readable) + "-" + profile.id.uuidString.prefix(8).lowercased()
    }

    public static func isValid(_ name: String, id: UUID) -> Bool {
        !name.isEmpty && name.count <= 64 && name.hasSuffix("-" + id.uuidString.prefix(8).lowercased()) &&
        name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
    }
}

public struct LaunchPlan: Equatable {
    public let application: ManagedApplication
    public let createsNewInstance: Bool
    public let environment: [String: String]
    public let arguments: [String]

    public init(paths: ProfilePaths, application: ManagedApplication = .codex) {
        self.application = application
        createsNewInstance = application.supportsSeparateProfiles
        if application == .wechat {
            // macOS chooses the container from the signed app identity, not HOME or argv.
            environment = [:]
            arguments = []
            return
        }
        if application == .workbuddy {
            environment = ["HOME": paths.workbuddyHome.path,
                           "WORKBUDDY_CONFIG_DIR": paths.workbuddyConfig.path,
                           "CODEBUDDY_CONFIG_DIR": paths.workbuddyConfig.path,
                           "WORKBUDDY_USER_DATA_DIR": paths.desktop.path]
            arguments = ["--user-data-dir=\(paths.desktop.path)"]
            return
        }
        if application == .claude {
            environment = [
                "CLAUDE_CONFIG_DIR": paths.claudeConfig.path,
                "CLAUDE_SECURESTORAGE_CONFIG_DIR": paths.claudeConfig.path
            ]
            arguments = ["--user-data-dir=\(paths.desktop.path)"]
            return
        }
        environment = [
            "CODEX_HOME": paths.codex.path,
            "CODEX_SQLITE_HOME": paths.codex.path,
            "CODEX_ELECTRON_USER_DATA_PATH": paths.desktop.path
        ]
        arguments = ["--user-data-dir=\(paths.desktop.path)"]
    }
}

public enum SingletonLock {
    public static func processID(from target: String) -> Int32? {
        guard let suffix = target.split(separator: "-").last,
              let pid = Int32(suffix), pid > 0, target.contains("-") else { return nil }
        return pid
    }
}

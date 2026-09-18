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

    public init(id: UUID = UUID(), name: String, colorIndex: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.createdAt = createdAt
    }
}

public struct Registry: Codable {
    public var schemaVersion = 1
    public var applicationPath: String?
    public var profiles: [Profile] = []
    public init() {}
}

public struct ProfilePaths: Equatable {
    public let root: URL
    public var codex: URL { root.appendingPathComponent("codex", isDirectory: true) }
    public var desktop: URL { root.appendingPathComponent("desktop", isDirectory: true) }
    public var config: URL { codex.appendingPathComponent("config.toml") }
    public var singletonLock: URL { desktop.appendingPathComponent("SingletonLock") }

    public init(base: URL, id: UUID) {
        root = base.appendingPathComponent("profiles", isDirectory: true)
            .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }
}

public struct LaunchPlan: Equatable {
    public let environment: [String: String]
    public let arguments: [String]

    public init(paths: ProfilePaths) {
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

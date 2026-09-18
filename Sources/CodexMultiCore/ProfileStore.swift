import Darwin
import Foundation

public final class ProfileStore {
    public let root: URL
    private let fm = FileManager.default
    private var registryURL: URL { root.appendingPathComponent("profiles.json") }

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Codex Multi", isDirectory: true)
    }

    public init(root: URL = ProfileStore.defaultRoot) {
        self.root = root.standardizedFileURL
    }

    public func paths(for profile: Profile) -> ProfilePaths { ProfilePaths(base: root, id: profile.id) }

    public func load() throws -> Registry {
        try withLock {
            if !fm.fileExists(atPath: registryURL.path) {
                var registry = Registry()
                registry.profiles = [
                    Profile(name: Texts.t("个人账号", "Personal"), colorIndex: 0),
                    Profile(name: Texts.t("工作账号", "Work"), colorIndex: 1)
                ]
                try saveUnlocked(registry)
                return registry
            }
            return try loadUnlocked()
        }
    }

    @discardableResult public func create(name: String) throws -> Profile {
        try withLock {
            var registry = try loadUnlocked()
            let name = try validatedName(name, in: registry)
            let profile = Profile(name: name, colorIndex: registry.profiles.count % 5)
            registry.profiles.append(profile)
            try saveUnlocked(registry)
            return profile
        }
    }

    public func rename(_ id: UUID, to name: String) throws {
        try mutate { registry in
            guard let i = registry.profiles.firstIndex(where: { $0.id == id }) else { throw missingProfile() }
            registry.profiles[i].name = try validatedName(name, in: registry, excluding: id)
        }
    }

    public func setApplication(_ url: URL) throws {
        try mutate { $0.applicationPath = url.resolvingSymlinksInPath().path }
    }

    public func record(_ receipt: ProcessReceipt, for id: UUID) throws {
        try mutate { registry in
            guard let i = registry.profiles.firstIndex(where: { $0.id == id }) else { throw missingProfile() }
            registry.profiles[i].receipt = receipt
        }
    }

    // The caller must verify that the profile is stopped. Trash is reversible; no recursive deletion.
    public func moveToTrash(_ id: UUID) throws {
        try withLock {
            var registry = try loadUnlocked()
            guard let profile = registry.profiles.first(where: { $0.id == id }) else { throw missingProfile() }
            let directory = paths(for: profile).root
            try rejectSymlink(root.appendingPathComponent("profiles"))
            try rejectSymlink(directory)
            if fm.fileExists(atPath: directory.path) {
                try fm.trashItem(at: directory, resultingItemURL: nil)
            }
            registry.profiles.removeAll { $0.id == id }
            try saveUnlocked(registry)
        }
    }

    public func prepare(_ profile: Profile) throws -> ProfilePaths {
        try withLock {
            let registry = try loadUnlocked()
            guard registry.profiles.contains(where: { $0.id == profile.id }) else { throw missingProfile() }
            let paths = paths(for: profile)
            for directory in [root.appendingPathComponent("profiles"), paths.root, paths.codex, paths.desktop] {
                try ensurePrivateDirectory(directory)
            }
            try rejectSymlink(paths.config)
            if !fm.fileExists(atPath: paths.config.path) {
                let config = """
                # Created by Codex Multi. Keep credentials inside this profile.
                cli_auth_credentials_store = "file"

                """
                try Data(config.utf8).write(to: paths.config, options: .withoutOverwriting)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.config.path)
            }
            return paths
        }
    }

    private func mutate(_ body: (inout Registry) throws -> Void) throws {
        try withLock {
            var registry = try loadUnlocked()
            try body(&registry)
            try saveUnlocked(registry)
        }
    }

    private func loadUnlocked() throws -> Registry {
        try rejectSymlink(registryURL)
        let attributes = try fm.attributesOfItem(atPath: registryURL.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 < 1_048_576 else {
            throw LauncherError("账号列表文件异常，请先备份并检查 profiles.json。", "The profile registry is too large. Back up and inspect profiles.json.")
        }
        let registry = try JSONDecoder().decode(Registry.self, from: Data(contentsOf: registryURL))
        guard registry.schemaVersion == 1,
              Set(registry.profiles.map(\.id)).count == registry.profiles.count else {
            throw LauncherError("账号列表格式不受支持，原文件已保留。", "Unsupported profile registry. The original file has been preserved.")
        }
        return registry
    }

    private func saveUnlocked(_ registry: Registry) throws {
        try rejectSymlink(registryURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(registry).write(to: registryURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registryURL.path)
    }

    private func withLock<T>(_ action: () throws -> T) throws -> T {
        try ensurePrivateDirectory(root)
        let lockURL = root.appendingPathComponent(".registry.lock")
        let fd = Darwin.open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        try rejectSymlink(url)
        try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func rejectSymlink(_ url: URL) throws {
        if (try? fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
            throw LauncherError("数据路径是符号链接，已停止操作：\(url.lastPathComponent)", "Refusing a symlink at data path: \(url.lastPathComponent)")
        }
    }

    private func validatedName(_ raw: String, in registry: Registry, excluding id: UUID? = nil) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 40, value.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw LauncherError("名称需要 1–40 个字符，不能包含换行或控制字符。", "Use 1–40 characters without line breaks or control characters.")
        }
        guard !registry.profiles.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(value) == .orderedSame }) else {
            throw LauncherError("这个名称已经存在，请换一个。", "This name is already in use.")
        }
        return value
    }

    private func missingProfile() -> LauncherError {
        LauncherError("找不到这个账号空间，请刷新后重试。", "Profile not found. Refresh and try again.")
    }
}

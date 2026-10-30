import Darwin
import Foundation

public final class ProfileStore {
    public let root: URL
    public let application: ManagedApplication
    private let fm = FileManager.default
    private let trashItem: (URL) throws -> URL
    private var registryURL: URL { root.appendingPathComponent("profiles.json") }

    public static var defaultRoot: URL {
        let fm = FileManager.default
        let preferred = fm.homeDirectoryForCurrentUser.appendingPathComponent("CodexMulti", isDirectory: true)
        let legacy = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Codex Multi", isDirectory: true)
        // Preserve installations already using the old default; never silently relocate live data.
        if !fm.fileExists(atPath: preferred.path), fm.fileExists(atPath: legacy.appendingPathComponent("profiles.json").path) {
            return legacy
        }
        return preferred
    }

    public init(root: URL = ProfileStore.defaultRoot, application: ManagedApplication = .codex, trashItem: ((URL) throws -> URL)? = nil) {
        self.root = root.standardizedFileURL
        self.application = application
        self.trashItem = trashItem ?? { directory in
            var result: NSURL?
            try FileManager.default.trashItem(at: directory, resultingItemURL: &result)
            guard let result else {
                throw LauncherError("文件夹已移至废纸篓，但无法取得恢复位置，请在废纸篓中检查。", "The folder was trashed, but its recovery location is unavailable. Check the Trash.")
            }
            return result as URL
        }
    }

    public func paths(for profile: Profile) -> ProfilePaths { ProfilePaths(base: root, id: profile.id, directoryName: profile.directoryName, claudeAPI: application == .claude && profile.apiProvider != nil) }

    public func load(createIfMissing: Bool = true) throws -> Registry {
        try withLock {
            if !fm.fileExists(atPath: registryURL.path) {
                guard createIfMissing else {
                    throw LauncherError("找不到账号列表文件，请恢复 profiles.json 后重试。", "The profile registry is missing. Restore profiles.json and retry.")
                }
                var registry = Registry()
                if application != .codex { registry.application = application; registry.schemaVersion = application == .wechat ? 6 : application == .workbuddy ? 5 : 3 }
                try saveUnlocked(registry)
                return registry
            }
            return try loadUnlocked()
        }
    }

    @discardableResult public func create(name: String) throws -> Profile {
        return try withLock {
            var registry = try loadUnlocked()
            let name = try validatedName(name, in: registry)
            var profile = Profile(name: name, colorIndex: registry.profiles.count % 5)
            profile.directoryName = ProfileDirectory.name(for: profile)
            let directory = paths(for: profile).root
            guard !fm.fileExists(atPath: directory.path),
                  !registry.profiles.contains(where: { paths(for: $0).root.path.lowercased() == directory.path.lowercased() }) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try rejectSymlink(directory)
            registry.profiles.append(profile)
            try saveUnlocked(registry)
            return profile
        }
    }

    @discardableResult public func create(name: String, provider: APIProvider, apiKey: String) throws -> Profile {
        guard application.supportsAPIProfiles else { throw unsupportedAPI() }
        let provider = try provider.validated(application: application)
        let key = try APIProvider.validatedKey(apiKey)
        return try withLock {
            var registry = try loadUnlocked()
            var profile = Profile(name: try validatedName(name, in: registry), colorIndex: registry.profiles.count % 5)
            profile.apiProvider = provider
            profile.directoryName = ProfileDirectory.name(for: profile)
            let paths = paths(for: profile)
            try ensurePrivateDirectory(root.appendingPathComponent("profiles"))
            // This UUID is new. Never adopt or replace an existing directory.
            guard !fm.fileExists(atPath: paths.root.path) else { throw CocoaError(.fileWriteFileExists) }
            try rejectSymlink(paths.root)
            try ensurePrivateDirectory(paths.root)
            do {
                if application == .claude {
                    try ensurePrivateDirectory(paths.desktop)
                    try ensurePrivateDirectory(paths.claudeConfig)
                    try ensurePrivateDirectory(paths.claudeLibrary)
                    try writePrivate(ClaudeProviderConfiguration.configuration(provider: provider, key: key), to: paths.claudeProvider)
                    try writePrivate(ClaudeProviderConfiguration.metadata(id: profile.id, name: profile.name), to: paths.claudeLibraryMetadata)
                    try writePrivate(ClaudeProviderConfiguration.encode(["deploymentMode": "3p"]), to: paths.claudeDesktopConfig)
                    registry.profiles.append(profile)
                    try saveUnlocked(registry)
                    return profile
                }
                try ensurePrivateDirectory(paths.codex)
                try ensurePrivateDirectory(paths.desktop)
                try writePrivate(Data(provider.configuration.utf8), to: paths.config)
                try writePrivate(JSONEncoder().encode(["OPENAI_API_KEY": key]), to: paths.auth)
                try installGuidance(paths)
                registry.profiles.append(profile)
                try saveUnlocked(registry)
                return profile
            } catch {
                // Only our newly created, unpublished UUID directory is removed on failure.
                try? fm.removeItem(at: paths.root)
                throw error
            }
        }
    }

    public func updateProvider(_ id: UUID, provider: APIProvider, newAPIKey: String?) throws {
        guard application.supportsAPIProfiles else { throw unsupportedAPI() }
        let provider = try provider.validated(application: application)
        let key = try newAPIKey.map(APIProvider.validatedKey)
        try withProfileOperation(id) {
            let originalRegistry = try loadUnlocked()
            var registry = originalRegistry
            guard let i = registry.profiles.firstIndex(where: { $0.id == id }),
                  let original = registry.profiles[i].apiProvider else {
                throw LauncherError("这个空间未使用 API Key，请新建一个 API 空间。", "Create an API profile to use this connection method.")
            }
            let profile = registry.profiles[i]
            let paths = paths(for: profile)
            for directory in [root.appendingPathComponent("profiles"), paths.root, paths.codex, paths.desktop] {
                try rejectSymlink(directory)
            }
            try requireStopped(profile)
            if original.baseURL != provider.baseURL && key == nil {
                throw LauncherError("更换接口地址时，请重新填写对应的 API Key。", "Enter the matching API key when changing the base URL.")
            }
            if application == .claude {
                try validateClaudeSelection(paths)
                let oldData = try readPrivateConfiguration(paths.claudeProvider)
                let updated = try ClaudeProviderConfiguration.updating(oldData, original: original, replacement: provider, key: key)
                registry.profiles[i].apiProvider = provider
                do {
                    try writePrivate(updated, to: paths.claudeProvider)
                    try saveUnlocked(registry)
                } catch {
                    try writePrivate(oldData, to: paths.claudeProvider)
                    throw error
                }
                return
            }
            try rejectSymlink(paths.config)
            try rejectSymlink(paths.auth)
            let configAttributes = try fm.attributesOfItem(atPath: paths.config.path)
            guard configAttributes[.type] as? FileAttributeType == .typeRegular,
                  (configAttributes[.size] as? NSNumber)?.intValue ?? 0 <= 1_048_576 else {
                throw LauncherError("配置文件过大或不是普通文件，已停止保存。", "The configuration is too large or is not a regular file. Saving stopped.")
            }
            let oldData = try Data(contentsOf: paths.config)
            guard let oldConfig = String(data: oldData, encoding: .utf8) else {
                throw LauncherError("供应商配置已被其他程序修改，请从账号数据文件夹检查 config.toml；现有内容已保留。", "Provider configuration was edited externally. Check config.toml in the account data folder; existing contents are preserved.")
            }
            if key == nil && !fm.fileExists(atPath: paths.auth.path) {
                throw LauncherError("找不到这个空间的密钥，请重新填写 API Key。", "This profile's key is missing. Enter its API key again.")
            }
            let newConfig = try ProviderConfigurationEditor.updating(oldConfig, original: original, replacement: provider)
            registry.profiles[i].apiProvider = provider
            do {
                try writePrivate(Data(newConfig.utf8), to: paths.config)
                try saveUnlocked(registry)
                // Last throwing operation: never read the existing credential for a rollback.
                if let key { try writePrivate(JSONEncoder().encode(["OPENAI_API_KEY": key]), to: paths.auth) }
            } catch {
                do {
                    try writePrivate(oldData, to: paths.config)
                    try saveUnlocked(originalRegistry)
                } catch {
                    throw LauncherError("保存未完成，配置恢复也失败。请检查账号数据文件夹后再启动。", "Saving and restoring configuration failed. Check the account data folder before launching.")
                }
                throw error
            }
        }
    }

    private func readPrivateConfiguration(_ file: URL) throws -> Data {
        try rejectSymlink(file)
        let attributes = try fm.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 1_048_576 else {
            throw LauncherError("配置文件不可读取或过大，已停止操作。", "The configuration is not readable or is too large.")
        }
        return try Data(contentsOf: file)
    }

    private func validateClaudeSelection(_ paths: ProfilePaths) throws {
        try rejectSymlink(paths.claudeLibrary)
        try ClaudeProviderConfiguration.validateSelection(metadata: readPrivateConfiguration(paths.claudeLibraryMetadata), desktop: readPrivateConfiguration(paths.claudeDesktopConfig), id: paths.id)
    }

    /// Create private files before writing any secret, then atomically replace the destination.
    private func writePrivate(_ data: Data, to url: URL) throws {
        try rejectSymlink(url)
        let temp = url.deletingLastPathComponent().appendingPathComponent(".write-\(UUID().uuidString)")
        let fd = Darwin.open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close(); try? fm.removeItem(at: temp) }
        try file.write(contentsOf: data)
        try file.synchronize()
        try file.close()
        guard Darwin.rename(temp.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
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

    // Recheck at the storage boundary, even if a UI already checked before confirmation.
    public func moveToTrash(_ id: UUID) throws {
        guard application != .wechat else {
            throw LauncherError("微信空间请使用归档，账号数据会保留。", "Archive WeChat profiles to preserve their account data.")
        }
        try withProfileOperation(id) {
            var registry = try loadUnlocked()
            guard let profile = registry.profiles.first(where: { $0.id == id }) else { throw missingProfile() }
            let directory = paths(for: profile).root
            try rejectSymlink(root.appendingPathComponent("profiles"))
            try rejectSymlink(directory)
            try rejectSymlink(paths(for: profile).desktop)
            try requireStopped(profile)
            var trashed: URL?
            if fm.fileExists(atPath: directory.path) {
                trashed = try trashItem(directory)
            }
            registry.profiles.removeAll { $0.id == id }
            do { try saveUnlocked(registry) }
            catch {
                if let trashed {
                    do { try fm.moveItem(at: trashed, to: directory) }
                    catch {
                        throw LauncherError("账号列表保存失败，文件夹仍在废纸篓。请先从废纸篓恢复该空间，再重试。", "The registry could not be saved and the folder remains in the Trash. Restore this profile from the Trash before retrying.")
                    }
                }
                throw error
            }
        }
    }

    public func setWeChatArchived(_ id: UUID, archived: Bool) throws {
        guard application == .wechat else { throw missingProfile() }
        try withProfileOperation(id) {
            var registry = try loadUnlocked()
            guard let index = registry.profiles.firstIndex(where: { $0.id == id }) else { throw missingProfile() }
            try requireStopped(registry.profiles[index])
            registry.profiles[index].archived = archived
            try saveUnlocked(registry)
        }
    }

    public func dataFolder(for profile: Profile) -> URL {
        application == .wechat ? paths(for: profile).wechatContainer : paths(for: profile).root
    }

    /// Reveal must work even when auth/config needs repair; it must not rewrite those files.
    public func folderURL(for profile: Profile) throws -> URL {
        try withLock {
            let current = try currentProfile(profile.id)
            if application == .wechat {
                let container = paths(for: current).wechatContainer
                try rejectSymlink(container)
                guard fm.fileExists(atPath: container.path) else {
                    throw LauncherError("首次打开微信后，macOS 才会创建这个空间的数据文件夹。", "macOS creates this data folder when you first open the WeChat profile.")
                }
                return container
            }
            let directory = paths(for: current).root
            try ensurePrivateDirectory(root.appendingPathComponent("profiles"))
            try ensurePrivateDirectory(directory)
            return directory
        }
    }

    public func prepare(_ profile: Profile) throws -> ProfilePaths {
        return try withLock {
            let current = try currentProfile(profile.id)
            let paths = paths(for: current)
            if application == .wechat {
                guard current.archived != true else { throw missingProfile() }
                try requireStopped(current)
                for directory in [root.appendingPathComponent("profiles"), paths.root] { try ensurePrivateDirectory(directory) }
                return paths
            }
            if application == .workbuddy { try requireStopped(current) }
            let directories = [root.appendingPathComponent("profiles"), paths.root, paths.desktop] + (application == .codex ? [paths.codex] : application == .claude ? [paths.claudeConfig] : [paths.workbuddyHome, paths.workbuddyConfig])
            for directory in directories { try ensurePrivateDirectory(directory) }
            if application == .workbuddy {
                // Check every ancestor, not just the final directory, to prevent auth redirects.
                var directory = paths.workbuddyHome
                for component in ["Library", "Application Support", "CodeBuddyExtension", "Data", "Public", "auth"] {
                    directory.appendPathComponent(component, isDirectory: true)
                    try ensurePrivateDirectory(directory)
                }
                try rejectSymlink(paths.workbuddyAppConfig)
                var settings: [String: Any] = [:]
                if fm.fileExists(atPath: paths.workbuddyAppConfig.path) {
                    guard let object = try JSONSerialization.jsonObject(with: readPrivateConfiguration(paths.workbuddyAppConfig)) as? [String: Any] else {
                        throw LauncherError("WorkBuddy 设置格式异常，原文件已保留。", "Invalid WorkBuddy settings. The original file is preserved.")
                    }
                    settings = object
                }
                settings["startupForceAutoUpdate"] = false
                try writePrivate(JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys]), to: paths.workbuddyAppConfig)
                return paths
            }
            if application == .claude {
                if let provider = current.apiProvider {
                    try validateClaudeSelection(paths)
                    _ = try ClaudeProviderConfiguration.validate(readPrivateConfiguration(paths.claudeProvider), provider: provider)
                }
                return paths
            }
            try rejectSymlink(paths.config)
            if current.apiProvider != nil {
                try rejectSymlink(paths.auth)
                guard (try? fm.attributesOfItem(atPath: paths.auth.path)[.type] as? FileAttributeType) == .typeRegular else {
                    throw LauncherError("API Key 文件缺失或不可用，请在「模型与 API Key」中重新填写。", "The API key file is missing or unavailable. Enter the key again in Model & API key.")
                }
            }
            if !fm.fileExists(atPath: paths.config.path) {
                guard current.apiProvider == nil else {
                    throw LauncherError("API 空间的配置文件缺失，请恢复 config.toml 后再打开。", "The API profile's config.toml is missing. Restore it before opening.")
                }
                let config = """
                # Created by ShadowApp. Keep credentials inside this profile.
                cli_auth_credentials_store = "file"

                """
                try Data(config.utf8).write(to: paths.config, options: .withoutOverwriting)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.config.path)
            }
            try installGuidance(paths)
            return paths
        }
    }

    // May also be applied to an existing space without touching its config or credentials.
    public func prepareGuidance(for profile: Profile) throws {
        guard application == .codex else { return }
        try withLock {
            let current = try currentProfile(profile.id)
            let paths = paths(for: current)
            for directory in [root.appendingPathComponent("profiles"), paths.root, paths.codex] {
                try ensurePrivateDirectory(directory)
            }
            try installGuidance(paths)
        }
    }

    private func installGuidance(_ paths: ProfilePaths) throws {
        let normal = paths.codex.appendingPathComponent("AGENTS.md")
        let override = paths.codex.appendingPathComponent("AGENTS.override.md")
        // Preflight both files before any write. Codex prefers a non-empty override.
        var updates: [(URL, String)] = []
        for file in [normal, override] {
            try rejectSymlink(file)
            let exists = fm.fileExists(atPath: file.path)
            if file == override && !exists { continue }
            if exists {
                let attrs = try fm.attributesOfItem(atPath: file.path)
                guard attrs[.type] as? FileAttributeType == .typeRegular,
                      (attrs[.size] as? NSNumber)?.intValue ?? 0 <= 262_144 else {
                    throw LauncherError("空间指令文件无法安全更新，请检查 AGENTS 文件。", "Cannot safely update the profile's AGENTS file. Please inspect it.")
                }
            }
            let previous = exists ? try String(contentsOf: file, encoding: .utf8) : ""
            if file == override && previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let next = try ProfileGuidance.merging(previous, paths: paths)
            if next != previous { updates.append((file, next)) }
        }
        for (file, content) in updates { try writePrivate(Data(content.utf8), to: file) }
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
        guard [1, 2, 3, 4, 5, 6].contains(registry.schemaVersion),
              (registry.application ?? .codex) == application,
              (application == .codex ? registry.schemaVersion <= 2 : application == .claude ? [3, 4].contains(registry.schemaVersion) : application == .wechat ? registry.schemaVersion == 6 : (registry.schemaVersion == 5 || (registry.schemaVersion == 3 && registry.profiles.isEmpty))),
              (application == .wechat || registry.profiles.allSatisfy { $0.archived == nil }),
              (application != .claude || registry.profiles.allSatisfy { $0.apiProvider == nil } || registry.schemaVersion == 4),
              (application.supportsAPIProfiles || registry.profiles.allSatisfy { $0.apiProvider == nil }),
              Set(registry.profiles.map(\.id)).count == registry.profiles.count,
              registry.profiles.allSatisfy({ profile in
                  guard let name = profile.directoryName else { return true }
                  return registry.schemaVersion >= 2 && ProfileDirectory.isValid(name, id: profile.id)
              }),
              Set(registry.profiles.map { paths(for: $0).root.path.lowercased() }).count == registry.profiles.count else {
            throw LauncherError("账号列表格式不受支持，原文件已保留。", "Unsupported profile registry. The original file has been preserved.")
        }
        return registry
    }

    private func saveUnlocked(_ registry: Registry) throws {
        try rejectSymlink(registryURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var versioned = registry
        if application == .claude { versioned.schemaVersion = max(versioned.schemaVersion, versioned.profiles.contains(where: { $0.apiProvider != nil }) ? 4 : 3); versioned.application = .claude }
        else if application == .workbuddy { versioned.schemaVersion = 5; versioned.application = .workbuddy }
        else if application == .wechat { versioned.schemaVersion = 6; versioned.application = .wechat }
        else if versioned.profiles.contains(where: { $0.directoryName != nil }) { versioned.schemaVersion = max(2, versioned.schemaVersion) }
        let data = try encoder.encode(versioned)
        guard data.count < 1_048_576 else {
            throw LauncherError("账号列表已达到大小上限，现有列表已保留。", "The profile registry reached its size limit. The existing registry is preserved.")
        }
        try writePrivate(data, to: registryURL)
    }

    /// Keep this lease alive across asynchronous launch and startup confirmation.
    public func beginLaunch(_ id: UUID) throws -> ProfileOperationLease {
        let lease = try acquireOperation(id)
        do {
            try withLock {
                let profile = try currentProfile(id)
                guard profile.archived != true else { throw missingProfile() }
                for path in [root.appendingPathComponent("profiles"), paths(for: profile).root, paths(for: profile).desktop] {
                    try rejectSymlink(path)
                }
                try requireStopped(profile)
            }
            return lease
        } catch {
            lease.release()
            throw error
        }
    }

    private func acquireOperation(_ id: UUID) throws -> ProfileOperationLease {
        try ensurePrivateDirectory(root)
        let directory = root.appendingPathComponent(".operations")
        try ensurePrivateDirectory(directory)
        return try ProfileOperationLease(url: directory.appendingPathComponent(id.uuidString.lowercased() + ".lock"))
    }

    private func withProfileOperation<T>(_ id: UUID, _ action: () throws -> T) throws -> T {
        let lease = try acquireOperation(id)
        defer { lease.release() }
        return try withLock(action)
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
        try ProfileName.validate(raw, profiles: registry.profiles, excluding: id)
    }

    private func currentProfile(_ id: UUID) throws -> Profile {
        guard let profile = try loadUnlocked().profiles.first(where: { $0.id == id }) else { throw missingProfile() }
        return profile
    }

    private func requireStopped(_ profile: Profile) throws {
        if application != .codex && ProfileProcessIdentity.mayBeUsing(paths(for: profile), application: application) {
            throw LauncherError("请先退出这个空间的 \(application.name)，再修改或移除空间。", "Quit this profile’s \(application.name) before changing or removing it.")
        }
        let lockPID = (try? fm.destinationOfSymbolicLink(atPath: paths(for: profile).singletonLock.path)).flatMap(SingletonLock.processID)
        for pid in [profile.receipt?.pid, lockPID].compactMap({ $0 }) where pid > 0 {
            guard kill(pid, 0) != 0 && errno != EPERM else {
                throw LauncherError("请先退出这个空间的 \(application.name)，再修改连接设置或移至废纸篓。", "Quit this profile's \(application.name) before changing its connection or moving it to the Trash.")
            }
        }
    }

    private func unsupportedAPI() -> LauncherError {
        LauncherError("此应用尚未提供 API Key 配置。", "This application does not provide API-key configuration.")
    }



    private func missingProfile() -> LauncherError {
        LauncherError("找不到这个账号空间，请刷新后重试。", "Profile not found. Refresh and try again.")
    }
}

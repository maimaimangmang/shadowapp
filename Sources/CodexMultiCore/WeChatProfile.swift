import AppKit
import CryptoKit
import Darwin
import Foundation

/// Local compatibility adapter for the single exercised Mac App Store build.
/// Never changes the source installation or re-signs a previously prepared profile.
public enum WeChatProfile {
    public static let version = "4.1.15"
    public static let build = "270115"
    public static let sourceHash = "0a6eb182d2ccf2bd005d778d2be8f3e675df3bfa7a7e9c904348e93d0ae8a10a"
    private static let fm = FileManager.default
    private static let removedExtensions: Set<String> = ["WeChatMacShare.appex", "WeChatFileProviderExtension.appex"]
    private static let identityKeys: Set<String> = ["com.apple.application-identifier", "com.apple.developer.team-identifier", "com.apple.security.application-groups"]
    private static let sandboxKeys: Set<String> = [
        "com.apple.security.app-sandbox", "com.apple.security.cs.allow-jit",
        "com.apple.security.device.audio-input", "com.apple.security.device.camera",
        "com.apple.security.files.bookmarks.app-scope", "com.apple.security.files.downloads.read-write",
        "com.apple.security.files.user-selected.read-write", "com.apple.security.network.client",
        "com.apple.security.network.server", "com.apple.security.personal-information.location",
        "com.apple.security.personal-information.photos-library", "com.apple.security.print"
    ]

    public struct Manifest: Codable {
        public let schemaVersion: Int
        public let profileID: UUID
        public let bundleIdentifier: String
        public let sourceVersion: String
        public let sourceBuild: String
        public let sourceSHA256: String
        public let integrity: [String: String]
    }

    private static let sealedFiles = ["Contents/MacOS/WeChat", "Contents/Info.plist", "Contents/_CodeSignature/CodeResources"]

    public static func validateSource(_ source: URL) throws {
        #if !arch(arm64)
        throw LauncherError("微信多开暂仅在 Apple Silicon 上验证，请使用受支持的设备。", "WeChat profiles are currently verified only on Apple Silicon.")
        #else
        let info = try plist(source.appendingPathComponent("Contents/Info.plist"))
        guard info["CFBundleIdentifier"] as? String == ManagedApplication.wechat.bundleIdentifier,
              info["CFBundleExecutable"] as? String == "WeChat",
              info["CFBundleShortVersionString"] as? String == version,
              info["CFBundleVersion"] as? String == build,
              try digest(source.appendingPathComponent("Contents/MacOS/WeChat")) == sourceHash else {
            throw LauncherError("微信多开暂仅支持 Mac App Store 版 4.1.15（270115）。当前版本尚未验证，已有数据已保留。", "WeChat profiles currently support only Mac App Store 4.1.15 (270115). This build is unverified; existing data is preserved.")
        }
        _ = try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", "=anchor apple generic and identifier \"com.tencent.xinWeChat\"", source.path])
        let entitlements = try permissions(source)
        guard entitlements["com.apple.security.app-sandbox"] as? Bool == true,
              Set(entitlements.keys).isSubset(of: sandboxKeys.union(identityKeys)) else { throw invalid() }
        let plugins = source.appendingPathComponent("Contents/PlugIns")
        try rejectSymlink(plugins)
        guard Set(try fm.contentsOfDirectory(atPath: plugins.path)) == removedExtensions else { throw invalid() }
        for name in removedExtensions {
            let plugin = plugins.appendingPathComponent(name)
            try rejectSymlink(plugin)
            guard try plugin.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw invalid() }
        }
        #endif
    }

    /// Caller must hold the profile operation lease. All expensive work runs off the UI actor.
    public static func prepare(source: URL, paths: ProfilePaths) throws -> URL {
        try rejectSymlink(paths.root)
        try rejectSymlink(paths.wechatApplication)
        try rejectSymlink(paths.wechatManifest)
        if fm.fileExists(atPath: paths.wechatApplication.path) || fm.fileExists(atPath: paths.wechatManifest.path) {
            try validate(paths: paths)
            return paths.wechatApplication
        }
        guard !hasLiveProcesses(paths) else { throw running() }
        // An existing container without its receipt might contain user data. Never adopt it.
        guard !fm.fileExists(atPath: paths.wechatContainer.path) else {
            throw LauncherError("此空间已有微信数据，但缺少应用校验文件。请恢复原空间文件夹，数据不会被覆盖。", "This profile has WeChat data but no app receipt. Restore its original profile folder; data will not be overwritten.")
        }
        try validateSource(source)
        let staging = paths.root.appendingPathComponent(".prepare-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) } // Only our unlaunched staging directory.
        let app = staging.appendingPathComponent("WeChat.app")
        // APFS copy-on-write avoids duplicating all application bytes at creation.
        // Unsupported filesystems fail visibly, leaving the registered space retryable.
        _ = try command("/bin/cp", ["-cR", source.path, app.path])
        for name in removedExtensions {
            let copied = app.appendingPathComponent("Contents/PlugIns/" + name)
            try rejectSymlink(copied)
            try fm.removeItem(at: copied)
        }
        let infoFile = app.appendingPathComponent("Contents/Info.plist")
        var info = try plist(infoFile)
        info["CFBundleIdentifier"] = paths.wechatIdentifier
        info["TeamIdentifier"] = "group."
        info.removeValue(forKey: "CFBundleURLTypes")
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoFile, options: .atomic)
        var entitlements = try permissions(source).filter { sandboxKeys.contains($0.key) }
        entitlements["com.apple.security.application-groups"] = ["group." + paths.wechatIdentifier]
        entitlements["com.apple.security.cs.disable-library-validation"] = true
        let entitlementFile = staging.appendingPathComponent("entitlements.plist")
        try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0).write(to: entitlementFile)
        // Do not use --deep when signing: child executables retain sandbox inheritance.
        _ = try command("/usr/bin/codesign", ["--force", "--sign", "-", "--options", "runtime", "--entitlements", entitlementFile.path, app.path])
        var hashes: [String: String] = [:]
        for relative in sealedFiles { hashes[relative] = try digest(app.appendingPathComponent(relative)) }
        let manifest = Manifest(schemaVersion: 1, profileID: paths.id, bundleIdentifier: paths.wechatIdentifier,
                                sourceVersion: version, sourceBuild: build, sourceSHA256: sourceHash, integrity: hashes)
        try validate(app: app, manifest: manifest, paths: paths)
        guard try digest(source.appendingPathComponent("Contents/MacOS/WeChat")) == sourceHash else { throw invalid() }
        let encoded = try JSONEncoder().encode(manifest)
        let stagedManifest = staging.appendingPathComponent("wechat.json")
        try encoded.write(to: stagedManifest, options: .withoutOverwriting)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stagedManifest.path)
        // Never overwrite an existing application. On publication failure, only undo this new copy.
        try fm.moveItem(at: app, to: paths.wechatApplication)
        do { try fm.moveItem(at: stagedManifest, to: paths.wechatManifest) }
        catch { try? fm.removeItem(at: paths.wechatApplication); throw error }
        return paths.wechatApplication
    }

    public static func validate(paths: ProfilePaths) throws {
        try rejectSymlink(paths.root)
        try rejectSymlink(paths.wechatManifest)
        let attrs = try fm.attributesOfItem(atPath: paths.wechatManifest.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.size] as? NSNumber)?.intValue ?? 0 < 16_384 else { throw invalid() }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: paths.wechatManifest))
        try validate(app: paths.wechatApplication, manifest: manifest, paths: paths)
    }

    public static func preparedInstallation(paths: ProfilePaths) throws -> CodexInstallation {
        try validate(paths: paths)
        return CodexInstallation(url: paths.wechatApplication, version: version, application: .wechat)
    }

    private static func validate(app: URL, manifest: Manifest, paths: ProfilePaths) throws {
        try rejectSymlink(app)
        guard manifest.schemaVersion == 1, manifest.profileID == paths.id,
              manifest.bundleIdentifier == paths.wechatIdentifier, manifest.sourceVersion == version,
              manifest.sourceBuild == build, manifest.sourceSHA256 == sourceHash,
              Set(manifest.integrity.keys) == Set(sealedFiles) else { throw invalid() }
        for relative in sealedFiles {
            let file = app.appendingPathComponent(relative)
            try rejectSymlink(file)
            guard try digest(file) == manifest.integrity[relative] else { throw invalid() }
        }
        let info = try plist(app.appendingPathComponent("Contents/Info.plist"))
        guard info["CFBundleIdentifier"] as? String == paths.wechatIdentifier,
              info["CFBundleExecutable"] as? String == "WeChat",
              info["CFBundleShortVersionString"] as? String == version,
              info["CFBundleVersion"] as? String == build,
              info["TeamIdentifier"] as? String == "group.", info["CFBundleURLTypes"] == nil else { throw invalid() }
        let permissions = try permissions(app)
        guard permissions["com.apple.security.app-sandbox"] as? Bool == true,
              permissions["com.apple.security.cs.disable-library-validation"] as? Bool == true,
              permissions["com.apple.security.application-groups"] as? [String] == ["group." + paths.wechatIdentifier],
              Set(permissions.keys).isSubset(of: sandboxKeys.union(["com.apple.security.application-groups", "com.apple.security.cs.disable-library-validation"])) else { throw invalid() }
        _ = try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let signature = try command("/usr/bin/codesign", ["-dv", app.path]).error
        guard signature.range(of: #"flags=0x[0-9a-f]+\([^\n)]*\bruntime\b"#, options: .regularExpression) != nil else { throw invalid() }
        guard let items = fm.enumerator(at: app, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) else { throw invalid() }
        var helpers: [URL] = [app.appendingPathComponent("Contents/Frameworks/crashpad_handler")]
        for case let file as URL in items {
            if ["appex", "xpc"].contains(file.pathExtension) { throw invalid() }
            if file.pathExtension == "app" { helpers.append(file) }
        }
        guard helpers.count == 9 else { throw invalid() }
        for helper in helpers {
            try rejectSymlink(helper)
            let e = try self.permissions(helper)
            guard e["com.apple.security.app-sandbox"] as? Bool == true,
                  e["com.apple.security.inherit"] as? Bool == true,
                  Set(e.keys).isSubset(of: ["com.apple.security.app-sandbox", "com.apple.security.inherit", "com.apple.security.cs.allow-jit"]) else { throw invalid() }
        }
    }

    public static func isManagedIdentifier(_ identifier: String) -> Bool {
        identifier.range(of: #"^org\.shadowapp\.wechat\.space\.[0-9a-f]{32}$"#, options: .regularExpression) != nil
    }

    public static func matches(pid: Int32, bundleIdentifier: String?, bundleURL: URL?, paths: ProfilePaths) -> Bool {
        bundleIdentifier == paths.wechatIdentifier &&
        bundleURL?.resolvingSymlinksInPath().path == paths.wechatApplication.resolvingSymlinksInPath().path &&
        executablePath(pid) == paths.wechatApplication.appendingPathComponent("Contents/MacOS/WeChat").resolvingSymlinksInPath().path
    }

    public static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard pid > 0, proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path
    }

    /// Includes orphaned helpers so an app copy cannot be trashed while still executing.
    public static func hasLiveProcesses(_ paths: ProfilePaths) -> Bool {
        if NSRunningApplication.runningApplications(withBundleIdentifier: paths.wechatIdentifier).contains(where: { !$0.isTerminated }) { return true }
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return true }
        var pids = [Int32](repeating: 0, count: Int(count) + 128)
        let used = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard used > 0 else { return true }
        let prefix = paths.wechatApplication.resolvingSymlinksInPath().path + "/"
        return pids.prefix(Int(used)).contains { executablePath($0)?.hasPrefix(prefix) == true }
    }

    /// Fail closed if the local runtime cannot confirm the sandbox. No unsandboxed fallback.
    public static func sandboxActive(pid: Int32) -> Bool {
        typealias Check = @convention(c) (Int32, UnsafePointer<CChar>?, Int32) -> Int32
        guard pid > 0, let library = dlopen("/usr/lib/libsandbox.1.dylib", RTLD_LAZY) else { return false }
        defer { dlclose(library) }
        guard let symbol = dlsym(library, "sandbox_check") else { return false }
        return unsafeBitCast(symbol, to: Check.self)(pid, nil, 0) == 1
    }

    private static func permissions(_ app: URL) throws -> [String: Any] {
        let data = try command("/usr/bin/codesign", ["-d", "--entitlements", ":-", app.path]).output
        guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw invalid() }
        return result
    }

    private static func plist(_ file: URL) throws -> [String: Any] {
        guard let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any] else { throw invalid() }
        return value
    }

    private static func digest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func rejectSymlink(_ url: URL) throws {
        guard (try? fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) != .typeSymbolicLink else { throw invalid() }
    }

    private static func command(_ executable: String, _ arguments: [String]) throws -> (output: Data, error: String) {
        let temporary = fm.temporaryDirectory.appendingPathComponent("shadowapp-command-" + UUID().uuidString)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: temporary) }
        let outURL = temporary.appendingPathComponent("out"), errURL = temporary.appendingPathComponent("err")
        guard fm.createFile(atPath: outURL.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              fm.createFile(atPath: errURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw invalid() }
        let out = try FileHandle(forWritingTo: outURL), err = try FileHandle(forWritingTo: errURL)
        defer { try? out.close(); try? err.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let error = String(decoding: try Data(contentsOf: errURL), as: UTF8.self)
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw LauncherError("微信副本准备或校验失败，空间数据已保留。\n\(error.prefix(600))", "WeChat preparation or verification failed. Profile data is preserved.\n\(error.prefix(600))")
        }
        return (try Data(contentsOf: outURL), error)
    }

    private static func invalid() -> LauncherError {
        LauncherError("微信副本未通过完整性或沙盒检查，已停止打开。请保留空间文件夹和数据，不要用其他版本覆盖。", "The WeChat copy failed integrity or sandbox checks. Launch stopped. Preserve its profile folder and data; do not overwrite it with another build.")
    }
    private static func running() -> LauncherError {
        LauncherError("这个微信空间仍在运行，请先退出对应窗口。", "This WeChat profile is still running. Quit its window first.")
    }
}

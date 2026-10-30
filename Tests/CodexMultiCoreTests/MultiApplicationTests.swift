import Foundation
import CodexMultiCore
import CodexMultiState

@MainActor
func runMultiApplicationTests() -> Int {
    let fm = FileManager.default
    let tests: [(String, () throws -> Void)] = [
        ("WorkBuddy uses separate home and directories without inheriting credentials", {
            let paths = ProfilePaths(base: URL(fileURLWithPath: "/tmp/workbuddy fixture"), id: UUID())
            let plan = LaunchPlan(paths: paths, application: .workbuddy)
            XCTAssertTrue(plan.createsNewInstance)
            XCTAssertFalse(ManagedApplication.workbuddy.supportsAPIProfiles)
            XCTAssertEqual(plan.environment["HOME"], paths.workbuddyHome.path)
            XCTAssertEqual(plan.environment["WORKBUDDY_CONFIG_DIR"], paths.workbuddyConfig.path)
            XCTAssertEqual(plan.environment["WORKBUDDY_USER_DATA_DIR"], paths.desktop.path)
            let env = DesktopLauncher.workbuddyEnvironment(inherited: ["HOME": "/original", "PATH": "/usr/bin", "ANTHROPIC_API_KEY": "fixture", "NODE_OPTIONS": "fixture", "WORKBUDDY_CONFIG_DIR": "/original"], plan: plan)
            XCTAssertEqual(env["PATH"], "/usr/bin")
            XCTAssertEqual(env["HOME"], paths.workbuddyHome.path)
            XCTAssertNil(env["ANTHROPIC_API_KEY"])
            XCTAssertNil(env["NODE_OPTIONS"])
            XCTAssertTrue(ProfileProcessIdentity.matches(arguments: plan.arguments, desktop: paths.desktop))
            XCTAssertNil(LaunchPlan(paths: paths).environment["HOME"])
            let pid = ProcessInfo.processInfo.processIdentifier
            let start = ProfileProcessIdentity.startDate(pid: pid)
            XCTAssertTrue(start != nil)
            XCTAssertEqual(start, ProfileProcessIdentity.startDate(pid: pid))
            XCTAssertNil(ProfileProcessIdentity.startDate(pid: -1))
        }),
        ("WorkBuddy prepares separate accounts, preserves settings, refuses API injection", {
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let store = ProfileStore(root: root, application: .workbuddy)
            _ = try store.load()
            let first = try store.create(name: "First")
            let second = try store.create(name: "Second")
            let a = try store.prepare(first), b = try store.prepare(second)
            XCTAssertNotEqual(a.workbuddyAuth, b.workbuddyAuth)
            XCTAssertTrue(fm.fileExists(atPath: a.workbuddyAuth.path))
            XCTAssertFalse(fm.fileExists(atPath: a.codex.path))
            XCTAssertFalse(fm.fileExists(atPath: a.claudeConfig.path))
            try Data(#"{"startupForceAutoUpdate":true,"theme":"dark"}"#.utf8).write(to: a.workbuddyAppConfig)
            _ = try store.prepare(first)
            let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: a.workbuddyAppConfig)) as! [String: Any]
            XCTAssertEqual(settings["startupForceAutoUpdate"] as? Bool, false)
            XCTAssertEqual(settings["theme"] as? String, "dark")
            XCTAssertEqual(try fm.attributesOfItem(atPath: a.workbuddyAppConfig.path)[.posixPermissions] as? Int, 0o600)
            XCTAssertEqual(try store.load().schemaVersion, 5)
            let before = try Data(contentsOf: root.appendingPathComponent("profiles.json"))
            let provider = APIProvider(name: "Fixture", baseURL: "https://example.invalid/v1", modelID: "fixture")
            XCTAssertThrowsError(try store.create(name: "API", provider: provider, apiKey: "fixture"))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("profiles.json")), before)
        }),
        ("WorkBuddy rejects redirected home ancestors and malformed settings", {
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let store = ProfileStore(root: root, application: .workbuddy)
            _ = try store.load()
            let profile = try store.create(name: "First")
            let paths = try store.prepare(profile)
            let malformed = Data("[]".utf8)
            try malformed.write(to: paths.workbuddyAppConfig)
            XCTAssertThrowsError(try store.prepare(profile))
            XCTAssertEqual(try Data(contentsOf: paths.workbuddyAppConfig), malformed)
            let library = paths.workbuddyHome.appendingPathComponent("Library")
            try fm.removeItem(at: library)
            try fm.createSymbolicLink(at: library, withDestinationURL: root)
            XCTAssertThrowsError(try store.prepare(profile))
            XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("Application Support").path))
        }),
        ("WorkBuddy upgrades empty shortcut registries and rejects unsupported profile metadata", {
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let store = ProfileStore(root: root, application: .workbuddy)
            var registry = try store.load()
            let file = root.appendingPathComponent("profiles.json")
            registry.schemaVersion = 3
            try JSONEncoder().encode(registry).write(to: file)
            _ = try store.create(name: "New")
            XCTAssertEqual(try store.load().schemaVersion, 5)
            XCTAssertThrowsError(try ProfileStore(root: root, application: .claude).load())
            registry = try store.load()
            registry.profiles[0].apiProvider = APIProvider(name: "Fixture", baseURL: "https://example.invalid", modelID: "fixture")
            try JSONEncoder().encode(registry).write(to: file)
            XCTAssertThrowsError(try store.load())
            registry.profiles[0].apiProvider = nil
            registry.schemaVersion = 3
            try JSONEncoder().encode(registry).write(to: file)
            XCTAssertThrowsError(try store.load())
        }),
        ("WorkBuddy unverified bundles are rejected even with a matching version", {
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let contents = root.appendingPathComponent("WorkBuddy.app/Contents")
            try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            try fm.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
            let plist = ["CFBundleIdentifier": ManagedApplication.workbuddy.bundleIdentifier, "CFBundleExecutable": "Electron", "CFBundleShortVersionString": "5.8.3"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
            let exe = contents.appendingPathComponent("MacOS/Electron")
            try Data("fixture".utf8).write(to: exe)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
            try Data("WORKBUDDY_CONFIG_DIR".utf8).write(to: contents.appendingPathComponent("Resources/app.asar"))
            XCTAssertThrowsError(try CodexInstallation.inspect(contents.deletingLastPathComponent(), application: .workbuddy))
        }),
        ("Claude launch isolates desktop and Code without overriding HOME", {
            let paths = ProfilePaths(base: URL(fileURLWithPath: "/tmp/with spaces/Claude"), id: UUID())
            let plan = LaunchPlan(paths: paths, application: .claude)
            XCTAssertEqual(plan.arguments, ["--user-data-dir=\(paths.desktop.path)"])
            XCTAssertEqual(plan.environment["CLAUDE_CONFIG_DIR"], paths.claudeConfig.path)
            XCTAssertEqual(plan.environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"], paths.claudeConfig.path)
            XCTAssertNil(plan.environment["HOME"])
            XCTAssertNil(plan.environment["CLAUDE_USER_DATA_DIR"])
            XCTAssertNil(plan.environment["CODEX_HOME"])
        }),
        ("Claude process matching requires an exact unambiguous directory argument", {
            let directory = URL(fileURLWithPath: "/tmp/Claude Work/desktop")
            XCTAssertTrue(ProfileProcessIdentity.matches(arguments: ["Claude", "--user-data-dir=\(directory.path)"], desktop: directory))
            XCTAssertFalse(ProfileProcessIdentity.matches(arguments: ["Claude", "--user-data-dir=\(directory.path)-other"], desktop: directory))
            XCTAssertFalse(ProfileProcessIdentity.matches(arguments: ["Claude", "CLAUDE_USER_DATA_DIR=\(directory.path)"], desktop: directory))
            XCTAssertFalse(ProfileProcessIdentity.matches(arguments: ["Claude", "--user-data-dir=\(directory.path)", "--user-data-dir=/tmp/other"], desktop: directory))
            XCTAssertNil(ProfileProcessIdentity.arguments(pid: -1))
            XCTAssertEqual(ProfileProcessIdentity.arguments(pid: ProcessInfo.processInfo.processIdentifier), CommandLine.arguments)
        }),
        ("Claude prepare rejects redirected Code directory", {
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let store = ProfileStore(root: root, application: .claude)
            _ = try store.load()
            let profile = try store.create(name: "Work")
            let paths = try store.prepare(profile)
            try fm.removeItem(at: paths.claudeConfig)
            try fm.createSymbolicLink(at: paths.claudeConfig, withDestinationURL: root)
            XCTAssertThrowsError(try store.prepare(profile))
        }),
        ("Claude capability cannot be faked by copying only the environment marker", {
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let contents = root.appendingPathComponent("Claude.app/Contents")
            try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            try fm.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
            let plist = ["CFBundleIdentifier": ManagedApplication.claude.bundleIdentifier, "CFBundleExecutable": "Claude", "CFBundleShortVersionString": "4.29.0"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
            let exe = contents.appendingPathComponent("MacOS/Claude")
            try Data("fixture".utf8).write(to: exe)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
            try Data("CLAUDE_USER_DATA_DIR userData relocated CLAUDE_CONFIG_DIR".utf8).write(to: contents.appendingPathComponent("Resources/app.asar"))
            XCTAssertThrowsError(try CodexInstallation.inspect(contents.deletingLastPathComponent(), application: .claude))
        }),
        ("Claude and Codex registries names and data are independent", {
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let codex = ProfileStore(root: root)
            let claude = ProfileStore(root: ManagedApplication.claude.dataRoot(base: root), application: .claude)
            _ = try codex.load(); _ = try claude.load()
            let codexProfile = try codex.create(name: "Work")
            let claudeProfile = try claude.create(name: "Work")
            let before = try Data(contentsOf: root.appendingPathComponent("profiles.json"))
            let codexPaths = try codex.prepare(codexProfile)
            let claudePaths = try claude.prepare(claudeProfile)
            XCTAssertNotEqual(codexPaths.root, claudePaths.root)
            XCTAssertTrue(fm.fileExists(atPath: codexPaths.config.path))
            XCTAssertFalse(fm.fileExists(atPath: claudePaths.codex.path))
            XCTAssertTrue(fm.fileExists(atPath: claudePaths.desktop.path))
            XCTAssertEqual(try claude.load().schemaVersion, 3)
            XCTAssertEqual(try claude.load().application, .claude)
            XCTAssertEqual(try codex.load().schemaVersion, 2)
            try claude.rename(claudeProfile.id, to: "Renamed")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("profiles.json")), before)
            let model = AppModel(store: claude, automaticallyDiscover: false, refreshInterval: nil, runningInstances: { [] })
            XCTAssertEqual(model.application, .claude)
            XCTAssertEqual(model.profiles.map(\.name), ["Renamed"])
        }),
        ("mismatched application roots fail without rewriting registries", {
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let claude = ProfileStore(root: root, application: .claude)
            _ = try claude.load()
            _ = try claude.create(name: "Claude")
            let file = root.appendingPathComponent("profiles.json")
            let data = try Data(contentsOf: file)
            XCTAssertThrowsError(try ProfileStore(root: root).load())
            XCTAssertEqual(try Data(contentsOf: file), data)
        }),
        ("Claude invalid model IDs are rejected before credentials or metadata are saved", {
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let store = ProfileStore(root: root, application: .claude)
            _ = try store.load()
            let before = try Data(contentsOf: root.appendingPathComponent("profiles.json"))
            XCTAssertThrowsError(try store.create(name: "Wrong mode", provider: APIProvider(name: "Fixture", baseURL: "https://example.invalid/v1", modelID: "fixture"), apiKey: "fixture-only"))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("profiles.json")), before)
            XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("profiles").path))
        }),
        ("legacy Codex registries retain paths and cannot be interpreted as Claude", {
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let codex = ProfileStore(root: root)
            var registry = try codex.load()
            registry.schemaVersion = 1
            let profile = Profile(name: "Legacy")
            registry.profiles = [profile]
            let file = root.appendingPathComponent("profiles.json")
            let data = try JSONEncoder().encode(registry)
            try data.write(to: file)
            XCTAssertThrowsError(try ProfileStore(root: root, application: .claude).load())
            XCTAssertEqual(try Data(contentsOf: file), data)
            let paths = try codex.prepare(profile)
            XCTAssertEqual(paths.root.lastPathComponent, profile.id.uuidString.lowercased())
            XCTAssertEqual(try codex.load().profiles.first?.id, profile.id)
        })
    ]
    for (name, test) in tests {
        let before = failures
        do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }
        if before == failures { print("PASS \(name)") }
    }
    return tests.count
}

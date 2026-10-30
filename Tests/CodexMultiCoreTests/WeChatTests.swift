import Foundation
import CodexMultiCore
import CodexMultiState

@MainActor
func runWeChatTests() -> Int {
    let fm = FileManager.default
    func fixture(_ body: (URL, ProfileStore, Profile, ProfilePaths) throws -> Void) throws {
        let root = fm.temporaryDirectory.appendingPathComponent("wechat-tests-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let store = ProfileStore(root: root, application: .wechat)
        _ = try store.load()
        let profile = try store.create(name: "测试空间")
        let paths = try store.prepare(profile)
        try body(root, store, profile, paths)
    }
    let tests: [(String, () throws -> Void)] = [
        ("WeChat identities and containers are unique and survive rename and archive", {
            try fixture { _, store, first, paths in
                let second = try store.create(name: "另一个")
                XCTAssertNotEqual(paths.wechatIdentifier, store.paths(for: second).wechatIdentifier)
                XCTAssertNotEqual(paths.wechatContainer, store.dataFolder(for: second))
                XCTAssertEqual(store.dataFolder(for: first), paths.wechatContainer)
                XCTAssertTrue(WeChatProfile.isManagedIdentifier(paths.wechatIdentifier))
                XCTAssertFalse(WeChatProfile.isManagedIdentifier(ManagedApplication.wechat.bundleIdentifier))
                XCTAssertFalse(WeChatProfile.isManagedIdentifier("org.shadowapp.wechat.space.other"))
                try store.rename(first.id, to: "改名")
                XCTAssertEqual(store.paths(for: try XCTUnwrap(store.load().profiles.first)).wechatContainer, paths.wechatContainer)
                XCTAssertFalse(fm.fileExists(atPath: paths.codex.path))
                XCTAssertFalse(fm.fileExists(atPath: paths.workbuddyHome.path))
                XCTAssertFalse(fm.fileExists(atPath: paths.desktop.path))
                let plan = LaunchPlan(paths: paths, application: .wechat)
                XCTAssertTrue(plan.environment.isEmpty)
                XCTAssertTrue(plan.arguments.isEmpty)
            }
        }),
        ("WeChat archive preserves files and restores the original profile identity", {
            try fixture { _, store, profile, paths in
                let sentinel = paths.root.appendingPathComponent("fixture.txt")
                try Data("keep".utf8).write(to: sentinel)
                try store.setWeChatArchived(profile.id, archived: true)
                XCTAssertEqual(try String(contentsOf: sentinel), "keep")
                XCTAssertThrowsError(try store.beginLaunch(profile.id))
                XCTAssertThrowsError(try store.prepare(profile))
                XCTAssertThrowsError(try store.moveToTrash(profile.id))
                let model = AppModel(store: store, automaticallyDiscover: false, refreshInterval: nil)
                XCTAssertTrue(model.profiles.isEmpty)
                XCTAssertEqual(model.archivedProfiles.first?.id, profile.id)
                model.launch(profile)
                XCTAssertTrue(model.error != nil)
                model.restoreWeChat(profile)
                XCTAssertEqual(model.profiles.first?.id, profile.id)
                XCTAssertTrue(model.archivedProfiles.isEmpty)
                XCTAssertEqual(store.paths(for: try XCTUnwrap(model.profiles.first)), paths)
                XCTAssertEqual(try String(contentsOf: sentinel), "keep")
            }
        }),
        ("WeChat helper processes block archive and preparation without a receipt", {
            try fixture { _, store, profile, paths in
                let helper = paths.wechatApplication.appendingPathComponent("Contents/MacOS/sleep")
                try fm.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: helper)
                let process = Process()
                process.executableURL = helper
                process.arguments = ["30"]
                try process.run()
                defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
                XCTAssertTrue(WeChatProfile.hasLiveProcesses(paths))
                XCTAssertThrowsError(try store.setWeChatArchived(profile.id, archived: true))
                XCTAssertThrowsError(try store.beginLaunch(profile.id))
                XCTAssertFalse(WeChatProfile.matches(pid: process.processIdentifier, bundleIdentifier: paths.wechatIdentifier, bundleURL: paths.wechatApplication, paths: paths))
                XCTAssertFalse(WeChatProfile.sandboxActive(pid: process.processIdentifier))
            }
        }),
        ("WeChat schema rejects API metadata and cross-application use without rewriting", {
            try fixture { root, store, _, _ in
                XCTAssertEqual(try store.load().schemaVersion, 6)
                let file = root.appendingPathComponent("profiles.json")
                let before = try Data(contentsOf: file)
                let provider = APIProvider(name: "fixture", baseURL: "https://example.invalid", modelID: "fixture")
                XCTAssertThrowsError(try store.create(name: "key", provider: provider, apiKey: "fixture"))
                XCTAssertThrowsError(try ProfileStore(root: root, application: .workbuddy).load())
                XCTAssertEqual(try Data(contentsOf: file), before)
                var bad = try store.load()
                bad.profiles[0].apiProvider = provider
                try JSONEncoder().encode(bad).write(to: file)
                XCTAssertThrowsError(try store.load())
            }
        }),
        ("WeChat unopened data folders are not fabricated and redirected copies are refused", {
            try fixture { root, store, profile, paths in
                XCTAssertThrowsError(try store.folderURL(for: profile))
                XCTAssertFalse(fm.fileExists(atPath: paths.wechatContainer.path))
                try fm.createSymbolicLink(at: paths.wechatApplication, withDestinationURL: root)
                XCTAssertThrowsError(try WeChatProfile.prepare(source: root, paths: paths))
                XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("profiles.json").path))
            }
        }),
        ("WeChat rejects a claimed supported version without verified original binary", {
            try fixture { root, _, _, paths in
                let source = root.appendingPathComponent("Fake.app")
                let contents = source.appendingPathComponent("Contents")
                try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
                let info = ["CFBundleIdentifier": "com.tencent.xinWeChat", "CFBundleExecutable": "WeChat", "CFBundleShortVersionString": "4.1.15", "CFBundleVersion": "270115"]
                try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
                let executable = contents.appendingPathComponent("MacOS/WeChat")
                try Data("fixture only".utf8).write(to: executable)
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
                XCTAssertThrowsError(try CodexInstallation.inspect(source, application: .wechat))
                XCTAssertThrowsError(try WeChatProfile.prepare(source: source, paths: paths))
                XCTAssertFalse(fm.fileExists(atPath: paths.wechatApplication.path))
                XCTAssertFalse(fm.fileExists(atPath: paths.wechatManifest.path))
            }
        }),
        ("WeChat interrupted or altered receipts are preserved and never silently rebuilt", {
            try fixture { root, _, _, paths in
                let broken = Data("incomplete receipt".utf8)
                try broken.write(to: paths.wechatManifest)
                XCTAssertThrowsError(try WeChatProfile.prepare(source: root, paths: paths))
                XCTAssertEqual(try Data(contentsOf: paths.wechatManifest), broken)
                XCTAssertFalse(fm.fileExists(atPath: paths.wechatApplication.path))
            }
        })
    ]
    for (name, test) in tests {
        let before = failures
        do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }
        if before == failures { print("PASS \(name)") }
    }
    return tests.count
}

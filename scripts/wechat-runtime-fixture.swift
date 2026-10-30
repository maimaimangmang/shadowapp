// Opt-in local test. Never logs in, copies credentials, or changes existing app instances.
import AppKit
import CodexMultiCore
import CodexMultiState
import Foundation

struct WeChatSmokeFailure: Error { let message: String }
@main struct WeChatSmoke {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        guard CommandLine.arguments.count == 2 else { fatalError("Usage: wechat-runtime-fixture NEW_FIXTURE_DIRECTORY") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        guard !fm.fileExists(atPath: root.path) else { throw WeChatSmokeFailure(message: "Fixture directory must not exist") }
        let store = ProfileStore(root: root, application: .wechat)
        let model = AppModel(store: store, automaticallyDiscover: false, refreshInterval: nil)
        await model.checkApplications([URL(fileURLWithPath: "/Applications/WeChat.app")]).value
        guard model.installation != nil else { throw WeChatSmokeFailure(message: model.installationIssue ?? "Installation unavailable") }
        let original = DesktopLauncher.runningInstances(application: .wechat)
        var owned: [NSRunningApplication] = []
        var failure: Error?
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw WeChatSmokeFailure(message: message) }
        }
        func report(_ value: String) { print("PASS " + value); fflush(stdout) }
        func launch(_ profile: Profile) async throws -> NSRunningApplication {
            model.launch(profile)
            for _ in 0..<240 {
                try await Task.sleep(nanoseconds: 250_000_000)
                model.refresh()
                if let app = DesktopLauncher.runningWeChatProfile(store.paths(for: profile)), !owned.contains(where: { $0.processIdentifier == app.processIdentifier }) { owned.append(app) }
                if model.error != nil || model.status(profile) == .running { break }
            }
            try check(model.error == nil && model.status(profile) == .running, model.error ?? "Launch not confirmed")
            guard let app = DesktopLauncher.runningWeChatProfile(store.paths(for: profile)) else { throw WeChatSmokeFailure(message: "No matching app") }
            try check(WeChatProfile.sandboxActive(pid: app.processIdentifier), "Runtime sandbox missing")
            return app
        }
        func quit(_ app: NSRunningApplication, paths: ProfilePaths) async throws {
            if !app.isTerminated { _ = app.terminate() }
            for _ in 0..<80 {
                if !WeChatProfile.hasLiveProcesses(paths) { return }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            throw WeChatSmokeFailure(message: "Fixture process still running; files retained")
        }
        do {
            try model.create(name: "微信验收一")
            let first = model.profiles[0]
            let firstApp = try await launch(first)
            let a = store.paths(for: first)
            try check(fm.fileExists(atPath: a.wechatContainer.path), "System container not created")
            report("first copy launched with its unique bundle identity and sandbox")
            model.launch(first)
            try check(DesktopLauncher.runningWeChatProfile(a)?.processIdentifier == firstApp.processIdentifier, "Repeated open created a different process")
            do { try store.setWeChatArchived(first.id, archived: true); throw WeChatSmokeFailure(message: "Live archive allowed") } catch is LauncherError { }
            report("repeated open focuses existing PID; live archive blocked")
            try model.create(name: "微信验收二")
            let second = model.profiles.first { $0.id != first.id }!
            let secondApp = try await launch(second)
            let b = store.paths(for: second)
            try check(firstApp.processIdentifier != secondApp.processIdentifier && !firstApp.isTerminated, "Copies are not independent")
            try check(a.wechatContainer != b.wechatContainer, "Shared container")
            try await Task.sleep(nanoseconds: 2_000_000_000)
            // Deliberately lose one process receipt; only the exact app path/identity can recover it.
            var registry = try store.load()
            registry.profiles[0].receipt = nil
            try JSONEncoder().encode(registry).write(to: root.appendingPathComponent("profiles.json"), options: .atomic)
            let recovered = AppModel(store: store, automaticallyDiscover: false, refreshInterval: nil)
            try check(recovered.runningCount == 2, "Receipt recovery failed")
            report("two separate unsigned-in copies; fresh launcher recovers missing receipt")
            try await quit(firstApp, paths: a)
            try check(!secondApp.isTerminated, "Targeted quit affected peer")
            try store.setWeChatArchived(first.id, archived: true)
            recovered.refresh()
            try check(recovered.archivedProfiles.count == 1 && recovered.profiles.count == 1, "Archive visibility failed")
            recovered.restoreWeChat(first)
            model.refresh()
            let relaunched = try await launch(first)
            try check(relaunched.processIdentifier != firstApp.processIdentifier && !secondApp.isTerminated, "Restart affected peer")
            report("targeted quit, archive/restore and relaunch preserve paths and peer")
            try await quit(relaunched, paths: a)
            try await quit(secondApp, paths: b)
            // Mutate only a fresh fixture's sealed app resource; launch must fail without rewriting it.
            let info = a.wechatApplication.appendingPathComponent("Contents/Info.plist")
            let originalInfo = try Data(contentsOf: info)
            var plist = try PropertyListSerialization.propertyList(from: originalInfo, format: nil) as! [String: Any]
            plist["CFBundleShortVersionString"] = "99.0"
            let tampered = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try tampered.write(to: info)
            model.refresh()
            model.launch(first)
            for _ in 0..<100 {
                try await Task.sleep(nanoseconds: 100_000_000)
                if model.error != nil { break }
            }
            try check(model.error != nil && !WeChatProfile.hasLiveProcesses(a), "Tampered copy was launched")
            try check(try Data(contentsOf: info) == tampered, "Tampered app silently overwritten")
            try originalInfo.write(to: info)
            try WeChatProfile.validate(paths: a)
            report("tampered copy blocked, preserved for repair, restored signature validates")
        } catch { failure = error }
        for app in owned where !app.isTerminated { _ = app.terminate() }
        for _ in 0..<80 {
            if owned.allSatisfy({ $0.isTerminated }) { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        for instance in original {
            try check(DesktopLauncher.application(matching: instance, application: .wechat) != nil, "Original instance stopped unexpectedly")
        }
        report("original WeChat process preserved; no account sign-in or messages performed")
        // Keep manifests for inspection. Cleanup must be explicit and must never touch other containers.
        print("Fixture: " + root.path)
        if let failure { print("FAIL: \(failure)"); exit(1) }
    }
}

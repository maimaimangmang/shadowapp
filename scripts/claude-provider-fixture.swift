import AppKit
import Foundation
import CodexMultiCore

struct FixtureFailure: Error { let reason: String }
@main struct ProviderFixture {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let endpoint = CommandLine.arguments[2]
        let store = ProfileStore(root: root, application: .claude)
        _ = try store.load()
        let installed = try CodexInstallation.inspect(URL(fileURLWithPath: "/Applications/Claude.app"), application: .claude)
        let existing = Set(DesktopLauncher.runningInstances(application: .claude).map(\.pid))
        var owned: [(NSRunningApplication, ProcessReceipt, ProfilePaths)] = []
        var failure: Error?
        do {
            for index in 1...2 {
                let provider = APIProvider(name: "Local fixture", baseURL: endpoint + "/profile\(index)", modelID: "fixture/claude-sonnet-4-5")
                let key = "fixture-claude-key-\(index)"
                let profile = try store.create(name: "API \(index)", provider: provider, apiKey: key)
                let paths = try store.prepare(profile)
                let result = try await ProviderConnectionProbe.check(provider: provider, key: key, application: .claude)
                guard result == .completed else { throw FixtureFailure(reason: "Messages probe failed") }
                // Explicit fixture-only discovery forces a native request without sending a chat or signing in.
                var config = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.claudeProvider)) as! [String: Any]
                config["modelDiscoveryEnabled"] = true
                try ClaudeProviderConfiguration.encode(config).write(to: paths.claudeProvider)
                let app = try await DesktopLauncher.open(application: installed.url, plan: LaunchPlan(paths: paths, application: .claude))
                guard !existing.contains(app.processIdentifier), let date = app.launchDate, let bundle = app.bundleURL else { throw FixtureFailure(reason: "Unexpected process") }
                let receipt = ProcessReceipt(pid: app.processIdentifier, launchedAt: date, bundlePath: bundle.resolvingSymlinksInPath().path)
                owned.append((app, receipt, paths))
                try store.record(receipt, for: profile.id)
                try await Task.sleep(nanoseconds: 8_000_000_000)
                guard DesktopLauncher.confirmsProfile(app, paths: paths, application: .claude) else { throw FixtureFailure(reason: "Profile process mismatch") }
                print("PASS native API fixture \(index) started in desktop-3p")
                fflush(stdout)
            }
            try await Task.sleep(nanoseconds: 12_000_000_000)
            guard owned.allSatisfy({ !$0.0.isTerminated }) else { throw FixtureFailure(reason: "An API instance exited") }
        } catch { failure = error }
        for (app, receipt, paths) in owned where !app.isTerminated {
            if let target = DesktopLauncher.application(matching: receipt, application: .claude), DesktopLauncher.confirmsProfile(target, paths: paths, application: .claude) { _ = target.terminate() }
        }
        for _ in 0..<80 {
            if owned.allSatisfy({ $0.0.isTerminated }) { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard owned.allSatisfy({ $0.0.isTerminated }) else { throw FixtureFailure(reason: "Fixture instances still running; preserve data") }
        if let failure { throw failure }
        for profile in try store.load().profiles {
            let paths = store.paths(for: profile)
            var config = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.claudeProvider)) as! [String: Any]
            config["modelDiscoveryEnabled"] = false
            try ClaudeProviderConfiguration.encode(config).write(to: paths.claudeProvider)
            var updated = profile.apiProvider!
            updated.modelID = "fixture/claude-opus-4-8"
            try store.updateProvider(profile.id, provider: updated, newAPIKey: nil)
            _ = try store.prepare(profile)
        }
        print("PASS both API fixtures exited normally; native-written config remains editable")
    }
}

// Explicit, local-only smoke test. Creates fresh unsigned-in profiles; never copies credentials.
import AppKit
import Foundation
import CodexMultiCore
import CodexMultiState

struct CheckFailure: Error { let message: String }
@main struct ClaudeSmoke {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Usage: claude-runtime-fixture /Applications/Claude.app") }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("claude-multi-check-" + UUID().uuidString)
        let store = ProfileStore(root: root, application: .claude)
        let model = AppModel(store: store, automaticallyDiscover: false, refreshInterval: nil)
        let existing = Set(DesktopLauncher.runningInstances(application: .claude).map(\.pid))
        await model.checkApplications([URL(fileURLWithPath: CommandLine.arguments[1])]).value
        guard model.installation != nil else { try fm.removeItem(at: root); throw CheckFailure(message: model.installationIssue ?? "No installation") }
        var owned: [(NSRunningApplication, ProcessReceipt, ProfilePaths)] = []
        var failure: Error?
        do {
            for name in ["first", "second"] {
                try model.create(name: name)
                let profile = try model.profiles.first(where: { $0.name == name }).unwrap("Missing fixture")
                model.launch(profile)
                for _ in 0..<240 {
                    try await Task.sleep(nanoseconds: 250_000_000)
                    model.refresh()
                    if let current = model.profiles.first(where: { $0.id == profile.id }),
                       let app = DesktopLauncher.trackedApplication(current, application: .claude), let receipt = current.receipt {
                        if !owned.contains(where: { $0.1.pid == receipt.pid }) && !existing.contains(receipt.pid) {
                            owned.append((app, receipt, store.paths(for: current)))
                        }
                    }
                    if model.status(profile) == .running || model.error != nil { break }
                }
                guard model.error == nil, model.status(profile) == .running else { throw CheckFailure(message: model.error ?? "Not running") }
                let paths = store.paths(for: profile)
                for _ in 0..<80 {
                    if fm.fileExists(atPath: paths.desktop.appendingPathComponent("config.json").path), fm.fileExists(atPath: paths.desktop.appendingPathComponent("Cookies").path) { break }
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
                guard fm.fileExists(atPath: paths.desktop.appendingPathComponent("config.json").path),
                      fm.fileExists(atPath: paths.desktop.appendingPathComponent("Cookies").path) else { throw CheckFailure(message: "Isolated config/Cookies missing") }
                guard try store.load().profiles.count == owned.count else { throw CheckFailure(message: "Unexpected process association") }
                do { try store.moveToTrash(profile.id); throw CheckFailure(message: "Live profile deletion allowed") }
                catch is LauncherError { }
                print("PASS \(name): independent PID, running status, config/Cookies, live deletion blocked")
                fflush(stdout)
            }
            guard owned.count == 2, owned.allSatisfy({ !$0.0.isTerminated }) else { throw CheckFailure(message: "Two instances are not alive") }
            let restored = AppModel(store: store, automaticallyDiscover: false, refreshInterval: nil)
            guard restored.runningCount == 2, restored.existingInstances.allSatisfy({ !owned.map { $0.1.pid }.contains($0.pid) }) else { throw CheckFailure(message: "Restored instance status is wrong") }
            // Simulate receipt loss after startup. The argv fallback must still block data removal.
            let registryURL = root.appendingPathComponent("profiles.json")
            var registry = try store.load()
            registry.profiles[0].receipt = nil
            try JSONEncoder().encode(registry).write(to: registryURL, options: .atomic)
            restored.refresh()
            guard restored.status(registry.profiles[0]) == .untracked else { throw CheckFailure(message: "Receipt loss must require review") }
            do { try store.moveToTrash(registry.profiles[0].id); throw CheckFailure(message: "Unrecorded live profile deletion allowed") }
            catch is LauncherError { }
            print("PASS two simultaneous instances, registry reload, missing-receipt protection")
        } catch { failure = error }
        for (app, receipt, paths) in owned {
            if let current = DesktopLauncher.application(matching: receipt, application: .claude),
               DesktopLauncher.confirmsProfile(current, paths: paths, application: .claude), !app.isTerminated {
                _ = current.terminate()
            }
        }
        for _ in 0..<80 {
            if owned.allSatisfy({ $0.0.isTerminated }) { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        if owned.allSatisfy({ $0.0.isTerminated }) { try fm.removeItem(at: root) }
        else { print("Fixture still running; preserved \(root.path)"); failure = CheckFailure(message: "Fixture cleanup incomplete") }
        guard Set(DesktopLauncher.runningInstances(application: .claude).map(\.pid)).isSuperset(of: existing) else { throw CheckFailure(message: "Pre-existing process was lost") }
        if let failure { throw failure }
        print("PASS only fixture instances terminated; temporary data removed")
    }
}
private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let self else { throw CheckFailure(message: message) }
        return self
    }
}

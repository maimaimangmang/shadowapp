// Explicit, local-only smoke test. Creates fresh unsigned-in profiles; never copies credentials.
import AppKit
import Foundation
import CodexMultiCore
import CodexMultiState

struct CheckFailure: Error { let message: String }
@main struct WorkBuddySmoke {
    // Read only logs in this freshly created fixture, never a user's auth or chat files.
    static func authenticationPID(_ paths: ProfilePaths) -> Int32? {
        let logs = paths.workbuddyConfig.appendingPathComponent("logs")
        guard let files = FileManager.default.enumerator(at: logs, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in files where url.pathExtension == "log" {
            guard let data = try? Data(contentsOf: url), data.count < 4_194_304,
                  let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.contains("[FileAuthenticationStorage]") && line.contains("File watcher ready") {
                if let start = line.range(of: "[pid="), let end = line[start.upperBound...].firstIndex(of: "]") {
                    if let pid = Int32(line[start.upperBound..<end]), ProfileProcessIdentity.startDate(pid: pid) != nil { return pid }
                }
            }
        }
        return nil
    }
    static func authenticationReady(_ paths: ProfilePaths) -> Bool {
        authenticationPID(paths) != nil && !FileManager.default.fileExists(atPath: paths.workbuddyAuth.appendingPathComponent("workbuddy-desktop.info").path)
    }
    static func output(_ executable: String, _ args: [String]) throws -> String {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
    // Inspect only the HOME value for our fresh process tree, never print environment data.
    static func childHome(_ pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4, size < 8_388_608 else { return nil }
        var data = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &data, &size, nil, 0) == 0 else { return nil }
        let argc = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0, argc < 65_536 else { return nil }
        var i = 4
        while i < size && data[i] != 0 { i += 1 }
        while i < size && data[i] == 0 { i += 1 }
        for _ in 0..<argc {
            while i < size && data[i] != 0 { i += 1 }; i += 1
        }
        while i < size {
            let start = i
            while i < size && data[i] != 0 { i += 1 }
            if i - start >= 5, data[start..<min(start + 5, size)].elementsEqual(Array("HOME=".utf8)) {
                return String(bytes: data[(start + 5)..<i], encoding: .utf8)
            }
            i += 1
        }
        return nil
    }
    static func verifyOpenPaths(pid: Int32, paths: ProfilePaths) throws {
        let rows = try output("/bin/ps", ["-axo", "pid=,ppid="]).split(separator: "\n").compactMap { line -> (Int32, Int32)? in
            let values = line.split(whereSeparator: { $0.isWhitespace }).compactMap { Int32($0) }
            return values.count == 2 ? (values[0], values[1]) : nil
        }
        var tree: Set<Int32> = [pid]
        for _ in 0..<20 {
            let next = tree.union(rows.filter { tree.contains($0.1) }.map { $0.0 })
            if next == tree { break }; tree = next
        }
        guard let daemon = authenticationPID(paths), tree.contains(daemon), daemon != pid,
              childHome(pid) == paths.workbuddyHome.path,
              childHome(daemon) == paths.workbuddyHome.path else {
            throw CheckFailure(message: "Main process or authentication daemon does not use the isolated home")
        }
        let names = try output("/usr/sbin/lsof", ["-Fn", "-p", tree.sorted().map(String.init).joined(separator: ",")])
            .split(separator: "\n").filter { $0.hasPrefix("n/") }.map { URL(fileURLWithPath: String($0.dropFirst())).resolvingSymlinksInPath().path }
        let actual = paths.workbuddyAuth.resolvingSymlinksInPath().path
        let authPaths = names.filter { $0.contains("/CodeBuddyExtension/Data/Public/auth") }
        guard authPaths.allSatisfy({ $0 == actual || $0.hasPrefix(actual + "/") }) else {
            throw CheckFailure(message: "Auth watcher not confined to fixture home")
        }
        guard names.contains(where: { $0.hasPrefix(paths.workbuddyConfig.resolvingSymlinksInPath().path + "/") }),
              names.contains(where: { $0.hasPrefix(paths.desktop.resolvingSymlinksInPath().path + "/") }) else {
            throw CheckFailure(message: "Expected isolated open files missing")
        }
    }
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Usage: workbuddy-runtime-fixture /Applications/WorkBuddy.app") }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("workbuddy-multi-check-" + UUID().uuidString)
        let store = ProfileStore(root: root, application: .workbuddy)
        let model = AppModel(store: store, automaticallyDiscover: false, refreshInterval: nil)
        let existing = Set(DesktopLauncher.runningInstances(application: .workbuddy).map(\.pid))
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
                       let app = DesktopLauncher.trackedApplication(current, application: .workbuddy), let receipt = current.receipt {
                        if !owned.contains(where: { $0.1.pid == receipt.pid }) && !existing.contains(receipt.pid) {
                            owned.append((app, receipt, store.paths(for: current)))
                        }
                    }
                    if model.status(profile) == .running || model.error != nil { break }
                }
                guard model.error == nil, model.status(profile) == .running else { throw CheckFailure(message: model.error ?? "Not running") }
                let paths = store.paths(for: profile)
                for _ in 0..<180 {
                    if fm.fileExists(atPath: paths.workbuddyConfig.appendingPathComponent("workbuddy.db").path), authenticationReady(paths) { break }
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
                guard fm.fileExists(atPath: paths.workbuddyConfig.appendingPathComponent("workbuddy.db").path),
                      authenticationReady(paths) else { throw CheckFailure(message: "Isolated database/authentication initialization missing") }
                guard try store.load().profiles.count == owned.count else { throw CheckFailure(message: "Unexpected process association") }
                do { try store.moveToTrash(profile.id); throw CheckFailure(message: "Live profile deletion allowed") }
                catch is LauncherError { }
                print("PASS \(name): independent PID, running status, database and independent unsigned-in auth watcher, live deletion blocked")
                fflush(stdout)
            }
            guard owned.count == 2, owned.allSatisfy({ !$0.0.isTerminated }) else { throw CheckFailure(message: "Two instances are not alive") }
            for (app, _, paths) in owned { try verifyOpenPaths(pid: app.processIdentifier, paths: paths) }
            print("PASS main/auth daemon private HOME and open file paths: separate data and desktop roots; no shared auth files open")
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
            _ = owned[0].0.terminate()
            for _ in 0..<80 {
                if owned[0].0.isTerminated { break }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            guard owned[0].0.isTerminated, !owned[1].0.isTerminated else { throw CheckFailure(message: "Targeted quit affected another instance") }
            model.refresh()
            model.launch(registry.profiles[0])
            for _ in 0..<160 {
                try await Task.sleep(nanoseconds: 250_000_000)
                model.refresh()
                if let profile = model.profiles.first(where: { $0.id == registry.profiles[0].id }),
                   let receipt = profile.receipt, !owned.contains(where: { $0.1.pid == receipt.pid }),
                   !existing.contains(receipt.pid),
                   let app = DesktopLauncher.trackedApplication(profile, application: .workbuddy) {
                    owned.append((app, receipt, store.paths(for: profile)))
                    break
                }
                if model.error != nil { throw CheckFailure(message: model.error!) }
            }
            guard owned.count == 3, !owned[1].0.isTerminated, !owned[2].0.isTerminated,
                  owned[0].2 == owned[2].2 else { throw CheckFailure(message: "Restart did not preserve the isolated profile") }
            for _ in 0..<120 {
                if authenticationReady(owned[2].2) { break }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            try verifyOpenPaths(pid: owned[2].1.pid, paths: owned[2].2)
            print("PASS targeted quit and restart preserve the other instance and profile path")
            fflush(stdout)

        } catch { failure = error }
        let rows = (try? output("/bin/ps", ["-axo", "pid=,ppid="]))?.split(separator: "\n").compactMap { line -> (Int32, Int32)? in
            let values = line.split(whereSeparator: { $0.isWhitespace }).compactMap { Int32($0) }
            return values.count == 2 ? (values[0], values[1]) : nil
        } ?? []
        var descendants = Set(owned.filter { !$0.0.isTerminated }.map { $0.1.pid })
        for _ in 0..<20 {
            let next = descendants.union(rows.filter { descendants.contains($0.1) }.map { $0.0 })
            if next == descendants { break }; descendants = next
        }
        let childStarts = descendants.compactMap { pid -> (Int32, Date)? in
            ProfileProcessIdentity.startDate(pid: pid).map { (pid, $0) }
        }
        for (app, receipt, paths) in owned {
            if let current = DesktopLauncher.application(matching: receipt, application: .workbuddy),
               DesktopLauncher.confirmsProfile(current, paths: paths, application: .workbuddy), !app.isTerminated {
                _ = current.terminate()
            }
        }
        for attempt in 0..<80 {
            if attempt % 4 == 0 {
                for (_, receipt, paths) in owned {
                    if let app = DesktopLauncher.application(matching: receipt, application: .workbuddy),
                       DesktopLauncher.confirmsProfile(app, paths: paths, application: .workbuddy) { _ = app.terminate() }
                }
            }
            if owned.allSatisfy({ $0.0.isTerminated }) { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        // Daemons can outlive the UI. Stop only descendants captured while our exact
        // process receipts were alive, and recheck kernel start times against PID reuse.
        if owned.allSatisfy({ $0.0.isTerminated }) {
            for (pid, date) in childStarts where ProfileProcessIdentity.startDate(pid: pid) == date { _ = kill(pid, SIGTERM) }
            for _ in 0..<40 {
                if childStarts.allSatisfy({ ProfileProcessIdentity.startDate(pid: $0.0) != $0.1 }) { break }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            guard childStarts.allSatisfy({ ProfileProcessIdentity.startDate(pid: $0.0) != $0.1 }) else {
                print("Fixture daemon still running; retained \(root.path)"); exit(1)
            }
            do { try fm.removeItem(at: root) }
            catch { print("Temporary fixture retained at \(root.path): \(error.localizedDescription)"); if failure == nil { failure = error } }
        }
        else { print("Fixture still running; preserved \(root.path)"); failure = CheckFailure(message: "Fixture cleanup incomplete") }
        guard Set(DesktopLauncher.runningInstances(application: .workbuddy).map(\.pid)).isSuperset(of: existing) else { throw CheckFailure(message: "Pre-existing process was lost") }
        if let failure { print("FAIL: \(failure)"); fflush(stdout); exit(1) }
        print("PASS only fixture instances terminated; temporary data removed")
    }
}
private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let self else { throw CheckFailure(message: message) }
        return self
    }
}

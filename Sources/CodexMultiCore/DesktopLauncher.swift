import AppKit
import Foundation

@MainActor
public enum DesktopLauncher {
    public static func open(application: URL, plan: LaunchPlan) async throws -> NSRunningApplication {
        if plan.application == .workbuddy { return try await openWorkBuddy(application, plan: plan) }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = plan.createsNewInstance
        config.allowsRunningApplicationSubstitution = false
        config.environment = plan.environment
        config.arguments = plan.arguments
        config.activates = true
        let app = try await NSWorkspace.shared.openApplication(at: application, configuration: config)
        if plan.application == .wechat {
            // Only stop the copy returned for this exact URL if runtime validation fails.
            guard app.bundleURL?.resolvingSymlinksInPath().path == application.resolvingSymlinksInPath().path,
                  app.bundleIdentifier.map(WeChatProfile.isManagedIdentifier) == true else {
                throw LauncherError("微信未打开预期的独立副本，请检查窗口。", "WeChat did not open the expected independent copy. Check its window.")
            }
            guard WeChatProfile.sandboxActive(pid: app.processIdentifier) else {
                _ = app.terminate()
                throw LauncherError("未能确认微信沙盒已启用，已请求副本退出，数据已保留。", "Could not confirm the WeChat sandbox. The copy was asked to quit; data is preserved.")
            }
        }
        return app
    }

    // LaunchServices reuses WorkBuddy despite createsNewApplicationInstance because the
    // bundle prohibits multiple instances. Spawn the verified executable directly.
    private static var children: [Int32: Process] = [:]

    public static func workbuddyEnvironment(inherited: [String: String], plan: LaunchPlan) -> [String: String] {
        let allowed = Set(["PATH", "TMPDIR", "USER", "LOGNAME", "SHELL", "LANG", "LC_ALL", "LC_CTYPE"])
        return inherited.filter { allowed.contains($0.key) }.merging(plan.environment) { _, new in new }
    }

    private static func openWorkBuddy(_ application: URL, plan: LaunchPlan) async throws -> NSRunningApplication {
        guard let home = plan.environment["HOME"], FileManager.default.isWritableFile(atPath: home) else {
            throw LauncherError("空间主目录不可写，已停止启动。", "The profile home is not writable. Launch stopped.")
        }
        let child = Process()
        child.executableURL = application.appendingPathComponent("Contents/MacOS/Electron")
        child.arguments = plan.arguments
        child.environment = workbuddyEnvironment(inherited: ProcessInfo.processInfo.environment, plan: plan)
        child.currentDirectoryURL = URL(fileURLWithPath: home)
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { process in
            Task { @MainActor in children.removeValue(forKey: process.processIdentifier) }
        }
        try child.run()
        let pid = child.processIdentifier
        children[pid] = child
        do {
            for _ in 0..<80 {
                guard child.isRunning else { break }
                if let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
                   app.bundleIdentifier == ManagedApplication.workbuddy.bundleIdentifier,
                   launchDate(app) != nil,
                   app.bundleURL?.resolvingSymlinksInPath().path == application.resolvingSymlinksInPath().path {
                    _ = app.activate(options: [.activateAllWindows])
                    return app
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            throw LauncherError("WorkBuddy 独立进程未能启动，空间数据已保留。", "WorkBuddy could not start a separate process. Profile data is preserved.")
        } catch {
            // Only the Process we just created; never a pre-existing application.
            if child.isRunning {
                if let app = NSRunningApplication(processIdentifier: pid) { _ = app.terminate() }
                else { child.terminate() }
            }
            throw error
        }
    }

    /// Directly spawned apps may have no LaunchServices launchDate. Kernel start time
    /// is stable across launcher restarts and still protects against PID reuse.
    public static func launchDate(_ app: NSRunningApplication) -> Date? {
        if app.bundleIdentifier == ManagedApplication.workbuddy.bundleIdentifier {
            return ProfileProcessIdentity.startDate(pid: app.processIdentifier)
        }
        return app.launchDate
    }

    public static func trackedApplication(_ profile: Profile, application: ManagedApplication = .codex) -> NSRunningApplication? {
        guard let receipt = profile.receipt else { return nil }
        let app = self.application(matching: receipt, application: application)
        if application == .wechat {
            let expected = ProfilePaths(base: URL(fileURLWithPath: "/"), id: profile.id).wechatIdentifier
            return app?.bundleIdentifier == expected ? app : nil
        }
        return app
    }

    public static func application(matching receipt: ProcessReceipt, application: ManagedApplication = .codex) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: receipt.pid), !app.isTerminated,
              (app.bundleIdentifier == application.bundleIdentifier || (application == .wechat && app.bundleIdentifier.map(WeChatProfile.isManagedIdentifier) == true)),
              receipt.matches(pid: app.processIdentifier, launchedAt: launchDate(app), bundlePath: app.bundleURL?.path) else {
            return nil
        }
        return app
    }

    // Process metadata only: this does not inspect sign-in files or infer account identity.
    public static func runningInstances(application: ManagedApplication = .codex) -> [ProcessReceipt] {
        NSRunningApplication.runningApplications(withBundleIdentifier: application.bundleIdentifier)
            .compactMap { app in
                guard !app.isTerminated, let date = launchDate(app), let url = app.bundleURL else { return nil }
                return ProcessReceipt(pid: app.processIdentifier, launchedAt: date,
                                      bundlePath: url.resolvingSymlinksInPath().path)
            }
            .sorted { $0.launchedAt == $1.launchedAt ? $0.pid < $1.pid : $0.launchedAt < $1.launchedAt }
    }

    public static func confirmsProfile(_ app: NSRunningApplication, paths: ProfilePaths, application: ManagedApplication) -> Bool {
        if application == .wechat {
            return !app.isTerminated && WeChatProfile.matches(pid: app.processIdentifier, bundleIdentifier: app.bundleIdentifier, bundleURL: app.bundleURL, paths: paths)
        }
        guard !app.isTerminated, app.bundleIdentifier == application.bundleIdentifier else { return false }
        return application != .codex
            ? ProfileProcessIdentity.matches(pid: app.processIdentifier, paths: paths)
            : lockProcessID(paths) == app.processIdentifier
    }

    public static func runningWeChatProfile(_ paths: ProfilePaths) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: paths.wechatIdentifier)
            .first { confirmsProfile($0, paths: paths, application: .wechat) }
    }

    public static func hasLiveProfile(_ paths: ProfilePaths, application: ManagedApplication) -> Bool {
        application != .codex ? ProfileProcessIdentity.mayBeUsing(paths, application: application) : hasLiveLock(paths)
    }

    public static func lockProcessID(_ paths: ProfilePaths) -> Int32? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: paths.singletonLock.path) else { return nil }
        return SingletonLock.processID(from: target)
    }

    public static func hasLiveLock(_ paths: ProfilePaths) -> Bool {
        guard let pid = lockProcessID(paths) else { return false }
        // EPERM also means a process exists; never assume it is safe to remove its data.
        return kill(pid, 0) == 0 || errno == EPERM
    }
}

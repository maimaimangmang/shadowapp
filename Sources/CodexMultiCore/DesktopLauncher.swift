import AppKit
import Foundation

@MainActor
public enum DesktopLauncher {
    public static func open(application: URL, plan: LaunchPlan) async throws -> NSRunningApplication {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.allowsRunningApplicationSubstitution = false
        config.environment = plan.environment
        config.arguments = plan.arguments
        config.activates = true
        return try await NSWorkspace.shared.openApplication(at: application, configuration: config)
    }

    public static func trackedApplication(_ profile: Profile) -> NSRunningApplication? {
        guard let receipt = profile.receipt,
              let app = NSRunningApplication(processIdentifier: receipt.pid), !app.isTerminated,
              app.bundleIdentifier == CodexInstallation.bundleIdentifier,
              receipt.matches(pid: app.processIdentifier, launchedAt: app.launchDate, bundlePath: app.bundleURL?.path) else {
            return nil
        }
        return app
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

import AppKit
import Darwin
import Foundation

/// Apps without a reliable SingletonLock are identified by their actual argv.
/// Environment entries returned by KERN_PROCARGS2 are never decoded or exposed.
public enum ProfileProcessIdentity {
    public static func startDate(pid: Int32) -> Date? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_start_tvsec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }

    public static func arguments(pid: Int32) -> [String]? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size, size <= 8_388_608 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &bytes, &size, nil, 0) == 0 else { return nil }
        bytes = Array(bytes.prefix(size))
        let count = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard count > 0, count < 65_536 else { return nil }
        var offset = MemoryLayout<Int32>.size
        // Executable path, then NUL padding, then exactly argc arguments.
        while offset < bytes.count && bytes[offset] != 0 { offset += 1 }
        while offset < bytes.count && bytes[offset] == 0 { offset += 1 }
        var result: [String] = []
        for _ in 0..<count {
            guard offset < bytes.count else { return nil }
            let start = offset
            while offset < bytes.count && bytes[offset] != 0 { offset += 1 }
            guard offset < bytes.count, let value = String(bytes: bytes[start..<offset], encoding: .utf8) else { return nil }
            result.append(value)
            offset += 1
        }
        return result
    }

    public static func matches(arguments: [String], desktop: URL) -> Bool {
        let prefix = "--user-data-dir="
        let values = arguments.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        guard values.count == 1, let value = values.first, value.hasPrefix("/") else { return false }
        return URL(fileURLWithPath: value).resolvingSymlinksInPath().standardizedFileURL.path == desktop.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public static func matches(pid: Int32, paths: ProfilePaths) -> Bool {
        guard let arguments = arguments(pid: pid) else { return false }
        return matches(arguments: arguments, desktop: paths.desktop)
    }

    /// Also protects unrecorded launches (e.g. registry write failure after app startup).
    public static func mayBeUsing(_ paths: ProfilePaths, application: ManagedApplication) -> Bool {
        if application == .wechat { return WeChatProfile.hasLiveProcesses(paths) }
        return NSRunningApplication.runningApplications(withBundleIdentifier: application.bundleIdentifier)
            .contains { app in
                guard !app.isTerminated else { return false }
                guard let args = arguments(pid: app.processIdentifier) else { return true }
                return matches(arguments: args, desktop: paths.desktop)
            }
    }
}

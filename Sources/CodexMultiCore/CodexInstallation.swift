import Foundation

public struct CodexInstallation: Equatable {
    public let url: URL
    public let version: String
    public static let bundleIdentifier = "com.openai.codex"

    public static func inspect(_ url: URL) throws -> CodexInstallation {
        let url = url.resolvingSymlinksInPath()
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["CFBundleIdentifier"] as? String == bundleIdentifier,
              let executable = plist["CFBundleExecutable"] as? String,
              !executable.contains("/"), !executable.isEmpty,
              FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/\(executable)").path) else {
            throw LauncherError("请选择已安装的 Codex 桌面应用。所选应用的标识不匹配。", "Select the installed Codex desktop app. This bundle does not match its identifier.")
        }
        let asar = url.appendingPathComponent("Contents/Resources/app.asar")
        guard try containsMarker(in: asar, marker: Data("CODEX_ELECTRON_USER_DATA_PATH".utf8)) else {
            throw LauncherError("这版 Codex 未检测到独立数据目录支持，已停止启动。请查看兼容性说明。", "This Codex build has no detectable profile-directory support. Launch stopped; see compatibility notes.")
        }
        return CodexInstallation(url: url, version: plist["CFBundleShortVersionString"] as? String ?? "?")
    }

    // A static capability check, not a promise of runtime compatibility. No app files are changed.
    public static func containsMarker(in file: URL, marker: Data, chunkSize: Int = 1_048_576) throws -> Bool {
        guard !marker.isEmpty, chunkSize > 0 else { return false }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var tail = Data()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            let data = tail + chunk
            if data.range(of: marker) != nil { return true }
            tail = Data(data.suffix(marker.count - 1))
        }
        return false
    }
}

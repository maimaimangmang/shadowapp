import Foundation
import CryptoKit

public struct CodexInstallation: Equatable {
    public let url: URL
    public let version: String
    public let application: ManagedApplication
    public static let bundleIdentifier = "com.openai.codex"

    public static func find(in urls: [URL], application: ManagedApplication = .codex) throws -> CodexInstallation {
        var failure: Error = LauncherError("没有找到 \(application.name)，请先安装桌面应用，或手动选择已安装的应用。", "\(application.name) was not found. Install the desktop app, or choose an installed copy.")
        var seen = Set<String>()
        for url in urls {
            let resolved = url.resolvingSymlinksInPath()
            guard seen.insert(resolved.path).inserted,
                  FileManager.default.fileExists(atPath: resolved.path) else { continue }
            do { return try inspect(resolved, application: application) }
            catch { failure = error }
        }
        throw failure
    }

    public static func inspect(_ url: URL, application: ManagedApplication = .codex) throws -> CodexInstallation {
        let url = url.resolvingSymlinksInPath()
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["CFBundleIdentifier"] as? String == application.bundleIdentifier,
              let executable = plist["CFBundleExecutable"] as? String,
              !executable.contains("/"), !executable.isEmpty,
              FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/\(executable)").path) else {
            throw LauncherError("请选择已安装的 \(application.name) 桌面应用。所选应用的标识不匹配。", "Select the installed \(application.name) desktop app. This bundle does not match its identifier.")
        }
        let asar = url.appendingPathComponent("Contents/Resources/app.asar")
        if application == .wechat {
            try WeChatProfile.validateSource(url)
        } else if application == .claude {
            // Only enable the shipped build whose userData behavior has been exercised.
            // An environment marker alone is insufficient: packaged Claude removes it.
            guard plist["CFBundleShortVersionString"] as? String == "4.29.0",
                  try sha256(of: asar) == "fea39d0330a1f6dcb143d9a3fe7b45ed21343c5fc2895c1dff2cb942a28eeb7a" else {
                throw LauncherError("这版 Claude 尚未通过多开兼容性验证，暂不能打开新空间。已有数据已保留；请更新启动器后重试。", "This Claude build has not been verified for separate profiles. Existing data is preserved; update the launcher before opening a new instance.")
            }
        } else if application == .workbuddy {
            guard executable == "Electron", plist["CFBundleShortVersionString"] as? String == "5.8.3",
                  try sha256(of: asar) == "a7eff702411704d140d7d8d706fe9e711d9b13e304928481c9eba0af9c06f731" else {
                throw LauncherError("这版 WorkBuddy 尚未通过多开验证。空间数据已保留，请更新启动器后重试。", "This WorkBuddy build has not been verified for separate profiles. Data is preserved; update the launcher before retrying.")
            }
        } else if application == .codex, try !containsMarker(in: asar, marker: Data("CODEX_ELECTRON_USER_DATA_PATH".utf8)) {
            throw LauncherError("这版 Codex 未检测到独立数据目录支持，已停止启动。请查看兼容性说明。", "This Codex build has no detectable profile-directory support. Launch stopped; see compatibility notes.")
        }
        return CodexInstallation(url: url, version: plist["CFBundleShortVersionString"] as? String ?? "?", application: application)
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { digest.update(data: chunk) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
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

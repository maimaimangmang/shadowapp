import AppKit
import CodexMultiCore
import CodexMultiState
import SwiftUI

// Render the production views with disposable example data. Never read account data,
// discover running instances, launch a managed app, or make provider requests.
@main
struct DocumentationImages {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        guard CommandLine.arguments.count > 1 else { fatalError("Pass an output directory") }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("ShadowApp-Preview", isDirectory: true)
        guard !fm.fileExists(atPath: root.path) else {
            fatalError("Refusing to reuse an existing ~/ShadowApp-Preview directory")
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: output, withIntermediateDirectories: true)

        func model(_ application: ManagedApplication) -> AppModel {
            AppModel(store: ProfileStore(root: application.dataRoot(base: root), application: application),
                     automaticallyDiscover: false, refreshInterval: nil, runningInstances: { [] })
        }
        let codex = model(.codex), claude = model(.claude)
        let workbuddy = model(.workbuddy), wechat = model(.wechat)
        try codex.create(name: Texts.t("个人", "Personal"))
        try codex.create(name: Texts.t("工作", "Work"))
        try codex.create(name: Texts.t("模型实验室", "Model lab"),
                         provider: APIProvider(name: Texts.t("自定义网关", "Custom gateway"),
                                               baseURL: "https://gateway.example.com/v1", modelID: "vendor/model-id"),
                         apiKey: "documentation-placeholder-not-a-real-key")
        try wechat.create(name: Texts.t("个人微信", "Personal WeChat"))
        try wechat.create(name: Texts.t("工作微信", "Work WeChat"))

        func dashboard(_ application: ManagedApplication) -> some View {
            MultiApplicationDashboard(codex: codex, claude: claude, workbuddy: workbuddy,
                                      wechat: wechat, selection: .constant(application))
        }
        let apiOnly = CommandLine.arguments.contains("--api-only")
        if !apiOnly { try render(dashboard(.codex), size: CGSize(width: 960, height: 600), to: output.appendingPathComponent("overview.png")) }
        guard let apiProfile = codex.profiles.first(where: { $0.apiProvider != nil }) else { fatalError("Missing API example") }
        try render(ProviderConnectionEditor(profile: apiProfile, model: codex),
                   size: CGSize(width: 440, height: 580), to: output.appendingPathComponent("api-key.png"))
        if !apiOnly { try render(dashboard(.wechat), size: CGSize(width: 960, height: 600), to: output.appendingPathComponent("wechat.png")) }
    }

    @MainActor private static func render<Content: View>(_ content: Content, size: CGSize, to url: URL) throws {
        let view = content.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light).tint(LauncherAppearance.accent)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("Cannot render") }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode PNG") }
        try data.write(to: url)
        window.contentView = nil
    }
}

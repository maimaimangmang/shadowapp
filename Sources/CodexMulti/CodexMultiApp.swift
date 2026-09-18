import AppKit
import CodexMultiCore
import SwiftUI

@main
struct CodexMultiApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Codex Multi", id: "main") {
            Dashboard(model: model)
                .tint(Color(red: 0.13, green: 0.43, blue: 0.33))
        }
        .defaultSize(width: 960, height: 680)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(Texts.t("选择 Codex 应用…", "Choose Codex app…")) { model.chooseApplication() }
            }
        }
        MenuBarExtra("Codex Multi", systemImage: "square.on.square") {
            LauncherMenu(model: model)
        }
    }
}

private struct LauncherMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(Texts.t("打开账号管理", "Manage profiles")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        ForEach(model.profiles) { profile in
            Button("\(model.status(profile) == .running ? "●" : "○")  \(profile.name)") {
                model.launch(profile)
            }
            .disabled(model.status(profile) == .starting || model.status(profile) == .untracked || model.isChecking || !model.registryAvailable)
        }
        Divider()
        Text(Texts.t("退出管理器后，Codex 会继续运行", "Codex keeps running when this launcher quits"))
        Button(Texts.t("退出 Codex Multi", "Quit Codex Multi")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

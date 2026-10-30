import AppKit
import CodexMultiCore
import CodexMultiState
import SwiftUI

@main
struct CodexMultiApp: App {
    @StateObject private var codex = AppModel()
    @StateObject private var claude = AppModel(application: .claude)
    @StateObject private var workbuddy = AppModel(application: .workbuddy)
    @StateObject private var wechat = AppModel(application: .wechat)
    @AppStorage("selectedApplication") private var selection: ManagedApplication = .codex

    var body: some Scene {
        Window("ShadowApp", id: "main") {
            MultiApplicationDashboard(codex: codex, claude: claude, workbuddy: workbuddy, wechat: wechat, selection: $selection)
                .tint(LauncherAppearance.accent)
        }
        .defaultSize(width: 900, height: 560)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(Texts.t("选择 Codex 应用…", "Choose Codex app…")) { codex.chooseApplication() }
                Button(Texts.t("选择 Claude 应用…", "Choose Claude app…")) { claude.chooseApplication() }
                Button(Texts.t("选择 WorkBuddy 应用…", "Choose WorkBuddy app…")) { workbuddy.chooseApplication() }
                Button(Texts.t("选择微信应用…", "Choose WeChat app…")) { wechat.chooseApplication() }
            }
        }
        MenuBarExtra {
            LauncherApplicationMenu(model: codex, selection: $selection)
            Divider()
            LauncherApplicationMenu(model: claude, selection: $selection)
            Divider()
            LauncherApplicationMenu(model: workbuddy, selection: $selection)
            Divider()
            LauncherApplicationMenu(model: wechat, selection: $selection)
            Divider()
            Text(Texts.t("退出管理器后，已打开的应用会继续运行", "Opened apps keep running when this launcher quits"))
            Button(Texts.t("退出 ShadowApp", "Quit ShadowApp")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            LauncherStatusLabel(codex: codex, claude: claude, workbuddy: workbuddy, wechat: wechat, selection: $selection)
        }
    }
}

private struct LauncherStatusLabel: View {
    @ObservedObject var codex: AppModel
    @ObservedObject var claude: AppModel
    @ObservedObject var workbuddy: AppModel
    @ObservedObject var wechat: AppModel
    @Binding var selection: ManagedApplication
    @Environment(\.openWindow) private var openWindow

    private var needsAttention: Bool {
        [codex, claude, workbuddy, wechat].contains { $0.error != nil || $0.registryError != nil || $0.installationIssue != nil }
    }

    var body: some View {
        statusImage
            .accessibilityLabel(needsAttention ? Texts.t("ShadowApp，需要检查", "ShadowApp, attention needed") : "ShadowApp")
            .onChange(of: codex.error) { if $0 != nil { showIssue(.codex) } }
            .onChange(of: claude.error) { if $0 != nil { showIssue(.claude) } }
            .onChange(of: workbuddy.error) { if $0 != nil { showIssue(.workbuddy) } }
            .onChange(of: wechat.error) { if $0 != nil { showIssue(.wechat) } }
    }

    private var statusImage: Image {
        needsAttention ? Image(systemName: "exclamationmark.square")
            : Image(nsImage: ShadowAppBrand.image(size: 22, template: true))
    }

    private func showIssue(_ application: ManagedApplication) {
        selection = application
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct LauncherApplicationMenu: View {
    @ObservedObject var model: AppModel
    @Binding var selection: ManagedApplication
    @Environment(\.openWindow) private var openWindow

    private func showDashboard() {
        selection = model.application
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some View {
        Button(model.application.supportsSeparateProfiles ? Texts.t("管理 \(model.application.name) 空间", "Manage \(model.application.name) profiles") : "WorkBuddy", action: showDashboard)

        if let message = model.error ?? model.registryError ?? model.installationIssue {
            Button(Texts.t("查看错误…", "View error…"), action: showDashboard)
            Text(message)
            if model.registryError != nil {
                Button(Texts.t("重试读取账号列表", "Retry profile registry")) { model.retryRegistry() }
            }
        }
        if !model.existingInstances.isEmpty {
            Text(Texts.t("已打开的窗口", "Open instances"))
            ForEach(Array(model.existingInstances.enumerated()), id: \.element.pid) { index, instance in
                Button(Texts.t("显示 \(model.application.name) \(index + 1)", "Show \(model.application.name) \(index + 1)")) {
                    model.focusExistingInstance(instance)
                }
            }
        }
        ForEach(model.profiles) { profile in
            Button("\(model.status(profile) == .running ? "●" : "○")  \(profile.name)") { model.launch(profile) }
                .disabled(model.status(profile) == .starting || model.status(profile) == .untracked || model.isChecking || !model.registryAvailable)
        }
    }
}

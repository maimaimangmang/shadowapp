import AppKit
import CodexMultiCore
import CodexMultiState
import SwiftUI

private let palette = LauncherAppearance.avatars

struct MultiApplicationDashboard: View {
    @ObservedObject var codex: AppModel
    @ObservedObject var claude: AppModel
    @ObservedObject var workbuddy: AppModel
    @ObservedObject var wechat: AppModel
    @Binding var selection: ManagedApplication

    var body: some View {
        HStack(spacing: 0) {
            ApplicationSidebar(selection: $selection, installationURLs: icons)
            Dashboard(model: selectedModel).id(selection)
        }.frame(minWidth: 780, minHeight: 480)
    }

    private var selectedModel: AppModel {
        switch selection {
        case .codex: return codex
        case .claude: return claude
        case .workbuddy: return workbuddy
        case .wechat: return wechat
        }
    }

    private var icons: [ManagedApplication: URL] {
        var result: [ManagedApplication: URL] = [:]
        for model in [codex, claude, workbuddy, wechat] {
            if let url = model.installation?.url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: model.application.bundleIdentifier) {
                result[model.application] = url
            }
        }
        return result
    }
}

struct Dashboard: View {
    @ObservedObject var model: AppModel
    @State private var editorShown = false
    @State private var editing: Profile?
    private var selectedApplication: ManagedApplication { model.application }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
                header
                if let registryError = model.registryError {
                    registryWarning(registryError)
                }
                if let issue = model.installationIssue {
                    installationWarning(issue)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !model.existingInstances.isEmpty { existingInstances }
                        if model.application.supportsSeparateProfiles {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionTitle(Texts.t("独立空间", "Separate profiles"), count: model.profiles.count)
                                if model.profiles.isEmpty && model.registryAvailable {
                                    Text(Texts.t("需要另一个账号？点击右上角「新建空间」。", "For another account, choose New profile above."))
                                        .font(.system(size: 12)).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(16)
                                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                                } else {
                                    LazyVStack(spacing: 10) {
                                        ForEach(model.profiles) { profile in
                                            ProfileRow(profile: profile, model: model) {
                                                editing = profile
                                                editorShown = true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if model.application == .workbuddy { workbuddyDetails }
                        if model.application == .wechat { wechatDetails; archivedWeChat }
                    }
                    .padding(1)
                }
                if let notice = model.notice {
                    Text(notice).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(30)
            .background(LauncherAppearance.canvas)
        .sheet(isPresented: $editorShown) {
            ProfileEditor(profile: editing, model: model)
        }
        .alert(Texts.t("需要留意", "Please check"), isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil } }
        )) {
            Button(Texts.t("知道了", "OK"), role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(selectedApplication.name).font(.system(size: 24, weight: .semibold))
            if selectedApplication == .wechat {
                Text(Texts.t("实验性", "Experimental")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.application.supportsSeparateProfiles {
                Button {
                    editing = nil
                    editorShown = true
                } label: {
                    Label(Texts.t("新建空间", "New profile"), systemImage: "plus")
                }
                .buttonStyle(LauncherButtonStyle(prominent: true))
                .disabled(!model.registryAvailable)
            }
        }.padding(.top, 8).padding(.bottom, 4)
    }

    private var wechatDetails: some View {
        DisclosureGroup(Texts.t("微信多开 · 使用说明", "WeChat profiles · Usage notes")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Texts.t("首次打开会创建独立副本，请在微信窗口内扫码登录。手机退出或切换账号可能导致电脑下线，双账号持续在线仍待验证。", "First launch creates an independent copy. Scan its QR code to sign in. Signing out or switching accounts on your phone may log out the desktop; sustained dual-account use is not yet verified."))
                Text(Texts.t("仅支持 Apple Silicon 上的 Mac App Store 微信 4.1.15。通知、音视频尚未完整验证，系统分享和外部微信链接暂不支持。", "Verified with Mac App Store WeChat 4.1.15 on Apple Silicon only. Notifications and media are not fully tested; system sharing and external WeChat links are unavailable."))
                Text(Texts.t("副本保留沙盒，但本地签名会放宽其动态库校验，保护与原版并不完全相同。原微信不会被修改。", "Copies retain App Sandbox, but local signing relaxes library validation; protection differs from the original. The original app is unchanged."))
            }.foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
        }.font(.system(size: 12)).padding(16)
            .background(LauncherAppearance.card, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var archivedWeChat: some View {
        if !model.archivedProfiles.isEmpty {
            DisclosureGroup(Texts.t("已归档空间（\(model.archivedProfiles.count)）", "Archived profiles (\(model.archivedProfiles.count))")) {
                ForEach(model.archivedProfiles) { profile in
                    HStack {
                        Text(profile.name)
                        Spacer()
                        Button(Texts.t("恢复", "Restore")) { model.restoreWeChat(profile) }
                    }.padding(.top, 8)
                }
            }.font(.system(size: 12)).padding(16)
        }
    }

    private var workbuddyDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(Texts.t("多开预览 · 使用说明", "Multi-instance preview · Usage notes")) {
            VStack(alignment: .leading, spacing: 10) {
            Text(Texts.t("每个空间单独登录。请逐个完成登录，并在浏览器中确认所选账号。", "Sign in separately in each profile. Complete sign-ins one at a time and confirm the intended account in your browser."))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(Texts.t("更新应用后请从 ShadowApp 重新打开空间；新版本需重新验证兼容性。", "After updating, reopen profiles from ShadowApp. New app versions require compatibility verification."))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(Texts.t("自定义模型可在 WorkBuddy 的「设置 → 模型」中配置，首次仍需登录 WorkBuddy。", "Configure a custom model in WorkBuddy Settings → Models. WorkBuddy sign-in is still required."))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Link(Texts.t("查看 API Key 配置说明", "API key setup guide"), destination: URL(string: "https://www.workbuddy.cn/docs/workbuddy/From-Beginner-to-Expert-Guide/Function-Description/Model")!)
                .font(.system(size: 12))
            }.padding(.top, 10)
            }.font(.system(size: 12, weight: .medium))
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(LauncherAppearance.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(LauncherAppearance.border, lineWidth: 1))
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text("\(count)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(LauncherAppearance.subtle, in: Capsule())
        }.font(.system(size: 12, weight: .medium))
    }

    private var existingInstances: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(Texts.t("已有窗口", "Existing windows"), count: model.existingInstances.count)
            ForEach(Array(model.existingInstances.enumerated()), id: \.element.pid) { index, instance in
                HStack(spacing: 12) {
                    ApplicationIcon(applicationURL: URL(fileURLWithPath: instance.bundlePath), size: 36)
                    Text(model.existingInstances.count == 1 ? model.application.name : "\(model.application.name) \(index + 1)")
                        .font(.system(size: 13, weight: .medium))
                    Circle().fill(LauncherAppearance.running).frame(width: 6, height: 6)
                        .accessibilityLabel(Texts.t("运行中", "Running"))
                    Spacer()
                    Button(Texts.t("显示窗口", "Show window")) { model.focusExistingInstance(instance) }
                        .buttonStyle(LauncherButtonStyle())
                }
                .padding(16)
                .background(LauncherAppearance.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(LauncherAppearance.border, lineWidth: 1))
                .help(Texts.t("继续使用原有登录，具体账号请在 \(model.application.name) 窗口内查看。", "Continue your existing sign-in. Check the account inside \(model.application.name)."))
            }
        }
    }

    private func installationWarning(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedApplication.supportsSeparateProfiles ? Texts.t("无法打开新的 \(selectedApplication.name) 空间", "Cannot open a new \(selectedApplication.name) profile") : Texts.t("无法打开 WorkBuddy", "Cannot open WorkBuddy"))
                    .font(.system(size: 13, weight: .semibold))
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(model.isChecking ? Texts.t("正在检测…", "Checking…") : Texts.t("重试", "Retry")) {
                model.discoverApplication()
            }.disabled(model.isChecking || !model.registryAvailable)
            Button(Texts.t("选择应用…", "Choose app…")) { model.chooseApplication() }
                .disabled(model.isChecking || !model.registryAvailable)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    private func registryWarning(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 5) {
                Text(Texts.t("账号列表暂不可用", "Profiles are unavailable")).font(.system(size: 13, weight: .semibold))
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(Texts.t("已有数据已保留，恢复列表文件后可重试。", "Existing data is preserved. Restore the registry file, then retry."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(Texts.t("重试读取", "Retry")) { model.retryRegistry() }
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

}

private struct ProfileRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let profile: Profile
    @ObservedObject var model: AppModel
    var edit: () -> Void
    @State private var connectionShown = false
    @State private var apiHelpShown = false
    @State private var modelInfoShown = false
    private var status: InstanceStatus { model.status(profile) }
    private var color: Color { palette[((profile.colorIndex % palette.count) + palette.count) % palette.count] }
    private var displayedPath: String {
        let path = model.store.dataFolder(for: profile).path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.primary.opacity(0.85) : color).frame(width: 36, height: 36)
                    .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name).font(.system(size: 13, weight: .medium)).lineLimit(1).help(profile.name)
                    Text(profile.apiProvider.map { "\(status.label) · \($0.name) / \($0.modelID)" } ?? status.label)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        .help(profile.apiProvider.map { "\($0.name) / \($0.modelID)" } ?? status.label)
                }
                Spacer(minLength: 12)
                if profile.apiProvider != nil {
                    Button { apiHelpShown.toggle() } label: { Image(systemName: "info.circle") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help(Texts.t("API Key 使用说明", "API key help"))
                        .accessibilityLabel(Texts.t("API Key 使用说明", "API key help"))
                        .popover(isPresented: $apiHelpShown) { APIUsageHelp(application: model.application) }
                }
                Button { model.launch(profile) } label: {
                    HStack(spacing: 6) {
                        if status == .starting { ProgressView().controlSize(.mini) }
                        Text(status == .running ? Texts.t("显示窗口", "Show window") : profile.apiProvider != nil ? Texts.t("打开 \(model.application.name)", "Open \(model.application.name)") : Texts.t("打开", "Open"))
                    }
                }
                .buttonStyle(LauncherButtonStyle())
                .disabled(status == .starting || status == .untracked || model.isChecking || !model.registryAvailable)
                Menu {
                    if profile.apiProvider != nil {
                        Button(Texts.t("模型信息…", "Model information…")) { modelInfoShown = true }
                        Button(Texts.t("模型与 API Key…", "Model & API key…")) { connectionShown = true }
                            .disabled(status != .stopped)
                    }
                    Button(Texts.t("重命名…", "Rename…"), action: edit)
                    Button(Texts.t("打开空间文件夹", "Open profile folder")) { model.showFolder(profile) }
                    if status == .running {
                        Button(Texts.t("退出此窗口", "Quit this instance")) { model.requestQuit(profile) }
                    }
                    Divider()
                    Button(model.application == .wechat ? Texts.t("归档空间…", "Archive profile…") : Texts.t("移至废纸篓…", "Move to Trash…"), role: .destructive) { model.trash(profile) }
                        .disabled(status != .stopped)
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(.secondary)
                    .disabled(!model.registryAvailable)
                    .accessibilityLabel(Texts.t("\(profile.name) 的更多操作", "More actions for \(profile.name)"))
            }
            HStack(alignment: .top, spacing: 8) {
                Button { model.showFolder(profile) } label: {
                    Image(systemName: "folder").frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(Texts.t("打开空间文件夹", "Open profile folder"))
                .accessibilityLabel(Texts.t("打开空间文件夹", "Open profile folder"))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.application == .wechat ? Texts.t("账号数据路径", "Account data path") : Texts.t("空间路径", "Profile path")).font(.system(size: 10))
                    Text(displayedPath)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .help(model.store.dataFolder(for: profile).path)
                        .accessibilityLabel(model.store.dataFolder(for: profile).path)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.store.dataFolder(for: profile).path, forType: .string)
                } label: { Image(systemName: "doc.on.doc").frame(width: 16, height: 16) }
                .buttonStyle(.plain)
                .help(Texts.t("复制空间路径", "Copy profile path"))
                .accessibilityLabel(Texts.t("复制空间路径", "Copy profile path"))
            }
            .foregroundStyle(.secondary)
            .padding(.top, 10)
            .overlay(alignment: .top) { Rectangle().fill(LauncherAppearance.border).frame(height: 1) }
        }
        .padding(16)
        .background(LauncherAppearance.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LauncherAppearance.border, lineWidth: 1))
        .sheet(isPresented: $connectionShown) { ProviderConnectionEditor(profile: profile, model: model) }
        .sheet(isPresented: $modelInfoShown) { ModelInformation(profile: profile, paths: model.store.paths(for: profile), application: model.application) }
    }
}

struct APIUsageHelp: View {
    var application: ManagedApplication = .codex
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if application == .claude {
                Text(Texts.t("使用供应商 API Key", "Use a provider API key")).font(.headline)
                Text(Texts.t("首次出现登录选择页时，选择使用已配置的供应商。接口必须兼容 Anthropic Messages 和 Claude 模型。", "Choose the configured provider if a sign-in choice appears. The gateway must support Anthropic Messages and Claude models."))
                Text(Texts.t("设置中的模型 ID 是配置值，实际调用请以供应商的请求记录为准。", "The model ID is a configured value. Verify actual routing in your provider's request records."))
            } else {
            Text(Texts.t("使用 Codex 模式", "Use Codex mode")).font(.headline)
            Text(Texts.t("打开窗口后，点击左上角产品菜单，选择 Codex，再新建聊天。首次导入步骤可以跳过。", "After opening, select Codex from the product menu at the top left, then start a new chat. You can skip the initial import step."))
            Text(Texts.t("Work 浏览器要求 ChatGPT 账号验证。遇到这个提示，先切回 Codex，无需因此更换供应商 Key。", "Work browser access requires a ChatGPT account. If that warning appears, switch to Codex first; it does not establish that your provider key is invalid."))
                .foregroundStyle(.secondary)
            Text(Texts.t("确认模型请在空间的「… → 模型信息」查看会话记录，不要依据模型的自我介绍。", "Use … > Model information to inspect session metadata, rather than the model's self-description."))
                .foregroundStyle(.secondary)
            }
        }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).padding(20).frame(width: 330)
    }
}

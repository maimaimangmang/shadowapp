import CodexMultiCore
import CodexMultiState
import SwiftUI

struct ProviderDraft: Equatable {
    var application: ManagedApplication = .codex
    var shengsuanyun = true
    var name = ""
    var baseURL = ""
    var modelID = ""
    var apiKey = ""

    init(provider: APIProvider? = nil, application: ManagedApplication = .codex) {
        self.application = application
        if let provider {
            shengsuanyun = provider.baseURL == (application == .claude ? APIProvider.shengsuanyunClaudeURL : APIProvider.shengsuanyunURL) && provider.name == "胜算云"
            name = provider.name
            baseURL = provider.baseURL
            modelID = provider.modelID
        }
    }

    var presetURL: String { application == .claude ? APIProvider.shengsuanyunClaudeURL : APIProvider.shengsuanyunURL }

    var provider: APIProvider {
        APIProvider(name: shengsuanyun ? "胜算云" : name,
                    baseURL: shengsuanyun ? presetURL : baseURL, modelID: modelID)
    }

    func complete(requiresKey: Bool) -> Bool {
        let values = [provider.name, provider.baseURL, provider.modelID] + (requiresKey ? [apiKey] : [])
        return values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct ProviderFields: View {
    @Binding var draft: ProviderDraft
    var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(Texts.t("供应商", "Provider"), selection: $draft.shengsuanyun) {
                Text(Texts.t("胜算云", "Shengsuanyun")).tag(true)
                Text(Texts.t("自定义供应商", "Custom provider")).tag(false)
            }
            if draft.shengsuanyun {
                Text(draft.presetURL).font(.system(size: 11)).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                field(Texts.t("供应商名称", "Provider name"), text: $draft.name, placeholder: Texts.t("例如：公司网关", "e.g. Company gateway"))
                field(Texts.t("接口地址（Base URL）", "Base URL"), text: $draft.baseURL, placeholder: draft.application == .claude ? "https://gateway.example.com" : "https://api.example.com/v1")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("API Key").font(.system(size: 12, weight: .medium))
                SecureField(editing ? Texts.t("留空保留原 Key", "Leave blank to keep the current key") : Texts.t("粘贴供应商的 API Key", "Paste the provider's API key"), text: $draft.apiKey)
                    .textFieldStyle(.roundedBorder)
                if draft.shengsuanyun {
                    Link(Texts.t("获取 API Key", "Get an API key"), destination: URL(string: "https://console.shengsuanyun.com/user/keys")!)
                        .font(.system(size: 11))
                    Text(.init(Texts.t(
                        "还没有 Key？[点击链接注册领取 10 元体验金](https://www.shengsuanyun.com/?from=Zoey)",
                        "No API key yet? [Sign up to receive ¥10 in trial credit](https://www.shengsuanyun.com/?from=Zoey)"
                    )))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            field(Texts.t("模型 ID", "Model ID"), text: $draft.modelID, placeholder: Texts.t("粘贴供应商提供的完整模型 ID", "Paste the full model ID from your provider"))
            if draft.application == .claude {
                Text(Texts.t("仅 Claude 模型或网关模型 ID，例如 anthropic/claude-sonnet-5。", "Claude model or gateway ID only, e.g. anthropic/claude-sonnet-5."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if draft.shengsuanyun {
                Link(Texts.t("查看模型列表", "View model list"), destination: URL(string: "https://global.modelmesh.info/model")!)
                    .font(.system(size: 11))
            }
            ProviderConnectionTest(draft: draft, editing: editing)
            DisclosureGroup(Texts.t("使用说明", "Usage notes")) {
                VStack(alignment: .leading, spacing: 10) {
                    if draft.application == .claude {
                        Text(Texts.t("使用 Claude 的第三方推理模式，无需用供应商 Key 登录 Claude 账号。首次出现选择页时，选择使用已配置的供应商。", "Uses Claude's third-party inference mode. Choose the configured provider if an initial sign-in choice is shown."))
                        Text(Texts.t("接口需支持 Anthropic Messages、流式输出和工具调用。模型需为 Claude 或对应的网关模型 ID；Base URL 不带 /v1。", "Requires Anthropic Messages, streaming, and tool use with a Claude or gateway model ID. The base URL has no /v1 suffix."))
                        Text(Texts.t("Key 只保存在本空间；组织管理策略可能优先于本地配置。", "The key stays in this profile. Organization policies may take precedence over local settings."))
                    } else {
                    Text(Texts.t("打开后选择 Codex 模式。Work 浏览器功能需要 ChatGPT 账号，不能用供应商 Key 代替。", "Select Codex after opening. Work browser features require a ChatGPT account, not a provider key."))
                    Text(Texts.t("供应商和模型需支持 Responses API。Key 保存在此空间的本机数据文件夹中。", "The provider and model must support the Responses API. The key is saved locally in this profile's data folder."))
                    }
                }
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            }.font(.system(size: 11))
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .medium))
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }
}

struct ProfileEditor: View {
    let profile: Profile?
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var name = ""
    @State var useAPIKey = true
    @State private var draft = ProviderDraft()
    @State private var error: String?
    @State private var isSubmitting = false
    @FocusState private var focused: Bool

    private var apiMode: Bool { model.application.supportsAPIProfiles && useAPIKey }

    private var nameIssue: String? {
        // Creating a profile publishes it before this sheet finishes dismissing.
        // Do not validate the submitted name against that newly created profile.
        guard !isSubmitting, !name.isEmpty else { return nil }
        do { _ = try ProfileName.validate(name, profiles: model.profiles + model.archivedProfiles, excluding: profile?.id); return nil }
        catch { return error.localizedDescription }
    }

    private var canSave: Bool {
        !isSubmitting && nameIssue == nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (profile != nil || !apiMode || draft.complete(requiresKey: true))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(profile == nil ? Texts.t("新建空间", "New profile") : Texts.t("重命名空间", "Rename profile"))
                .font(.title2.weight(.semibold))
            if profile == nil && apiMode {
                ScrollView { fields }.frame(height: 420)
            } else {
                fields.fixedSize(horizontal: false, vertical: true)
            }
            if let message = nameIssue ?? error { EditorErrorMessage(message: message) }
            HStack {
                Spacer()
                Button(Texts.t("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Texts.t("保存", "Save"), action: save)
                    .buttonStyle(LauncherButtonStyle(prominent: true)).keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .padding(28).frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { draft.application = model.application; if let profile { name = profile.name }; focused = true }
        .onChange(of: name) { _ in error = nil }
        .onChange(of: draft) { _ in error = nil }
        .onChange(of: useAPIKey) { _ in error = nil }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField(Texts.t("空间名称，例如「工作」", "Profile name, e.g. Work"), text: $name)
                .textFieldStyle(.roundedBorder).focused($focused)
            if profile == nil {
                if model.application.supportsAPIProfiles {
                Picker(Texts.t("连接方式", "Connection"), selection: $useAPIKey) {
                    Text("API Key").tag(true)
                    Text(model.application == .claude ? Texts.t("Claude 账号", "Claude account") : Texts.t("ChatGPT 账号", "ChatGPT account")).tag(false)
                }.pickerStyle(.segmented)
                }
                if apiMode { ProviderFields(draft: $draft) }
                else {
                    Text(Texts.t("打开后在 \(model.application.name) 内登录；多个账号请逐个完成登录。", "Sign in inside \(model.application.name) after opening. Complete one sign-in at a time."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.application == .wechat {
                        Text(Texts.t("实验性多开：首次打开会创建保留沙盒的本地签名副本，其动态库校验与原版不同。", "Experimental: first launch creates a locally signed, sandboxed copy with relaxed library validation."))
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if model.application == .workbuddy {
                        Text(Texts.t("每个空间使用独立主目录；原有 Git、SSH 等配置需自行设置。", "Each profile uses a separate home; configure Git, SSH and other tools inside it."))
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }.padding(1)
    }

    private func save() {
        guard canSave else { return }
        isSubmitting = true
        error = nil
        do {
            if let profile { try model.rename(profile, to: name) }
            else if apiMode { try model.create(name: name, provider: draft.provider, apiKey: draft.apiKey) }
            else { try model.create(name: name) }
            draft.apiKey = ""
            dismiss()
        } catch {
            isSubmitting = false
            self.error = error.localizedDescription
        }
    }
}

struct ProviderConnectionEditor: View {
    let profile: Profile
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProviderDraft
    @State private var error: String?

    init(profile: Profile, model: AppModel) {
        self.profile = profile
        self.model = model
        _draft = State(initialValue: ProviderDraft(provider: profile.apiProvider, application: model.application))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(Texts.t("模型与 API Key", "Model & API key")).font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ProviderFields(draft: $draft, editing: true)
                }.padding(1)
            }
            if let error { EditorErrorMessage(message: error) }
            HStack {
                Spacer()
                Button(Texts.t("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Texts.t("保存", "Save")) {
                    do {
                        try model.updateProvider(profile, provider: draft.provider, newAPIKey: draft.apiKey.isEmpty ? nil : draft.apiKey)
                        draft.apiKey = ""
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(LauncherButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                    .disabled(!draft.complete(requiresKey: draft.provider.baseURL != profile.apiProvider?.baseURL))
            }
        }.padding(28).frame(width: 440, height: 580)
        .onChange(of: draft) { _ in error = nil }
    }
}

import CodexMultiCore
import SwiftUI

struct ModelInformation: View {
    let profile: Profile
    let paths: ProfilePaths
    var application: ManagedApplication = .codex
    @Environment(\.dismiss) private var dismiss
    @State private var evidence: SessionModelEvidence?
    @State private var problem: String?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Texts.t("模型信息", "Model information")).font(.title2.weight(.semibold))
            Text(profile.name).foregroundStyle(.secondary)
            if let provider = profile.apiProvider {
                GroupBox(Texts.t("启动器设置", "Launcher settings")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(provider.name)
                        Text(provider.modelID).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
            }
            if application == .claude {
                Text(Texts.t("以上为启动器配置。Claude 会话记录尚未接入，实际调用模型请在供应商请求记录中确认。", "These are launcher settings. Claude session metadata is not integrated; verify the model in your provider's request records."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
            GroupBox(Texts.t("最近更新的本地会话", "Most recently updated local session")) {
                VStack(alignment: .leading, spacing: 8) {
                    if loading { ProgressView().controlSize(.small) }
                    else if let evidence {
                        Text(evidence.model).fontWeight(.semibold).textSelection(.enabled)
                        Text(Texts.t("供应商配置：", "Provider configuration: ") + evidence.provider)
                        Text(Texts.t("会话：", "Session: ") + evidence.sessionID)
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if let timestamp = evidence.timestamp {
                            Text(timestamp).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(problem ?? Texts.t("还没有可读取的本地会话。", "No local session is available yet."))
                            .foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            Text(Texts.t("会话记录反映客户端选择的模型，不一定是当前窗口；供应商实际调用的模型需在其请求记录中确认。", "Session metadata shows the client-selected model and may not belong to the current window. Verify upstream routing in the provider’s request records."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if application == .codex { Button(Texts.t("刷新", "Refresh")) { Task { await refresh() } }.disabled(loading) }
                Spacer()
                Button(Texts.t("完成", "Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 460).task { await refresh() }
    }

    private func refresh() async {
        guard application == .codex else { loading = false; return }
        loading = true
        let paths = paths
        let result = await Task.detached { () -> Result<SessionModelEvidence?, Error> in
            Result { try SessionModelEvidence.latest(in: paths) }
        }.value
        switch result {
        case .success(let value): evidence = value; problem = nil
        case .failure(let error): evidence = nil; problem = error.localizedDescription
        }
        loading = false
    }
}

import CodexMultiCore
import SwiftUI

struct ProviderConnectionTest: View {
    let draft: ProviderDraft
    let editing: Bool
    @State private var task: Task<Void, Never>?
    @State private var message: String?
    @State private var failed = false
    @State private var generation = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Button(task == nil ? Texts.t("测试连接", "Test connection") : Texts.t("测试中…", "Testing…"), action: start)
                    .buttonStyle(LauncherButtonStyle())
                    .disabled(!draft.complete(requiresKey: true) || task != nil)
                if task != nil {
                    ProgressView().controlSize(.small)
                    Button(Texts.t("取消", "Cancel"), action: reset).buttonStyle(.plain)
                }
            }
            if let message {
                Label(message, systemImage: failed ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(failed ? Color.red : LauncherAppearance.running)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(editing && draft.apiKey.isEmpty
                 ? Texts.t("测试需重新填写 Key；留空仍可保存其他设置。", "Enter the key to test. Leaving it blank still preserves the saved key.")
                 : Texts.t("发送一条简短请求，可能产生少量费用。", "Sends a short request; a small usage charge may apply."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .onChange(of: draft) { _ in reset() }
        .onDisappear(perform: reset)
    }

    private func start() {
        reset()
        let current = generation
        let provider = draft.provider
        let key = draft.apiKey
        task = Task { @MainActor in
            do {
                let result = try await ProviderConnectionProbe.check(provider: provider, key: key, application: draft.application)
                guard !Task.isCancelled, current == generation else { return }
                failed = false
                message = result.message
            } catch {
                guard !Task.isCancelled, current == generation else { return }
                failed = true
                message = error.localizedDescription
            }
            task = nil
        }
    }

    private func reset() {
        generation = UUID()
        task?.cancel()
        task = nil
        message = nil
    }
}

struct EditorErrorMessage: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.system(size: 12)).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

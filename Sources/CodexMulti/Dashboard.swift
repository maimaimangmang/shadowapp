import CodexMultiCore
import SwiftUI

private let green = Color(red: 0.13, green: 0.43, blue: 0.33)
private let palette: [Color] = [green, Color(red: 0.31, green: 0.38, blue: 0.69), .orange, .purple, .pink]

struct Dashboard: View {
    @ObservedObject var model: AppModel
    @State private var editorShown = false
    @State private var editing: Profile?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 24) {
                header
                installation
                ScrollView {
                    if model.profiles.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up").font(.system(size: 32)).foregroundStyle(.secondary)
                            Text(Texts.t("添加第一个账号空间", "Add your first profile")).font(.headline)
                            Text(Texts.t("每个空间登录一个账号，随时一起打开。", "One sign-in per profile. Open them side by side."))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 55)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(model.profiles) { profile in
                                ProfileCard(profile: profile, model: model) {
                                    editing = profile
                                    editorShown = true
                                }
                            }
                        }
                        .padding(1)
                    }
                }
                footer
            }
            .padding(30)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 880, minHeight: 620)
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "square.on.square")
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(Color(red: 0.68, green: 0.89, blue: 0.76))
                .padding(.bottom, 18)
            Text("Codex\nMulti")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .lineSpacing(0)
            Text(Texts.t("每个账号，都有自己的空间。", "A space for every account."))
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                .padding(.top, 13).lineSpacing(4)
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                Text(Texts.t("账号空间", "Profiles")).fontWeight(.medium)
                Spacer()
                Text("\(model.profiles.count)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.white.opacity(0.13), in: Capsule())
            }
            .font(.system(size: 13))
            .padding(13).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 34)
            Spacer(minLength: 35)
            VStack(alignment: .leading, spacing: 17) {
                tip("1", Texts.t("创建账号空间", "Create a profile"))
                tip("2", Texts.t("打开后，登录对应账号", "Open it and sign in"))
                tip("3", Texts.t("随时同时运行", "Run accounts side by side"))
            }
            Divider().overlay(.white.opacity(0.1)).padding(.vertical, 24)
            Text("v0.1.0  /  PREVIEW")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.1).foregroundStyle(.white.opacity(0.55))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 25).padding(.top, 45).padding(.bottom, 28)
        .frame(width: 220)
        .background(Color(red: 0.09, green: 0.17, blue: 0.14))
    }

    private func tip(_ number: String, _ title: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .frame(width: 19, height: 19)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
            Text(title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.78)).padding(.top, 1)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Texts.t("你的账号空间", "Your profiles")).font(.system(size: 26, weight: .semibold))
                Text(Texts.t("独立登录，各自保留历史。", "Separate sign-ins. Separate histories."))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                editing = nil
                editorShown = true
            } label: {
                Label(Texts.t("添加账号", "Add profile"), systemImage: "plus")
            }
            .controlSize(.large).buttonStyle(.borderedProminent)
            .disabled(!model.registryAvailable)
        }.padding(.top, 12)
    }

    private var installation: some View {
        HStack(spacing: 12) {
            Image(systemName: model.installation == nil ? "app.dashed" : "checkmark.circle.fill")
                .foregroundStyle(model.installation == nil ? Color.secondary : green)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.isChecking ? Texts.t("正在检查 Codex…", "Checking Codex…") :
                    model.installation.map { "Codex  \($0.version)" } ?? Texts.t("先选择 Codex 应用", "Choose your Codex app"))
                    .font(.system(size: 13, weight: .medium))
                Text(model.installation?.url.lastPathComponent ?? Texts.t("需要先安装 Codex 桌面版", "Install the Codex desktop app first"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(Texts.t("选择应用…", "Choose app…")) { model.chooseApplication() }
                .buttonStyle(.borderless).disabled(model.isChecking)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.07), lineWidth: 1))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice = model.notice {
                Label(notice, systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack(spacing: 8) {
                Circle().fill(model.runningCount > 0 ? green : .secondary).frame(width: 6, height: 6)
                Text(Texts.t("\(model.runningCount) 个运行中", "\(model.runningCount) running"))
                Spacer()
                Text(Texts.t("首次登录请逐个完成", "Complete first sign-ins one at a time"))
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            Text(Texts.t("预览版 · Codex 更新后可能需要适配", "Preview · Codex updates may require launcher changes"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

private struct ProfileCard: View {
    let profile: Profile
    @ObservedObject var model: AppModel
    var edit: () -> Void
    private var status: InstanceStatus { model.status(profile) }
    private var color: Color { palette[((profile.colorIndex % palette.count) + palette.count) % palette.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(color).frame(width: 46, height: 46)
                    .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                Spacer()
                Menu {
                    Button(Texts.t("重命名…", "Rename…"), action: edit)
                    Button(Texts.t("在访达中查看数据", "Show data in Finder")) { model.showFolder(profile) }
                    Divider()
                    Button(Texts.t("移至废纸篓…", "Move to Trash…"), role: .destructive) { model.trash(profile) }
                        .disabled(status != .stopped)
                } label: { Image(systemName: "ellipsis").frame(width: 20, height: 20) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel(Texts.t("\(profile.name) 的更多操作", "More actions for \(profile.name)"))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(profile.name).font(.system(size: 17, weight: .semibold)).lineLimit(1).help(profile.name)
                HStack(spacing: 6) {
                    Circle().fill(status == .running ? green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(status.label).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button {
                    model.launch(profile)
                } label: {
                    HStack(spacing: 7) {
                        if status == .starting { ProgressView().controlSize(.mini) }
                        else { Image(systemName: status == .running ? "arrow.up.forward.app" : "play.fill").font(.system(size: 10)) }
                        Text(status == .running ? Texts.t("切换窗口", "Show window") : Texts.t("打开 Codex", "Open Codex"))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .disabled(status == .starting || status == .untracked || model.isChecking || !model.registryAvailable)
                if status == .running {
                    Button { model.requestQuit(profile) } label: { Image(systemName: "power") }
                        .controlSize(.large).help(Texts.t("退出这个账号", "Quit this instance"))
                        .accessibilityLabel(Texts.t("退出 \(profile.name)", "Quit \(profile.name)"))
                }
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(status == .running ? green.opacity(0.4) : .primary.opacity(0.09), lineWidth: 1))
    }
}

private struct ProfileEditor: View {
    let profile: Profile?
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(profile == nil ? Texts.t("添加账号空间", "Add a profile") : Texts.t("重命名账号空间", "Rename profile"))
                .font(.title2.weight(.semibold))
            Text(Texts.t("用容易区分的名称，例如「个人」「工作」。", "Choose a recognizable name, such as Personal or Work."))
                .font(.callout).foregroundStyle(.secondary)
            TextField(Texts.t("账号名称", "Profile name"), text: $name)
                .textFieldStyle(.roundedBorder).focused($focused).onSubmit(save)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(Texts.t("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Texts.t("保存", "Save"), action: save)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28).frame(width: 390)
        .onAppear { name = profile?.name ?? ""; focused = true }
    }

    private func save() {
        do {
            if let profile { try model.rename(profile, to: name) }
            else { try model.create(name: name) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

import AppKit
import CodexMultiCore
import SwiftUI
import UniformTypeIdentifiers

enum InstanceStatus: Equatable {
    case stopped, starting, running, untracked

    var label: String {
        switch self {
        case .stopped: return Texts.t("未启动", "Stopped")
        case .starting: return Texts.t("启动中…", "Starting…")
        case .running: return Texts.t("运行中", "Running")
        case .untracked: return Texts.t("需检查窗口", "Check instance")
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var installation: CodexInstallation?
    @Published var statuses: [UUID: InstanceStatus] = [:]
    @Published var notice: String?
    @Published var error: String?
    @Published var isChecking = true
    @Published var registryAvailable = false
    let store: ProfileStore
    private var starting: Set<UUID> = []
    private var checkTask: Task<Void, Never>?
    private var refreshTimer: Timer?

    init() {
        // A separate data root is useful for development and smoke tests. Never change HOME.
        if let path = ProcessInfo.processInfo.environment["CODEX_MULTI_DATA_DIR"], path.hasPrefix("/") {
            store = ProfileStore(root: URL(fileURLWithPath: path, isDirectory: true))
        } else {
            store = ProfileStore()
        }
        do {
            let registry = try store.load()
            profiles = registry.profiles
            registryAvailable = true
            discoverApplication(savedPath: registry.applicationPath)
        } catch {
            self.error = error.localizedDescription
            isChecking = false
        }
        refresh()
        // Keep the menu-bar status current even when the dashboard window is closed.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    deinit { refreshTimer?.invalidate() }

    var runningCount: Int { statuses.values.filter { $0 == .running }.count }

    func status(_ profile: Profile) -> InstanceStatus { statuses[profile.id] ?? .stopped }

    func refresh() {
        guard registryAvailable else { return }
        do {
            profiles = try store.load().profiles
            var next: [UUID: InstanceStatus] = [:]
            for profile in profiles {
                let paths = store.paths(for: profile)
                if starting.contains(profile.id) { next[profile.id] = .starting }
                else if let app = DesktopLauncher.trackedApplication(profile),
                        DesktopLauncher.lockProcessID(paths) == app.processIdentifier { next[profile.id] = .running }
                else if DesktopLauncher.trackedApplication(profile) != nil || DesktopLauncher.hasLiveLock(paths) {
                    next[profile.id] = .untracked
                } else { next[profile.id] = .stopped }
            }
            statuses = next
        } catch {
            self.error = error.localizedDescription
            registryAvailable = false
        }
    }

    func discoverApplication(savedPath: String? = nil) {
        var urls: [URL] = []
        if let savedPath { urls.append(URL(fileURLWithPath: savedPath)) }
        if let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CodexInstallation.bundleIdentifier) { urls.append(found) }
        for path in ["/Applications/Codex.app", "/Applications/ChatGPT.app"] {
            urls.append(URL(fileURLWithPath: path))
        }
        urls.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Codex.app"))
        check(urls: urls)
    }

    func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = Texts.t("选择 Codex 应用", "Choose Codex")
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { check(urls: [url], reportFailure: true) }
    }

    private func check(urls: [URL], reportFailure: Bool = false) {
        checkTask?.cancel()
        isChecking = true
        checkTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<CodexInstallation, Error> in
                var failure: Error = LauncherError("没有找到兼容的 Codex，请手动选择应用。", "No compatible Codex found. Choose the app manually.")
                for url in urls where FileManager.default.fileExists(atPath: url.path) {
                    do { return .success(try CodexInstallation.inspect(url)) }
                    catch { failure = error }
                }
                return .failure(failure)
            }.value
            guard !Task.isCancelled else { return }
            isChecking = false
            switch result {
            case .success(let app):
                installation = app
                do { try store.setApplication(app.url) } catch { self.error = error.localizedDescription }
            case .failure(let failure):
                if reportFailure { error = failure.localizedDescription }
            }
        }
    }

    func create(name: String) throws {
        _ = try store.create(name: name)
        refresh()
    }

    func rename(_ profile: Profile, to name: String) throws {
        try store.rename(profile.id, to: name)
        refresh()
    }

    func launch(_ profile: Profile) {
        refresh()
        guard registryAvailable, !starting.contains(profile.id) else { return }
        let current = profiles.first(where: { $0.id == profile.id }) ?? profile
        if let app = DesktopLauncher.trackedApplication(current), status(current) == .running {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }
        guard status(current) == .stopped else {
            error = Texts.t("这个账号的实例状态暂时无法确认。请在对应 Codex 窗口内退出，再重新启动。", "This instance cannot be verified. Quit it from its Codex window, then launch it again.")
            return
        }
        guard let installation else { chooseApplication(); return }
        starting.insert(profile.id)
        refresh()
        Task {
            defer { starting.remove(profile.id); refresh() }
            do {
                // Recheck after application updates before every new launch.
                let checked = try await Task.detached {
                    try CodexInstallation.inspect(installation.url)
                }.value
                let paths = try store.prepare(current)
                let app = try await DesktopLauncher.open(application: checked.url, plan: LaunchPlan(paths: paths))
                guard let launchDate = app.launchDate, let bundleURL = app.bundleURL else {
                    throw LauncherError("应用已打开，但无法记录实例。请检查新窗口。", "The app opened, but its process identity is unavailable. Check the new window.")
                }
                let receipt = ProcessReceipt(pid: app.processIdentifier, launchedAt: launchDate,
                                             bundlePath: bundleURL.resolvingSymlinksInPath().path)
                try store.record(receipt, for: current.id)
                for _ in 0..<60 {
                    if app.isTerminated { break }
                    if DesktopLauncher.lockProcessID(paths) == app.processIdentifier {
                        self.installation = checked
                        notice = Texts.t("\(current.name) 已打开；首次使用请在新窗口中登录。", "\(current.name) opened. Sign in in the new window on first use.")
                        return
                    }
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
                throw LauncherError("Codex 未能确认启动，请检查窗口；账号数据已保留。", "Could not confirm Codex startup. Check its window; profile data has been preserved.")
            } catch { self.error = error.localizedDescription }
        }
    }

    func requestQuit(_ profile: Profile) {
        refresh()
        guard let current = profiles.first(where: { $0.id == profile.id }),
              status(current) == .running,
              let app = DesktopLauncher.trackedApplication(current),
              DesktopLauncher.lockProcessID(store.paths(for: current)) == app.processIdentifier else { return }
        let alert = NSAlert()
        alert.messageText = Texts.t("退出「\(current.name)」？", "Quit “\(current.name)”?")
        alert.informativeText = Texts.t("请先确认这个窗口中的任务已完成。只会请求这个实例正常退出。", "Finish any tasks in this window first. This requests a normal quit of this instance.")
        alert.addButton(withTitle: Texts.t("退出这个账号", "Quit this instance"))
        alert.addButton(withTitle: Texts.t("取消", "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            // Verify again after the confirmation dialog, guarding against process-ID reuse.
            guard let target = DesktopLauncher.trackedApplication(current),
                  DesktopLauncher.lockProcessID(store.paths(for: current)) == target.processIdentifier else { return }
            if target.terminate() {
                notice = Texts.t("已请求退出；如有保存提示，请在 Codex 窗口中处理。", "Quit requested. Handle any save prompt in the Codex window.")
            } else {
                error = Texts.t("未能请求退出，请在对应 Codex 窗口中手动退出。", "Could not request a quit. Quit from this Codex window manually.")
            }
        }
        refresh()
    }

    func showFolder(_ profile: Profile) {
        do {
            let paths = try store.prepare(profile)
            NSWorkspace.shared.open(paths.root)
        } catch { self.error = error.localizedDescription }
    }

    func trash(_ profile: Profile) {
        refresh()
        guard status(profile) == .stopped else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Texts.t("移除「\(profile.name)」？", "Remove “\(profile.name)”?")
        alert.informativeText = Texts.t("这个账号的本地登录信息、历史记录和设置会一起移至废纸篓。其他账号不受影响。", "This profile’s local sign-in data, history and settings will move to the Trash. Other profiles are unaffected.")
        alert.addButton(withTitle: Texts.t("移至废纸篓", "Move to Trash"))
        alert.addButton(withTitle: Texts.t("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        refresh()
        guard status(profile) == .stopped else { return }
        do { try store.moveToTrash(profile.id); refresh() }
        catch { self.error = error.localizedDescription }
    }
}

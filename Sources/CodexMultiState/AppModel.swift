import AppKit
import Combine
import CodexMultiCore
import UniformTypeIdentifiers

public enum InstanceStatus: Equatable {
    case stopped, starting, running, untracked, unavailable

    public var label: String {
        switch self {
        case .stopped: return Texts.t("未启动", "Stopped")
        case .starting: return Texts.t("启动中…", "Starting…")
        case .running: return Texts.t("运行中", "Running")
        case .untracked: return Texts.t("需检查窗口", "Check instance")
        case .unavailable: return Texts.t("状态不可用", "Status unavailable")
        }
    }
}

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var profiles: [Profile] = []
    @Published public private(set) var archivedProfiles: [Profile] = []
    @Published public private(set) var existingInstances: [ProcessReceipt] = []
    @Published public private(set) var installation: CodexInstallation?
    @Published public private(set) var statuses: [UUID: InstanceStatus] = [:]
    @Published public private(set) var notice: String?
    @Published public var error: String?
    @Published public private(set) var registryError: String?
    @Published public private(set) var installationIssue: String?
    @Published public private(set) var isChecking = false
    @Published public private(set) var registryAvailable = false
    public let store: ProfileStore
    public var application: ManagedApplication { store.application }
    private let automaticallyDiscover: Bool
    private let runningInstances: @MainActor () -> [ProcessReceipt]
    private var starting: Set<UUID> = []
    private var checkTask: Task<Void, Never>?
    private var refreshTimer: Timer?

    public init(store: ProfileStore? = nil, application: ManagedApplication = .codex, automaticallyDiscover: Bool = true, refreshInterval: TimeInterval? = 2,
                runningInstances: (@MainActor () -> [ProcessReceipt])? = nil) {
        self.automaticallyDiscover = automaticallyDiscover
        let selectedApplication = store?.application ?? application
        self.runningInstances = runningInstances ?? { DesktopLauncher.runningInstances(application: selectedApplication) }
        // The launcher retains its own HOME. Only WorkBuddy children receive a private home.
        if let store {
            self.store = store
        } else if let path = ProcessInfo.processInfo.environment["CODEX_MULTI_DATA_DIR"], path.hasPrefix("/") {
            self.store = ProfileStore(root: application.dataRoot(base: URL(fileURLWithPath: path, isDirectory: true)), application: application)
        } else {
            self.store = ProfileStore(root: application.dataRoot(base: ProfileStore.defaultRoot), application: application)
        }
        if let registry = readRegistry(createIfMissing: true), automaticallyDiscover {
            discoverApplication(savedPath: registry.applicationPath)
        }
        refreshExistingInstances()
        // Keep the menu-bar status current even when the dashboard window is closed.
        if let refreshInterval, refreshInterval > 0 {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        }
    }

    deinit { refreshTimer?.invalidate() }

    public var runningCount: Int { statuses.values.filter { $0 == .running }.count }

    public func status(_ profile: Profile) -> InstanceStatus {
        registryAvailable ? statuses[profile.id] ?? .stopped : .unavailable
    }

    public func refresh() {
        if registryAvailable { _ = readRegistry() }
        refreshExistingInstances()
    }

    public func retryRegistry() {
        defer { refreshExistingInstances() }
        guard let registry = readRegistry() else { return }
        if automaticallyDiscover, installation == nil, !isChecking {
            discoverApplication(savedPath: registry.applicationPath)
        }
    }

    private func refreshExistingInstances() {
        let receipts = profiles.compactMap(\.receipt)
        let lockPIDs = Set(profiles.compactMap { DesktopLauncher.lockProcessID(store.paths(for: $0)) })
        existingInstances = runningInstances().filter { instance in
            !lockPIDs.contains(instance.pid) && !receipts.contains {
                $0.matches(pid: instance.pid, launchedAt: instance.launchedAt, bundlePath: instance.bundlePath)
            }
        }
    }

    public func focusExistingInstance(_ instance: ProcessReceipt) {
        // Verify again at click time: the observed PID may have exited or been reused.
        guard let app = DesktopLauncher.application(matching: instance, application: application) else {
            refresh()
            error = Texts.t("这个 \(application.name) 窗口已关闭或发生变化，请查看更新后的列表。", "This \(application.name) instance has closed or changed. Check the refreshed list.")
            return
        }
        if !app.activate(options: [.activateAllWindows]) {
            error = Texts.t("未能切换到这个 \(application.name)，请从 Dock 打开对应窗口。", "Could not focus this \(application.name) instance. Open its window from the Dock.")
        }
    }

    @discardableResult
    private func readRegistry(createIfMissing: Bool = false) -> Registry? {
        do {
            var registry = try store.load(createIfMissing: createIfMissing)
            if application == .wechat {
                // Recover a still-running copy after a launcher restart or receipt-write failure.
                for index in registry.profiles.indices where registry.profiles[index].archived != true {
                    let profile = registry.profiles[index]
                    if let app = DesktopLauncher.runningWeChatProfile(store.paths(for: profile)),
                       let date = DesktopLauncher.launchDate(app), let url = app.bundleURL {
                        let receipt = ProcessReceipt(pid: app.processIdentifier, launchedAt: date, bundlePath: url.resolvingSymlinksInPath().path)
                        if receipt != profile.receipt {
                            try store.record(receipt, for: profile.id)
                            registry.profiles[index].receipt = receipt
                        }
                    }
                }
            }
            profiles = registry.profiles.filter { $0.archived != true }
            archivedProfiles = registry.profiles.filter { $0.archived == true }
            var next: [UUID: InstanceStatus] = [:]
            for profile in profiles {
                let paths = store.paths(for: profile)
                if starting.contains(profile.id) { next[profile.id] = .starting }
                else if let app = DesktopLauncher.trackedApplication(profile, application: application),
                        DesktopLauncher.confirmsProfile(app, paths: paths, application: application) { next[profile.id] = .running }
                else if DesktopLauncher.trackedApplication(profile, application: application) != nil || DesktopLauncher.hasLiveProfile(paths, application: application) {
                    next[profile.id] = .untracked
                } else { next[profile.id] = .stopped }
            }
            statuses = next
            registryError = nil
            registryAvailable = true
            return registry
        } catch {
            registryError = error.localizedDescription
            registryAvailable = false
            statuses = [:]
            return nil
        }
    }

    public func discoverApplication(savedPath: String? = nil) {
        guard registryAvailable, let registry = readRegistry() else { return }
        var urls: [URL] = []
        let preferredPath = savedPath ?? installation?.url.path ?? registry.applicationPath
        if let preferredPath { urls.append(URL(fileURLWithPath: preferredPath)) }
        if let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: application.bundleIdentifier) { urls.append(found) }
        for path in application.candidatePaths {
            urls.append(URL(fileURLWithPath: path))
        }
        urls.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(application.name).app"))
        checkApplications(urls)
    }

    public func chooseApplication() {
        guard registryAvailable else { return }
        let panel = NSOpenPanel()
        panel.title = Texts.t("选择 \(application.name) 应用", "Choose \(application.name)")
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { checkApplications([url]) }
    }

    @discardableResult
    public func checkApplications(_ urls: [URL]) -> Task<Void, Never> {
        let application = application
        checkTask?.cancel()
        isChecking = true
        let task = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<CodexInstallation, Error> in
                Result { try CodexInstallation.find(in: urls, application: application) }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.isChecking = false
            switch result {
            case .success(let app):
                self.installation = app
                self.installationIssue = nil
                guard self.registryAvailable else { return }
                do { try self.store.setApplication(app.url) }
                catch { self.error = error.localizedDescription; self.refresh() }
            case .failure(let failure):
                self.installation = nil
                self.installationIssue = failure.localizedDescription
            }
        }
        checkTask = task
        return task
    }

    private func requireRegistry() throws {
        refresh()
        guard registryAvailable else {
            throw LauncherError("账号列表暂不可用，请先重试读取。", "The profile registry is unavailable. Retry reading it first.")
        }
    }

    public func create(name: String) throws {
        try requireRegistry()
        _ = try store.create(name: name)
        refresh()
    }

    public func create(name: String, provider: APIProvider, apiKey: String) throws {
        try requireRegistry()
        _ = try store.create(name: name, provider: provider, apiKey: apiKey)
        refresh()
        notice = application == .claude ? Texts.t("API 空间已创建，打开后使用已配置的供应商。", "API profile created. Open it to use the configured provider.") : Texts.t("API 空间已创建。打开后在左上角选择 Codex，再新建聊天。", "API profile created. Select Codex at the top left after opening, then start a new chat.")
    }

    public func updateProvider(_ profile: Profile, provider: APIProvider, newAPIKey: String?) throws {
        try requireRegistry()
        guard let current = profiles.first(where: { $0.id == profile.id }), status(current) == .stopped else {
            throw LauncherError("请先退出这个空间的 \(application.name)，再修改连接设置。", "Quit this profile's \(application.name) before editing its connection.")
        }
        try store.updateProvider(profile.id, provider: provider, newAPIKey: newAPIKey)
        refresh()
        notice = Texts.t("连接设置已保存，下次打开此空间时生效。", "Connection saved. It applies next time you open this profile.")
    }

    public func rename(_ profile: Profile, to name: String) throws {
        try requireRegistry()
        try store.rename(profile.id, to: name)
        refresh()
    }

    public func launch(_ profile: Profile) {
        guard application.supportsSeparateProfiles else { return }
        refresh()
        guard registryAvailable, !starting.contains(profile.id) else { return }
        guard let current = profiles.first(where: { $0.id == profile.id }) else {
            error = Texts.t("这个空间已被移除，请查看更新后的列表。", "This profile was removed. Check the updated list.")
            return
        }
        if let app = DesktopLauncher.trackedApplication(current, application: application), status(current) == .running {
            if !app.activate(options: [.activateAllWindows]) {
                error = Texts.t("未能显示这个 \(application.name) 窗口，请从 Dock 打开对应窗口。", "Could not show this \(application.name) window. Open it from the Dock.")
            }
            return
        }
        guard status(current) == .stopped else {
            error = Texts.t("这个账号的实例状态暂时无法确认。请在对应 \(application.name) 窗口内退出，再重新启动。", "This instance cannot be verified. Quit it from its \(application.name) window, then launch it again.")
            return
        }
        let installation = self.installation
        let preparedWeChat = application == .wechat && FileManager.default.fileExists(atPath: store.paths(for: current).wechatApplication.path)
        guard installation != nil || preparedWeChat else { chooseApplication(); return }
        starting.insert(profile.id)
        refresh()
        Task {
            defer { starting.remove(profile.id); refresh() }
            do {
                let lease = try store.beginLaunch(current.id)
                defer { lease.release() }
                // Recheck after application updates before every new launch.
                let checked: CodexInstallation
                do {
                    let existingPaths = store.paths(for: current)
                    checked = try await Task.detached {
                        if preparedWeChat { return try WeChatProfile.preparedInstallation(paths: existingPaths) }
                        guard let installation else { throw LauncherError("请先选择应用。", "Choose an application first.") }
                        return try CodexInstallation.inspect(installation.url, application: installation.application)
                    }.value
                } catch {
                    if !preparedWeChat {
                        self.installation = nil
                        self.installationIssue = error.localizedDescription
                    }
                    throw error
                }
                let paths = try store.prepare(current)
                let launchURL: URL
                if application == .wechat {
                    notice = Texts.t("正在准备并校验微信空间，首次打开需要稍等。", "Preparing and verifying the WeChat profile. First launch may take a moment.")
                    launchURL = try await Task.detached { try WeChatProfile.prepare(source: checked.url, paths: paths) }.value
                } else { launchURL = checked.url }
                let app = try await DesktopLauncher.open(application: launchURL, plan: LaunchPlan(paths: paths, application: application))
                guard let launchDate = DesktopLauncher.launchDate(app), let bundleURL = app.bundleURL else {
                    throw LauncherError("应用已打开，但无法记录实例。请检查新窗口。", "The app opened, but its process identity is unavailable. Check the new window.")
                }
                let receipt = ProcessReceipt(pid: app.processIdentifier, launchedAt: launchDate,
                                             bundlePath: bundleURL.resolvingSymlinksInPath().path)
                try store.record(receipt, for: current.id)
                for _ in 0..<60 {
                    if app.isTerminated { break }
                    if DesktopLauncher.confirmsProfile(app, paths: paths, application: application) {
                        if application != .wechat { self.installation = checked }
                        notice = current.apiProvider == nil
                            ? Texts.t("\(current.name) 已打开；首次使用请在新窗口中登录。", "\(current.name) opened. Sign in in the new window on first use.")
                            : application == .claude ? Texts.t("\(current.name) 已打开；如出现登录选择页，请选择使用已配置的供应商。", "\(current.name) opened. If a sign-in choice appears, choose the configured provider.") : Texts.t("\(current.name) 已打开。在左上角选择 Codex → 新聊天；API Key 不提供 Work 浏览器账号登录。", "\(current.name) opened. Select Codex → New chat at the top left. An API key does not sign in to Work browser services.")
                        return
                    }
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
                throw LauncherError("\(application.name) 未能确认启动，请检查窗口；账号数据已保留。", "Could not confirm \(application.name) startup. Check its window; profile data has been preserved.")
            } catch { self.notice = nil; self.error = error.localizedDescription }
        }
    }

    public func requestQuit(_ profile: Profile) {
        refresh()
        guard registryAvailable, let current = profiles.first(where: { $0.id == profile.id }),
              status(current) == .running,
              let app = DesktopLauncher.trackedApplication(current, application: application),
              DesktopLauncher.confirmsProfile(app, paths: store.paths(for: current), application: application) else { return }
        let alert = NSAlert()
        alert.messageText = Texts.t("退出「\(current.name)」？", "Quit “\(current.name)”?")
        alert.informativeText = Texts.t("请先确认这个窗口中的任务已完成。只会请求这个实例正常退出。", "Finish any tasks in this window first. This requests a normal quit of this instance.")
        alert.addButton(withTitle: Texts.t("退出这个账号", "Quit this instance"))
        alert.addButton(withTitle: Texts.t("取消", "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            // Verify again after the confirmation dialog, guarding against process-ID reuse.
            refresh()
            guard registryAvailable, let target = DesktopLauncher.trackedApplication(current, application: application),
                  DesktopLauncher.confirmsProfile(target, paths: store.paths(for: current), application: application) else { return }
            if target.terminate() {
                notice = Texts.t("已请求退出；如有保存提示，请在 \(application.name) 窗口中处理。", "Quit requested. Handle any save prompt in the \(application.name) window.")
            } else {
                error = Texts.t("未能请求退出，请在对应 \(application.name) 窗口中手动退出。", "Could not request a quit. Quit from this \(application.name) window manually.")
            }
        }
        refresh()
    }

    public func showFolder(_ profile: Profile) {
        do {
            try requireRegistry()
            let directory = try store.folderURL(for: profile)
            if !NSWorkspace.shared.open(directory) {
                throw LauncherError("无法打开空间文件夹，请复制路径后在 Finder 中打开。", "Could not open the profile folder. Copy its path and open it in Finder.")
            }
        } catch { self.error = error.localizedDescription }
    }

    public func trash(_ profile: Profile) {
        refresh()
        guard registryAvailable, status(profile) == .stopped else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Texts.t("移除「\(profile.name)」？", "Remove “\(profile.name)”?")
        if application == .wechat {
            alert.messageText = Texts.t("归档「\(profile.name)」？", "Archive “\(profile.name)”?")
            alert.informativeText = Texts.t("应用副本、登录信息和聊天数据都会保留。可在「已归档空间」中恢复。", "The app copy, sign-in information and chats are preserved. Restore it from Archived profiles.")
        } else {
            alert.informativeText = Texts.t("这个账号的本地登录信息、历史记录和设置会一起移至废纸篓。其他账号不受影响。", "This profile’s local sign-in data, history and settings will move to the Trash. Other profiles are unaffected.")
        }
        alert.addButton(withTitle: application == .wechat ? Texts.t("归档", "Archive") : Texts.t("移至废纸篓", "Move to Trash"))
        alert.addButton(withTitle: Texts.t("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        refresh()
        guard registryAvailable, status(profile) == .stopped else { return }
        do {
            if application == .wechat { try store.setWeChatArchived(profile.id, archived: true) }
            else { try store.moveToTrash(profile.id) }
            refresh()
        }
        catch { self.error = error.localizedDescription }
    }

    public func restoreWeChat(_ profile: Profile) {
        do { try requireRegistry(); try store.setWeChatArchived(profile.id, archived: false); refresh() }
        catch { self.error = error.localizedDescription }
    }
}

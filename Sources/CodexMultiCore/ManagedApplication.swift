import Foundation

public enum ManagedApplication: String, Codable, CaseIterable, Identifiable {
    case codex, claude, workbuddy, wechat
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .workbuddy: return "WorkBuddy"
        case .wechat: return Texts.t("微信", "WeChat")
        }
    }
    public var bundleIdentifier: String {
        switch self {
        case .codex: return "com.openai.codex"
        case .claude: return "com.anthropic.claudefordesktop"
        case .workbuddy: return "com.tencent.workbuddy.mac"
        case .wechat: return "com.tencent.xinWeChat"
        }
    }
    // WorkBuddy additionally requires a private child-process home for account storage.
    public var supportsSeparateProfiles: Bool { true }
    public var supportsAPIProfiles: Bool { self == .codex || self == .claude }
    public var candidatePaths: [String] {
        switch self {
        case .codex: return ["/Applications/Codex.app", "/Applications/ChatGPT.app"]
        case .claude: return ["/Applications/Claude.app"]
        case .workbuddy: return ["/Applications/WorkBuddy.app"]
        case .wechat: return ["/Applications/WeChat.app"]
        }
    }
    public func dataRoot(base: URL) -> URL {
        self == .codex ? base : base.appendingPathComponent("apps/\(rawValue)", isDirectory: true)
    }
}

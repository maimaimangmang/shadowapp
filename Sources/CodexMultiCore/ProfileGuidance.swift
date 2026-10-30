import Foundation

public enum ProfileGuidance {
    public static let start = "<!-- BEGIN CODEX MULTI PROFILE CONTEXT -->"
    public static let end = "<!-- END CODEX MULTI PROFILE CONTEXT -->"

    public static func block(paths: ProfilePaths) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let configPath = String(data: try! encoder.encode(paths.config.path), encoding: .utf8)!
        return """
        \(start)
        ## Active ShadowApp profile

        This process uses an isolated CODEX_HOME. Its configuration file is:
        \(configPath)

        When identifying or changing this instance's configuration:
        - Resolve CODEX_HOME first. If the shell does not expose it, use the profile path above. Do not substitute ~/.codex/config.toml: HOME and ~ still refer to the macOS user's home, not this isolated profile.
        - For "which model am I using", prefer this conversation's current model/provider metadata. The model in config.toml is a configured default and can differ from a per-conversation selection. Only claim to have checked session metadata after actually reading a typed session_meta / turn_context record with a tool, or receiving explicit trusted runtime metadata. These instructions do not supply the active model identity. Never invent metadata or cite internal recollection as evidence. If you cannot inspect a reliable source, say the active model is unverified and direct the user to the launcher’s Model information entry. State which evidence you checked; do not infer the model from the Codex app name, your self-description, or another profile's files.
        - Read only the model/provider fields needed for diagnosis. Do not dump configuration files, authentication files, environment variables, API keys or tokens to identify a model. The provider's actual upstream routing can only be confirmed by its own request records.
        - An API key enables the configured model provider; it does not authenticate a ChatGPT account for Work browser features. If Work reports "Work browser access requires an authenticated account", guide the user to the product selector > Codex > a new local chat. Do not treat that error as proof that the provider key is invalid or attempt to bypass account authentication.
        \(end)
        """
    }

    /// Preserve user instructions byte-for-byte outside our clearly delimited block.
    public static func merging(_ existing: String, paths: ProfilePaths) throws -> String {
        let beginCount = existing.components(separatedBy: start).count - 1
        let endCount = existing.components(separatedBy: end).count - 1
        guard beginCount <= 1, beginCount == endCount else { throw malformed() }
        if let begin = existing.range(of: start), let finish = existing.range(of: end) {
            guard begin.lowerBound < finish.lowerBound else { throw malformed() }
            var result = existing
            result.replaceSubrange(begin.lowerBound..<finish.upperBound, with: block(paths: paths))
            return result
        }
        return block(paths: paths) + "\n\n" + existing
    }

    private static func malformed() -> LauncherError {
        LauncherError("空间指令中的启动器标记不完整，请检查 AGENTS 文件；原文已保留。", "Launcher markers in the profile's AGENTS file are incomplete. Check the file; the original is preserved.")
    }
}

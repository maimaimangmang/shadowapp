import Foundation

/// Display and routing metadata only. Never put an API key in the registry.
public struct APIProvider: Codable, Equatable {
    public static let shengsuanyunURL = "https://router.shengsuanyun.com/api/v1"
    public static let shengsuanyunClaudeURL = "https://router.shengsuanyun.com/api"
    public var name: String
    public var baseURL: String
    public var modelID: String

    public init(name: String, baseURL: String, modelID: String) {
        self.name = name
        self.baseURL = baseURL
        self.modelID = modelID
    }

    public func validated(application: ManagedApplication = .codex) throws -> APIProvider {
        guard application.supportsAPIProfiles else {
            throw LauncherError("请在 WorkBuddy 的设置中配置自定义模型。", "Configure custom models in WorkBuddy settings.")
        }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw LauncherError("请填写供应商名称（最多 80 字）。", "Enter a provider name of up to 80 characters.")
        }
        guard !model.isEmpty, model.count <= 256,
              model.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
            throw LauncherError("请粘贴完整模型 ID，不能包含空格或换行。", "Paste a complete model ID without spaces or line breaks.")
        }
        guard let url = URLComponents(string: address), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              address.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)),
              let resolved = url.url else {
            throw LauncherError("请填写 HTTPS 接口地址，不要包含密钥、查询参数或片段。本机服务可使用 HTTP。", "Enter an HTTPS base URL without credentials, query or fragment. Localhost may use HTTP.")
        }
        var normalized = resolved.absoluteString.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard !["/responses", "/chat/completions", "/messages"].contains(where: normalized.hasSuffix) else {
            if application == .claude { throw LauncherError("请填写网关根地址，不要加 /v1/messages 或 /messages。", "Enter the gateway base URL without /v1/messages or /messages.") }
            throw LauncherError("请填写 Base URL（通常以 /v1 结尾），不要加 /responses 或 /chat/completions。", "Enter the base URL (usually ending in /v1), without /responses or /chat/completions.")
        }
        if application == .claude {
            if normalized.hasSuffix("/v1") { normalized = String(normalized.dropLast(3)) }
            try ClaudeProviderConfiguration.validateModel(model)
        }
        return APIProvider(name: name, baseURL: normalized, modelID: model)
    }

    public static func validatedKey(_ raw: String) throws -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.count <= 8192,
              key.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
            throw LauncherError("请填写有效的 API Key，不能包含空格或换行。", "Enter an API key without spaces or line breaks.")
        }
        return key
    }

    // JSON basic strings use escapes supported by TOML; no interpolated TOML syntax.
    private func quoted(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(data: try! encoder.encode(value), encoding: .utf8)!
    }

    public var configuration: String {
        """
        # BEGIN CODEX MULTI PROVIDER — edit through the launcher
        cli_auth_credentials_store = "file"
        model_provider = "codex_multi"
        model = \(quoted(modelID))

        [model_providers.codex_multi]
        name = \(quoted(name))
        base_url = \(quoted(baseURL))
        wire_api = "responses"
        requires_openai_auth = true
        # END CODEX MULTI PROVIDER


        """
    }
}

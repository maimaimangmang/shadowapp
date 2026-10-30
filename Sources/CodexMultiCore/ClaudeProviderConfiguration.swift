import Foundation

/// Claude Desktop's native per-profile 3P configuration library. No global policies.
public enum ClaudeProviderConfiguration {
    public static func validateModel(_ model: String) throws {
        let lower = model.lowercased()
        if lower.range(of: #"^(sonnet|opus|haiku|fable|mythos)(-[\d.]+)?$"#, options: .regularExpression) != nil { return }
        let blocked = #"ark-code|astron|command-r|deepseek|doubao|gemini|gemma|glm|gpt|grok|hermes|hy3|kimi|lfm|\bling\b|llama|longcat|mimo|minimax|mistral|mixtral|moonshot|nemotron|openai|phi-|qianfan|qwen|tc-code|\bunic\b|yi-|stepfun|step-3|seed-|bytedance|hunyuan|granite|amazon\.nova|nova-|devstral|ministral|ernie|codex|arcee|trinity|abab|phi\d|\bk2\.|\bm2\.|jamba|arctic|solar|mercury|zamba|kat-coder|\bds-|dpsk"#
        guard lower.range(of: blocked, options: .regularExpression) == nil,
              ["claude", "sonnet", "opus", "haiku", "fable", "mythos", "anthropic"].contains(where: lower.contains) else {
            throw LauncherError("Claude 桌面版仅支持 Claude 模型或对应的网关模型 ID，例如 anthropic/claude-sonnet-5。", "Claude Desktop requires a Claude model or its gateway model ID, such as anthropic/claude-sonnet-5.")
        }
    }

    public static func configuration(provider: APIProvider, key: String) throws -> Data {
        var value = routing(provider)
        value["inferenceGatewayApiKey"] = key
        return try encode(value)
    }

    private static func routing(_ provider: APIProvider) -> [String: Any] {
        ["inferenceProvider": "gateway", "inferenceCredentialKind": "static",
         "inferenceGatewayBaseUrl": provider.baseURL, "inferenceGatewayAuthScheme": "bearer",
         "modelDiscoveryEnabled": false, "inferenceModels": [["name": provider.modelID]]]
    }

    public static func metadata(id: UUID, name: String) throws -> Data {
        let id = id.uuidString.lowercased()
        return try encode(["appliedId": id, "entries": [["id": id, "name": name]]])
    }

    public static func validate(_ data: Data, provider: APIProvider) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["inferenceProvider"] as? String == "gateway",
              value["inferenceCredentialKind"] as? String == "static",
              value["inferenceGatewayBaseUrl"] as? String == provider.baseURL,
              value["inferenceGatewayAuthScheme"] as? String == "bearer",
              value["modelDiscoveryEnabled"] as? Bool == false,
              let key = value["inferenceGatewayApiKey"] as? String, !key.isEmpty else { throw changed() }
        let names: [String]
        if let entries = value["inferenceModels"] as? [[String: Any]] { names = entries.compactMap { $0["name"] as? String } }
        else { names = value["inferenceModels"] as? [String] ?? [] }
        guard names == [provider.modelID], value["inferenceCredentialHelper"] == nil,
              value["inferenceGatewayOidc"] == nil, value["inferenceCustomHeaders"] == nil else { throw changed() }
        return value
    }

    public static func updating(_ data: Data, original: APIProvider, replacement: APIProvider, key: String?) throws -> Data {
        var value = try validate(data, provider: original)
        for (field, content) in routing(replacement) { value[field] = content }
        // Native safeStorage may have sealed this string. Preserve it verbatim when no replacement is supplied.
        if let key { value["inferenceGatewayApiKey"] = key }
        return try encode(value)
    }

    public static func validateSelection(metadata: Data, desktop: Data, id: UUID) throws {
        guard let meta = try JSONSerialization.jsonObject(with: metadata) as? [String: Any],
              meta["appliedId"] as? String == id.uuidString.lowercased(),
              let config = try JSONSerialization.jsonObject(with: desktop) as? [String: Any],
              config["deploymentMode"] as? String == "3p" else { throw changed() }
    }

    public static func encode(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    private static func changed() -> LauncherError {
        LauncherError("Claude 的供应商配置已改变或缺失，请检查空间文件夹中的 configLibrary；原文件已保留。", "Claude provider configuration has changed or is missing. Check configLibrary in this profile; existing files are preserved.")
    }
}

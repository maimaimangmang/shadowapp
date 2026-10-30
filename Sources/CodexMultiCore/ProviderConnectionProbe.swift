import Foundation

public enum ProviderConnectionResult: Equatable {
    case completed, outputLimited

    public var message: String {
        switch self {
        case .completed: return Texts.t("连接成功，模型已响应。", "Connected. The model responded.")
        case .outputLimited: return Texts.t("接口已响应，测试输出达到上限。", "The endpoint responded; the test reached its output limit.")
        }
    }
}

private final class NoProbeRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Sends only a fixed test prompt to the user-selected provider. Never includes local files or chats.
public enum ProviderConnectionProbe {
    public static func request(provider: APIProvider, key: String, application: ManagedApplication = .codex) throws -> URLRequest {
        let provider = try provider.validated(application: application)
        let key = try APIProvider.validatedKey(key)
        var request = URLRequest(url: URL(string: provider.baseURL + (application == .claude ? "/v1/messages" : "/responses"))!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if application == .claude {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": provider.modelID, "max_tokens": 64, "stream": false,
                "messages": [["role": "user", "content": "Reply with OK."]]
            ])
            return request
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": provider.modelID,
            "input": "Reply with OK.",
            "max_output_tokens": 64,
            "stream": false,
            "store": false
        ])
        return request
    }

    public static func check(provider: APIProvider, key: String, application: ManagedApplication = .codex) async throws -> ProviderConnectionResult {
        let request = try request(provider: provider, key: key, application: application)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: NoProbeRedirects())
            guard let response = response as? HTTPURLResponse else { throw invalidResponse() }
            guard (200..<300).contains(response.statusCode) else { throw httpFailure(response.statusCode) }
            var body = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard body.count < 262_144 else {
                    throw LauncherError("测试响应过大，已停止读取。请检查接口兼容性。", "The test response is too large. Check API compatibility.")
                }
                body.append(byte)
            }
            return try interpret(body, status: response.statusCode, application: application)
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut {
                throw LauncherError("连接超时，请检查网络或稍后重试。", "Connection timed out. Check your network or try again later.")
            }
            throw LauncherError("无法连接接口，请检查地址、网络或证书。", "Could not connect. Check the endpoint, network, or certificate.")
        }
    }

    public static func interpret(_ data: Data, status: Int, application: ManagedApplication = .codex) throws -> ProviderConnectionResult {
        guard (200..<300).contains(status) else { throw httpFailure(status) }
        if application == .claude {
            guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  value["type"] as? String == "message", value["role"] as? String == "assistant",
                  let id = value["id"] as? String, !id.isEmpty,
                  let content = value["content"] as? [[String: Any]], !content.isEmpty,
                  let stop = value["stop_reason"] as? String else {
                throw LauncherError("接口没有返回有效的 Anthropic Messages 结果，请检查地址与模型兼容性。", "The endpoint did not return a valid Anthropic Messages result. Check the base URL and model compatibility.")
            }
            if stop == "max_tokens" { return .outputLimited }
            guard ["end_turn", "stop_sequence", "tool_use"].contains(stop) else {
                throw LauncherError("接口已响应，但模型未完成测试。", "The endpoint responded, but the model did not complete the test.")
            }
            return .completed
        }
        // Do not display remote error text, which may echo credentials or request headers.
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["object"] as? String == "response", value["error"] == nil || value["error"] is NSNull,
              let id = value["id"] as? String, !id.isEmpty,
              value["output"] is [Any] else { throw invalidResponse() }
        if value["status"] as? String == "completed" { return .completed }
        if value["status"] as? String == "incomplete",
           (value["incomplete_details"] as? [String: Any])?["reason"] as? String == "max_output_tokens" { return .outputLimited }
        throw LauncherError("请求已到达接口，但模型未完成测试。请检查模型权限或稍后重试。", "The endpoint received the request, but the model did not complete the test. Check model access or try again later.")
    }

    private static func invalidResponse() -> LauncherError {
        LauncherError("接口没有返回有效的 Responses API 结果，请检查接口地址和模型兼容性。", "The endpoint did not return a valid Responses API result. Check the base URL and model compatibility.")
    }

    private static func httpFailure(_ status: Int) -> LauncherError {
        switch status {
        case 300..<400: return LauncherError("接口要求跳转，测试已停止。请填写最终接口地址。", "The endpoint requested a redirect. Enter its final URL and retry.")
        case 401: return LauncherError("API Key 验证失败（401），请检查 Key 是否正确或已失效。", "API key authentication failed (401). Check whether the key is correct and active.")
        case 403: return LauncherError("接口拒绝访问（403），请检查账号及模型权限。", "Access denied (403). Check account and model permissions.")
        case 404: return LauncherError("未找到接口或模型（404），请检查 Base URL 和模型 ID。", "Endpoint or model not found (404). Check the base URL and model ID.")
        case 429: return LauncherError("请求受限（429），请检查额度或稍后重试。", "Request limited (429). Check your quota or try again later.")
        case 500..<600: return LauncherError("供应商服务异常（\(status)），请稍后重试。", "Provider service error (\(status)). Try again later.")
        default: return LauncherError("测试失败（HTTP \(status)），请检查接口、模型 ID 和账号权限。", "Test failed (HTTP \(status)). Check the endpoint, model ID, and account permissions.")
        }
    }
}

import Foundation
import CodexMultiCore

func runClaudeProviderTests() -> Int {
    let fm = FileManager.default
    let provider = APIProvider(name: "Fixture", baseURL: "https://gateway.example/api", modelID: "anthropic/claude-sonnet-5")
    let tests: [(String, () throws -> Void)] = [
        ("Claude API spaces isolate configuration keys and native 3P directories", {
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let store = ProfileStore(root: root, application: .claude)
            _ = try store.load()
            let first = try store.create(name: "API", provider: provider, apiKey: "fixture-key-first")
            let second = try store.create(name: "Other", provider: provider, apiKey: "fixture-key-second")
            let account = try store.create(name: "Account")
            let paths = try store.prepare(first)
            let other = try store.prepare(second)
            XCTAssertEqual(paths.desktop.lastPathComponent, "desktop-3p")
            XCTAssertEqual(try store.prepare(account).desktop.lastPathComponent, "desktop")
            XCTAssertEqual(try store.load().schemaVersion, 4)
            XCTAssertFalse(fm.fileExists(atPath: paths.codex.path))
            let firstConfig = try ClaudeProviderConfiguration.validate(Data(contentsOf: paths.claudeProvider), provider: provider)
            let secondConfig = try ClaudeProviderConfiguration.validate(Data(contentsOf: other.claudeProvider), provider: provider)
            XCTAssertEqual(firstConfig["inferenceGatewayApiKey"] as? String, "fixture-key-first")
            XCTAssertEqual(secondConfig["inferenceGatewayApiKey"] as? String, "fixture-key-second")
            XCTAssertEqual(try fm.attributesOfItem(atPath: paths.claudeProvider.path)[.posixPermissions] as? Int, 0o600)
            XCTAssertFalse(try String(contentsOf: root.appendingPathComponent("profiles.json")).contains("fixture-key"))
            XCTAssertFalse(LaunchPlan(paths: paths, application: .claude).environment.values.contains("fixture-key-first"))
        }),
        ("Claude model edits retain native sealed key and unrelated configuration", {
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let store = ProfileStore(root: root, application: .claude)
            _ = try store.load()
            let profile = try store.create(name: "API", provider: provider, apiKey: "fixture-original")
            let paths = store.paths(for: profile)
            var config = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.claudeProvider)) as! [String: Any]
            config["inferenceGatewayApiKey"] = "__sealed__:v1:fixture-opaque-not-real"
            config["extraSetting"] = ["enabled": true]
            try ClaudeProviderConfiguration.encode(config).write(to: paths.claudeProvider)
            var updated = provider
            updated.modelID = "anthropic/claude-opus-4-8"
            try store.updateProvider(profile.id, provider: updated, newAPIKey: nil)
            let saved = try ClaudeProviderConfiguration.validate(Data(contentsOf: paths.claudeProvider), provider: updated)
            XCTAssertEqual(saved["inferenceGatewayApiKey"] as? String, "__sealed__:v1:fixture-opaque-not-real")
            XCTAssertEqual((saved["extraSetting"] as? [String: Bool])?["enabled"], true)
            XCTAssertNoThrow(try store.prepare(profile))
            let before = try Data(contentsOf: paths.claudeProvider)
            updated.baseURL = "https://different.example/api"
            XCTAssertThrowsError(try store.updateProvider(profile.id, provider: updated, newAPIKey: nil))
            XCTAssertEqual(try Data(contentsOf: paths.claudeProvider), before)
            try store.updateProvider(profile.id, provider: updated, newAPIKey: "fixture-replaced")
            XCTAssertEqual(try ClaudeProviderConfiguration.validate(Data(contentsOf: paths.claudeProvider), provider: updated)["inferenceGatewayApiKey"] as? String, "fixture-replaced")
        }),
        ("Claude refuses changed native profile selection without overwriting it", {
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let store = ProfileStore(root: root, application: .claude)
            _ = try store.load()
            let profile = try store.create(name: "API", provider: provider, apiKey: "fixture")
            let paths = store.paths(for: profile)
            let before = try Data(contentsOf: paths.claudeProvider)
            try Data("{\"appliedId\":\"another-profile\"}".utf8).write(to: paths.claudeLibraryMetadata)
            XCTAssertThrowsError(try store.prepare(profile))
            XCTAssertThrowsError(try store.updateProvider(profile.id, provider: provider, newAPIKey: "new-fixture"))
            XCTAssertEqual(try Data(contentsOf: paths.claudeProvider), before)
        }),
        ("Claude provider files reject symlink redirects", {
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let store = ProfileStore(root: root, application: .claude)
            _ = try store.load()
            let profile = try store.create(name: "API", provider: provider, apiKey: "fixture")
            let paths = store.paths(for: profile)
            let original = paths.claudeLibrary.appendingPathComponent("original.json")
            try fm.moveItem(at: paths.claudeProvider, to: original)
            let before = try Data(contentsOf: original)
            try fm.createSymbolicLink(at: paths.claudeProvider, withDestinationURL: original)
            XCTAssertThrowsError(try store.prepare(profile))
            XCTAssertThrowsError(try store.updateProvider(profile.id, provider: provider, newAPIKey: "new-fixture"))
            XCTAssertEqual(try Data(contentsOf: original), before)
        }),
        ("Claude native model limits and base URL normalization are explicit", {
            var changed = provider
            changed.baseURL += "/v1/"
            XCTAssertEqual(try changed.validated(application: .claude).baseURL, provider.baseURL)
            XCTAssertEqual(try changed.validated().baseURL, provider.baseURL + "/v1")
            for id in ["deepseek/chat", "claude-deepseek", "bigmodel/glm-5", "gpt-5", "custom-route"] {
                changed.modelID = id
                XCTAssertThrowsError(try changed.validated(application: .claude))
            }
            for id in ["Anthropic/Claude-Sonnet-5", "sonnet", "gateway/opus-4-8"] {
                changed.modelID = id
                XCTAssertEqual(try changed.validated(application: .claude).modelID, id)
            }
        }),
        ("Claude Messages probe uses its own protocol and never sends Codex payload fields", {
            let request = try ProviderConnectionProbe.request(provider: provider, key: "fixture", application: .claude)
            XCTAssertEqual(request.url?.absoluteString, provider.baseURL + "/v1/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, provider.modelID)
            XCTAssertEqual(body["max_tokens"] as? Int, 64)
            XCTAssertNil(body["input"])
            XCTAssertNil(body["max_output_tokens"])
            let good = Data(#"{"id":"msg_fixture","type":"message","role":"assistant","content":[{"type":"text","text":"OK"}],"stop_reason":"end_turn"}"#.utf8)
            XCTAssertEqual(try ProviderConnectionProbe.interpret(good, status: 200, application: .claude), .completed)
            XCTAssertThrowsError(try ProviderConnectionProbe.interpret(good, status: 200))
            let echoed = Data(#"{"error":{"message":"fixture-secret"}}"#.utf8)
            do { _ = try ProviderConnectionProbe.interpret(echoed, status: 401, application: .claude) }
            catch { XCTAssertFalse(error.localizedDescription.contains("fixture-secret")) }
        })
    ]
    for (name, test) in tests {
        let before = failures
        do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }
        if before == failures { print("PASS \(name)") }
    }
    return tests.count
}

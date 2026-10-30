import Foundation
import CodexMultiCore

func runProviderConnectionProbeTests() -> Int {
    let provider = APIProvider(name: "Fixture", baseURL: "https://example.com/v1/", modelID: "vendor/exact-model")
    let tests: [(String, () throws -> Void)] = [
        ("connection probe sends exact model to Responses with a bounded fixed prompt", {
            let request = try ProviderConnectionProbe.request(provider: provider, key: " fixture-key ")
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/responses")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, "vendor/exact-model")
            XCTAssertEqual(body["input"] as? String, "Reply with OK.")
            XCTAssertEqual(body["max_output_tokens"] as? Int, 64)
            XCTAssertEqual(body["stream"] as? Bool, false)
            XCTAssertEqual(body["store"] as? Bool, false)
            XCTAssertNil(body["tools"])
        }),
        ("connection probe distinguishes completed from output-limited responses", {
            let completed = Data(#"{"object":"response","id":"r","status":"completed","output":[],"error":null}"#.utf8)
            XCTAssertEqual(try ProviderConnectionProbe.interpret(completed, status: 200), .completed)
            let limited = Data(#"{"object":"response","id":"r","status":"incomplete","output":[],"incomplete_details":{"reason":"max_output_tokens"}}"#.utf8)
            XCTAssertEqual(try ProviderConnectionProbe.interpret(limited, status: 200), .outputLimited)
        }),
        ("HTTP and malformed responses never expose echoed secrets", {
            let echoed = Data(#"{"error":{"message":"SECRET-ECHO"}}"#.utf8)
            for status in [200, 301, 401, 403, 404, 429, 500] {
                do {
                    _ = try ProviderConnectionProbe.interpret(echoed, status: status)
                    XCTAssertTrue(false)
                } catch {
                    XCTAssertFalse(error.localizedDescription.contains("SECRET-ECHO"))
                }
            }
            XCTAssertThrowsError(try ProviderConnectionProbe.interpret(Data("<html>OK</html>".utf8), status: 200))
            XCTAssertThrowsError(try ProviderConnectionProbe.interpret(Data(#"{"object":"response","id":"r","status":"failed","output":[]}"#.utf8), status: 200))
        }),
        ("connection probe rejects invalid keys and endpoints before sending", {
            XCTAssertThrowsError(try ProviderConnectionProbe.request(provider: provider, key: ""))
            XCTAssertThrowsError(try ProviderConnectionProbe.request(provider: provider, key: "bad\nkey"))
            let unsafe = APIProvider(name: "Fixture", baseURL: "http://example.com/v1", modelID: "model")
            XCTAssertThrowsError(try ProviderConnectionProbe.request(provider: unsafe, key: "fixture"))
        }),
        ("name validation matches storage and allows renaming the same profile", {
            let existing = Profile(name: "Work")
            XCTAssertThrowsError(try ProfileName.validate(" work ", profiles: [existing]))
            XCTAssertEqual(try ProfileName.validate(" Work ", profiles: [existing], excluding: existing.id), "Work")
        }),
        ("duplicate API profile does not write a new directory or change existing data", {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = ProfileStore(root: root)
            _ = try store.load()
            let existing = try store.create(name: "2", provider: provider, apiKey: "original-fixture")
            let auth = try Data(contentsOf: store.paths(for: existing).auth)
            let registry = try Data(contentsOf: root.appendingPathComponent("profiles.json"))
            XCTAssertThrowsError(try store.create(name: " 2 ", provider: provider, apiKey: "replacement-fixture"))
            XCTAssertEqual(try Data(contentsOf: store.paths(for: existing).auth), auth)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("profiles.json")), registry)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("profiles").path).count, 1)
        })
    ]
    for (name, test) in tests {
        let before = failures
        do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }
        if before == failures { print("PASS \(name)") }
    }
    return tests.count
}

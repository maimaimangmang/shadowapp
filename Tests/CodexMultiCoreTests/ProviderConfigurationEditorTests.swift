import Foundation
import CodexMultiCore

func runProviderConfigurationEditorTests() -> Int {
    let original = APIProvider(name: "Fixture", baseURL: "https://example.invalid/v1", modelID: "old")
    let replacement = APIProvider(name: "Updated", baseURL: original.baseURL, modelID: "vendor/new")
    func update(_ source: String) throws -> String {
        try ProviderConfigurationEditor.updating(source, original: original, replacement: replacement)
    }
    let reordered = """
    # Client-reordered fixture
    model = 'selected-in-client' # preserve this comment
    model_reasoning_effort = "high"
    cli_auth_credentials_store = 'file'
    model_provider = "codex_multi"

    [projects.'/tmp/project.with.dots']
    trust_level = 'trusted'

    [model_providers."codex_multi"]
    requires_openai_auth = true
    wire_api = 'responses'
    name = 'Fixture'
    base_url = 'https://example.invalid/v1/'
    request_max_retries = 3
    """
    let tests: [(String, () throws -> Void)] = [
        ("provider edits support client reordering and retain unrelated bytes", {
            let result = try update(reordered)
            var expected = reordered
            for (old, new) in [("'selected-in-client'", "\"vendor/new\""), ("'file'", "\"file\""), ("'responses'", "\"responses\""), ("'Fixture'", "\"Updated\""), ("'https://example.invalid/v1/'", "\"https://example.invalid/v1\"")] {
                expected = expected.replacingOccurrences(of: old, with: new)
            }
            XCTAssertEqual(result, expected)
            XCTAssertEqual(try update(reordered.replacingOccurrences(of: "\n", with: "\r\n")), expected.replacingOccurrences(of: "\n", with: "\r\n"))
        }),
        ("provider edits ignore fake settings inside multiline strings and arrays", {
            let suffix = #"""

            [unrelated]
            text = """
            model_provider = "evil"
            [model_providers.codex_multi]
            base_url = "https://other.invalid/v1"
            """
            literal = '''
            model = "not-a-setting"
            '''
            items = [
                {name = "not # a comment", value = "escaped \" quotes"}, # comment
                "model = fake",
            ]
            """#
            let result = try update(original.configuration + suffix)
            XCTAssertEqual(result, replacement.configuration + suffix)
        }),
        ("provider edits support dotted and escaped keys", {
            let text = original.configuration.replacingOccurrences(of: "[model_providers.codex_multi]\n", with: "")
                .replacingOccurrences(of: "name =", with: "model_providers.codex_multi.name =")
                .replacingOccurrences(of: "base_url =", with: "model_providers.codex_multi.base_url =")
                .replacingOccurrences(of: "wire_api =", with: "model_providers.codex_multi.wire_api =")
                .replacingOccurrences(of: "requires_openai_auth =", with: "model_providers.codex_multi.requires_openai_auth =")
                .replacingOccurrences(of: "model_provider =", with: "\"model_\\u0070rovider\" =")
            XCTAssertTrue(try update(text).contains("model = \"vendor/new\""))
        }),
        ("provider edits reject changed routing auth and duplicate or missing settings", {
            for text in [
                original.configuration.replacingOccurrences(of: original.baseURL, with: "https://other.invalid/v1"),
                original.configuration.replacingOccurrences(of: "wire_api = \"responses\"", with: "wire_api = \"chat\""),
                original.configuration.replacingOccurrences(of: "requires_openai_auth = true", with: "requires_openai_auth = false"),
                "model = \"duplicate\"\n" + original.configuration,
                original.configuration + "\n[model_providers.codex_multi]\n",
                original.configuration + "\nenv_key = \"OTHER_KEY\"\n",
                original.configuration + "\n[model_providers.codex_multi.http_headers]\nAuthorization = \"fixture\"\n",
                original.configuration.replacingOccurrences(of: "model_provider = \"codex_multi\"", with: "model_provider = \"other\""),
                original.configuration.replacingOccurrences(of: "model = \"old\"", with: ""),
                "model_providers = {}\n" + original.configuration,
                original.configuration + "\n[unrelated]\ntext = \"\"\"unterminated\n"
            ] { XCTAssertThrowsError(try update(text)) }
        }),
        ("provider store updates reformatted config without changing saved credentials", {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = ProfileStore(root: root)
            _ = try store.load()
            let profile = try store.create(name: "Reordered", provider: original, apiKey: "fixture-only")
            let paths = store.paths(for: profile)
            let auth = try Data(contentsOf: paths.auth)
            try Data(reordered.utf8).write(to: paths.config)
            try store.updateProvider(profile.id, provider: replacement, newAPIKey: nil)
            XCTAssertEqual(try String(contentsOf: paths.config), try update(reordered))
            XCTAssertEqual(try Data(contentsOf: paths.auth), auth)
            XCTAssertEqual(try store.load().profiles.first?.apiProvider, replacement)
        })
    ]
    for (name, test) in tests {
        let before = failures
        do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }
        if before == failures { print("PASS \(name)") }
    }
    return tests.count
}

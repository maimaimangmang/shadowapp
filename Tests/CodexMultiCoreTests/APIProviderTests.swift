import Foundation
import CodexMultiCore

final class APIProviderTests {
    private var root: URL!
    private var store: ProfileStore!
    private let fixtureKey = "fixture-only-never-a-real-key"
    private var provider: APIProvider { APIProvider(name: "Test provider", baseURL: "https://example.invalid/v1", modelID: "vendor/model-A") }

    func setUp() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-api-tests-\(UUID().uuidString)")
        store = ProfileStore(root: root)
        _ = try store.load()
    }
    func tearDown() throws { try FileManager.default.removeItem(at: root) }
    private func create() throws -> Profile { try store.create(name: "API", provider: provider, apiKey: fixtureKey) }

    func testCreationAndIsolation() throws {
        let normal = try store.create(name: "ChatGPT")
        let normalPaths = try store.prepare(normal)
        let original = try Data(contentsOf: normalPaths.config)
        let api = try create()
        let paths = try store.prepare(api)
        let auth = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: paths.auth))
        XCTAssertEqual(auth["OPENAI_API_KEY"], fixtureKey)
        XCTAssertEqual(api.apiProvider, provider)
        XCTAssertFalse(try String(contentsOf: root.appendingPathComponent("profiles.json")).contains(fixtureKey))
        XCTAssertFalse(try String(contentsOf: paths.config).contains(fixtureKey))
        XCTAssertEqual(try Data(contentsOf: normalPaths.config), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: normalPaths.auth.path))
        for file in [paths.config, paths.auth] {
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: paths.codex.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        // Optional provider metadata decodes old registries as ChatGPT profiles.
        XCTAssertNil(try store.load().profiles.first?.apiProvider)
    }

    func testValidationAndEscaping() throws {
        for address in ["http://example.com/v1", "https://user:pass@example.com/v1", "https://example.com/v1?key=x", "https://example.com/#frag", "https://example.com/v1/responses", "file:///tmp/a", "https://example.com/v1/chat/completions"] {
            XCTAssertThrowsError(try APIProvider(name: "X", baseURL: address, modelID: "model").validated())
        }
        for model in ["", "a\nb", "a b", String(repeating: "x", count: 257)] {
            XCTAssertThrowsError(try APIProvider(name: "X", baseURL: provider.baseURL, modelID: model).validated())
        }
        XCTAssertThrowsError(try store.create(name: "Invalid", provider: provider, apiKey: " "))
        XCTAssertThrowsError(try APIProvider.validatedKey("key\nother"))
        XCTAssertTrue(try store.load().profiles.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("profiles").path))
        let quoted = try APIProvider(name: "Quoted \"name\"", baseURL: "http://127.0.0.1:1234/v1/", modelID: "Vendor/Model\\\"ID").validated()
        XCTAssertEqual(quoted.baseURL, "http://127.0.0.1:1234/v1")
        XCTAssertTrue(quoted.configuration.contains("model = \"Vendor/Model\\\\\\\"ID\""))
        XCTAssertTrue(quoted.configuration.contains("name = \"Quoted \\\"name\\\"\""))
    }

    func testModelChangeAndKeyRotation() throws {
        let profile = try create()
        let paths = store.paths(for: profile)
        let originalKey = try Data(contentsOf: paths.auth)
        let extra = "[projects.\"/tmp/example\"]\ntrust_level = \"trusted\"\n"
        try Data((provider.configuration + extra).utf8).write(to: paths.config)
        var updated = provider
        updated.modelID = "vendor/model-B"
        try store.updateProvider(profile.id, provider: updated, newAPIKey: nil)
        XCTAssertEqual(try Data(contentsOf: paths.auth), originalKey)
        XCTAssertEqual(try String(contentsOf: paths.config), updated.configuration + extra)
        XCTAssertEqual(try store.load().profiles[0].apiProvider?.modelID, updated.modelID)
        try store.updateProvider(profile.id, provider: updated, newAPIKey: "fixture-rotated-key")
        let auth = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: paths.auth))
        XCTAssertEqual(auth["OPENAI_API_KEY"], "fixture-rotated-key")
        XCTAssertFalse(try String(contentsOf: root.appendingPathComponent("profiles.json")).contains("fixture-rotated-key"))
    }

    func testEndpointChangeRequiresKey() throws {
        let profile = try create()
        let paths = store.paths(for: profile)
        let before = try Data(contentsOf: paths.config)
        var changed = provider
        changed.baseURL = "https://other.example.invalid/v1"
        XCTAssertThrowsError(try store.updateProvider(profile.id, provider: changed, newAPIKey: nil))
        XCTAssertEqual(try Data(contentsOf: paths.config), before)
        try store.updateProvider(profile.id, provider: changed, newAPIKey: "fixture-other-key")
        XCTAssertEqual(try store.load().profiles[0].apiProvider?.baseURL, changed.baseURL)
        let normal = try store.create(name: "Normal")
        XCTAssertThrowsError(try store.updateProvider(normal.id, provider: provider, newAPIKey: fixtureKey))
    }

    func testExternalEditsAndMissingConfigPreserved() throws {
        let profile = try create()
        let paths = store.paths(for: profile)
        let custom = Data("# externally edited\nmodel = \"another\"\n".utf8)
        try custom.write(to: paths.config)
        XCTAssertThrowsError(try store.updateProvider(profile.id, provider: provider, newAPIKey: nil))
        XCTAssertEqual(try Data(contentsOf: paths.config), custom)
        try FileManager.default.removeItem(at: paths.config)
        XCTAssertThrowsError(try store.prepare(profile))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.config.path))
        try Data(provider.configuration.utf8).write(to: paths.config)
        try FileManager.default.removeItem(at: paths.auth)
        XCTAssertThrowsError(try store.prepare(profile))
        try store.updateProvider(profile.id, provider: provider, newAPIKey: fixtureKey)
        XCTAssertNoThrow(try store.prepare(profile))
    }

    func testCredentialSymlinkRejected() throws {
        let profile = try create()
        let paths = store.paths(for: profile)
        let outside = root.appendingPathComponent("outside.txt")
        try Data("untouched".utf8).write(to: outside)
        try FileManager.default.removeItem(at: paths.auth)
        try FileManager.default.createSymbolicLink(atPath: paths.auth.path, withDestinationPath: outside.path)
        XCTAssertThrowsError(try store.updateProvider(profile.id, provider: provider, newAPIKey: fixtureKey))
        XCTAssertEqual(try String(contentsOf: outside), "untouched")
    }

    func testLiveInstanceCannotBeEdited() throws {
        let profile = try create()
        let paths = store.paths(for: profile)
        let before = try Data(contentsOf: paths.config)
        try FileManager.default.createSymbolicLink(atPath: paths.singletonLock.path, withDestinationPath: "test-host-\(ProcessInfo.processInfo.processIdentifier)")
        XCTAssertThrowsError(try store.updateProvider(profile.id, provider: provider, newAPIKey: fixtureKey))
        XCTAssertEqual(try Data(contentsOf: paths.config), before)
    }

    func testFailedCredentialWriteRollsBack() throws {
        let profile = try create()
        let paths = store.paths(for: profile)
        let config = try Data(contentsOf: paths.config)
        let registry = try Data(contentsOf: root.appendingPathComponent("profiles.json"))
        try FileManager.default.removeItem(at: paths.auth)
        try FileManager.default.createDirectory(at: paths.auth, withIntermediateDirectories: false)
        var changed = provider
        changed.modelID = "different-model"
        XCTAssertThrowsError(try store.updateProvider(profile.id, provider: changed, newAPIKey: fixtureKey))
        XCTAssertEqual(try Data(contentsOf: paths.config), config)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("profiles.json")), registry)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: paths.codex.path).contains(where: { $0.hasPrefix(".write-") }))
    }
}

func runAPIProviderTests() -> Int {
    let suite = APIProviderTests()
    let tests: [(String, () throws -> Void)] = [
        ("API profile isolates credentials with private permissions", suite.testCreationAndIsolation),
        ("API fields validate URLs and escape TOML", suite.testValidationAndEscaping),
        ("model edits preserve keys and unrelated configuration", suite.testModelChangeAndKeyRotation),
        ("new API endpoint requires its own key", suite.testEndpointChangeRequiresKey),
        ("external or missing provider config is preserved", suite.testExternalEditsAndMissingConfigPreserved),
        ("provider edits reject credential symlinks", suite.testCredentialSymlinkRejected),
        ("provider edits reject live instances", suite.testLiveInstanceCannotBeEdited),
        ("credential write failure rolls back routing metadata", suite.testFailedCredentialWriteRollsBack)
    ]
    for (name, test) in tests {
        let before = failures
        do { try suite.setUp(); try test() }
        catch { failures += 1; print("FAIL \(name): \(error)") }
        do { try suite.tearDown() }
        catch { failures += 1; print("FAIL cleanup: \(error)") }
        if failures == before { print("PASS \(name)") }
    }
    return tests.count
}

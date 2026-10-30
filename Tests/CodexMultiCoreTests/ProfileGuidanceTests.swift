import Foundation
import CodexMultiCore

final class ProfileGuidanceTests {
    private var root: URL!
    private var store: ProfileStore!
    func setUp() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-guidance-tests-\(UUID().uuidString)")
        store = ProfileStore(root: root)
        _ = try store.load()
    }
    func tearDown() throws { try FileManager.default.removeItem(at: root) }

    func testEachProfileGetsItsOwnContext() throws {
        let a = try store.create(name: "One")
        let b = try store.create(name: "Two")
        let aPaths = try store.prepare(a)
        let bPaths = try store.prepare(b)
        let aText = try String(contentsOf: aPaths.codex.appendingPathComponent("AGENTS.md"))
        let bText = try String(contentsOf: bPaths.codex.appendingPathComponent("AGENTS.md"))
        XCTAssertTrue(aText.contains(aPaths.config.path))
        XCTAssertFalse(aText.contains(bPaths.config.path))
        XCTAssertTrue(bText.contains(bPaths.config.path))
        XCTAssertTrue(aText.contains("CODEX_HOME"))
        XCTAssertTrue(aText.contains("per-conversation selection"))
        XCTAssertTrue(aText.contains("Work browser access requires an authenticated account"))
        XCTAssertEqual(LaunchPlan(paths: aPaths).environment["CODEX_HOME"], aPaths.codex.path)
        XCTAssertNil(LaunchPlan(paths: aPaths).environment["HOME"])
    }

    func testUserInstructionsAndOverrideArePreserved() throws {
        let profile = try store.create(name: "Existing")
        let paths = try store.prepare(profile)
        let normal = paths.codex.appendingPathComponent("AGENTS.md")
        let override = paths.codex.appendingPathComponent("AGENTS.override.md")
        let userText = "# My rules\n\nUse tabs.\nKeep this exact spacing.  \n"
        let overrideText = "Temporary preference: use Chinese.\n"
        try Data(userText.utf8).write(to: normal)
        try Data(overrideText.utf8).write(to: override)
        let configBefore = try Data(contentsOf: paths.config)
        try store.prepareGuidance(for: profile)
        let first = try Data(contentsOf: normal)
        XCTAssertTrue(try String(contentsOf: normal).hasSuffix(userText))
        XCTAssertTrue(try String(contentsOf: override).hasSuffix(overrideText))
        XCTAssertTrue(try String(contentsOf: override).contains(paths.config.path))
        try store.prepareGuidance(for: profile)
        XCTAssertEqual(try Data(contentsOf: normal), first)
        XCTAssertEqual(try Data(contentsOf: paths.config), configBefore)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: normal.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testBrokenMarkersAndSymlinksArePreserved() throws {
        let profile = try store.create(name: "Invalid instructions")
        let paths = try store.prepare(profile)
        let normal = paths.codex.appendingPathComponent("AGENTS.md")
        let malformed = "My instructions\n" + ProfileGuidance.start
        try Data(malformed.utf8).write(to: normal)
        XCTAssertThrowsError(try store.prepareGuidance(for: profile))
        XCTAssertEqual(try String(contentsOf: normal), malformed)
        try FileManager.default.removeItem(at: normal)
        let outside = root.appendingPathComponent("outside.txt")
        try Data("Keep untouched".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(atPath: normal.path, withDestinationPath: outside.path)
        XCTAssertThrowsError(try store.prepareGuidance(for: profile))
        XCTAssertEqual(try String(contentsOf: outside), "Keep untouched")
    }

    func testMovedProfileRefreshesPathAndKeepsEmptyOverride() throws {
        let profile = try store.create(name: "Moved")
        let paths = try store.prepare(profile)
        let override = paths.codex.appendingPathComponent("AGENTS.override.md")
        try Data("\n  \n".utf8).write(to: override)
        let relocatedRoot = root.appendingPathComponent("relocated")
        try FileManager.default.createDirectory(at: relocatedRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appendingPathComponent("profiles.json"), to: relocatedRoot.appendingPathComponent("profiles.json"))
        try FileManager.default.copyItem(at: root.appendingPathComponent("profiles"), to: relocatedRoot.appendingPathComponent("profiles"))
        let moved = ProfileStore(root: relocatedRoot)
        try moved.prepareGuidance(for: profile)
        let next = try String(contentsOf: moved.paths(for: profile).codex.appendingPathComponent("AGENTS.md"))
        XCTAssertTrue(next.contains(moved.paths(for: profile).config.path))
        XCTAssertFalse(next.contains(paths.config.path))
        XCTAssertEqual(next.components(separatedBy: ProfileGuidance.start).count, 2)
        XCTAssertEqual(try String(contentsOf: moved.paths(for: profile).codex.appendingPathComponent("AGENTS.override.md")), "\n  \n")
    }
}

func runProfileGuidanceTests() -> Int {
    let suite = ProfileGuidanceTests()
    let tests: [(String, () throws -> Void)] = [
        ("each profile gets its own configuration guidance", suite.testEachProfileGetsItsOwnContext),
        ("guidance preserves user rules and effective overrides", suite.testUserInstructionsAndOverrideArePreserved),
        ("guidance preserves malformed markers and refuses symlinks", suite.testBrokenMarkersAndSymlinksArePreserved),
        ("guidance refreshes moved paths without enabling empty overrides", suite.testMovedProfileRefreshesPathAndKeepsEmptyOverride)
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

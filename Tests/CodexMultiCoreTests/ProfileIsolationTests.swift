import Foundation
import CodexMultiCore

final class ProfileIsolationTests {
    private var root: URL!
    private var store: ProfileStore!

    func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("codex-multi-tests-\(UUID().uuidString)")
        store = ProfileStore(root: root)
        _ = try store.load()
        _ = try store.create(name: "Fixture One")
        _ = try store.create(name: "Fixture Two")
    }

    func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testTwoProfilesDoNotShareAuthHistoryOrDesktopDirectories() throws {
        let profiles = try store.load().profiles
        let first = try store.prepare(profiles[0])
        let second = try store.prepare(profiles[1])
        XCTAssertNotEqual(first.codex, second.codex)
        XCTAssertNotEqual(first.desktop, second.desktop)
        let sentinel = first.codex.appendingPathComponent("test-session.txt")
        try Data("profile one only".utf8).write(to: sentinel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.codex.appendingPathComponent("test-session.txt").path))
        XCTAssertTrue(try String(contentsOf: first.config).contains("cli_auth_credentials_store = \"file\""))
        for directory in [root!, first.root, first.codex, first.desktop] {
            let attrs = try FileManager.default.attributesOfItem(atPath: directory.path)
            XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: first.config.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testExistingConfigurationIsPreservedOnRelaunch() throws {
        let profile = try XCTUnwrap(store.load().profiles.first)
        let paths = try store.prepare(profile)
        let custom = "cli_auth_credentials_store = \"file\"\nmodel = \"custom\"\n"
        try Data(custom.utf8).write(to: paths.config)
        _ = try store.prepare(profile)
        XCTAssertEqual(try String(contentsOf: paths.config), custom)
    }

    func testNamesNeverBecomePathsOrShellCommandsAndRenameKeepsIdentity() throws {
        let profile = try store.create(name: "../../work; $(touch oops) '账号'")
        let paths = try store.prepare(profile)
        XCTAssertEqual(paths.root.deletingLastPathComponent(), root.appendingPathComponent("profiles", isDirectory: true))
        XCTAssertEqual(paths.root.lastPathComponent, profile.directoryName)
        XCTAssertFalse(paths.root.lastPathComponent.contains(".."))
        XCTAssertFalse(paths.root.lastPathComponent.contains("/"))
        let plan = LaunchPlan(paths: paths)
        XCTAssertEqual(plan.arguments, ["--user-data-dir=\(paths.desktop.path)"])
        XCTAssertFalse(plan.arguments.joined().contains("touch oops"))
        try store.rename(profile.id, to: "Renamed")
        let renamed = try XCTUnwrap(store.load().profiles.first(where: { $0.id == profile.id }))
        XCTAssertEqual(store.paths(for: renamed), paths)
    }

    func testInvalidAndDuplicateNamesAreRejected() throws {
        XCTAssertThrowsError(try store.create(name: "  "))
        XCTAssertThrowsError(try store.create(name: "x\ny"))
        XCTAssertThrowsError(try store.create(name: String(repeating: "x", count: 41)))
        _ = try store.create(name: "Unique")
        XCTAssertThrowsError(try store.create(name: " unique "))
    }

    func testCorruptRegistryIsNeverReplacedWithDefaults() throws {
        let file = root.appendingPathComponent("profiles.json")
        let bytes = Data("not json - preserve me".utf8)
        try bytes.write(to: file)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.create(name: "New"))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testFutureRegistrySchemaIsPreserved() throws {
        var registry = try store.load()
        registry.schemaVersion = 99
        let file = root.appendingPathComponent("profiles.json")
        let bytes = try JSONEncoder().encode(registry)
        try bytes.write(to: file)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testProfileAndConfigSymlinksCannotRedirectWrites() throws {
        let profile = try XCTUnwrap(store.load().profiles.first)
        let paths = try store.prepare(profile)
        let outside = root.appendingPathComponent("untouched.toml")
        try Data("private config".utf8).write(to: outside)
        try FileManager.default.removeItem(at: paths.config)
        try FileManager.default.createSymbolicLink(at: paths.config, withDestinationURL: outside)
        XCTAssertThrowsError(try store.prepare(profile))
        XCTAssertEqual(try String(contentsOf: outside), "private config")

        let other = try store.create(name: "Symlink test")
        try FileManager.default.createSymbolicLink(at: store.paths(for: other).root, withDestinationURL: root)
        XCTAssertThrowsError(try store.prepare(other))
    }

    func testTwoStoreInstancesDoNotLoseEachOthersChanges() throws {
        let another = ProfileStore(root: root)
        _ = try another.load()
        _ = try store.create(name: "First")
        _ = try another.create(name: "Second")
        XCTAssertEqual(try store.load().profiles.count, 4)
    }

    func testLaunchArgumentsKeepSpacesAsOneArgumentAndAllStateRootsAgree() {
        let paths = ProfilePaths(base: URL(fileURLWithPath: "/tmp/a path with spaces"), id: UUID())
        let plan = LaunchPlan(paths: paths)
        XCTAssertEqual(plan.arguments.count, 1)
        XCTAssertEqual(plan.environment["CODEX_HOME"], paths.codex.path)
        XCTAssertEqual(plan.environment["CODEX_SQLITE_HOME"], paths.codex.path)
        XCTAssertEqual(plan.environment["CODEX_ELECTRON_USER_DATA_PATH"], paths.desktop.path)
        XCTAssertNil(plan.environment["HOME"])
    }

    func testPIDReuseCannotMatchAnOldReceipt() {
        let date = Date()
        let receipt = ProcessReceipt(pid: 123, launchedAt: date, bundlePath: "/Applications/Codex.app")
        XCTAssertTrue(receipt.matches(pid: 123, launchedAt: date, bundlePath: "/Applications/Codex.app"))
        XCTAssertFalse(receipt.matches(pid: 123, launchedAt: date.addingTimeInterval(10), bundlePath: "/Applications/Codex.app"))
        XCTAssertFalse(receipt.matches(pid: 124, launchedAt: date, bundlePath: "/Applications/Codex.app"))
        XCTAssertFalse(receipt.matches(pid: 123, launchedAt: date, bundlePath: "/Applications/Other.app"))
        XCTAssertFalse(receipt.matches(pid: 123, launchedAt: nil, bundlePath: "/Applications/Codex.app"))
    }

    func testSingletonLockParsingWithHyphenatedHostnames() {
        XCTAssertEqual(SingletonLock.processID(from: "my-mac.local-4321"), 4321)
        for invalid in ["", "4321", "mac-zero", "mac-0", "mac-9999999999999"] {
            XCTAssertNil(SingletonLock.processID(from: invalid))
        }
    }

    func testCapabilityMarkerAcrossReadBoundaries() throws {
        let file = root.appendingPathComponent("fixture.asar")
        let marker = Data("CODEX_ELECTRON_USER_DATA_PATH".utf8)
        try (Data(repeating: 0x41, count: 30) + marker + Data(repeating: 0x42, count: 30)).write(to: file)
        XCTAssertTrue(try CodexInstallation.containsMarker(in: file, marker: marker, chunkSize: 16))
        XCTAssertFalse(try CodexInstallation.containsMarker(in: file, marker: Data("missing".utf8), chunkSize: 16))
        XCTAssertFalse(try CodexInstallation.containsMarker(in: file, marker: Data()))
    }

    func testWrongAppOrMissingIsolationSupportIsRejected() throws {
        let app = root.appendingPathComponent("Fixture.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let executable = contents.appendingPathComponent("MacOS/fixture")
        try Data("fixture only; never executed".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let plistURL = contents.appendingPathComponent("Info.plist")
        var plist = ["CFBundleIdentifier": "example.unrelated", "CFBundleExecutable": "fixture"]
        func writePlist() throws {
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
        }
        try writePlist()
        XCTAssertThrowsError(try CodexInstallation.inspect(app))
        plist["CFBundleIdentifier"] = CodexInstallation.bundleIdentifier
        try writePlist()
        try Data("no profile override".utf8).write(to: contents.appendingPathComponent("Resources/app.asar"))
        XCTAssertThrowsError(try CodexInstallation.inspect(app))
        try Data("CODEX_ELECTRON_USER_DATA_PATH".utf8).write(to: contents.appendingPathComponent("Resources/app.asar"))
        XCTAssertNoThrow(try CodexInstallation.inspect(app))
    }
}

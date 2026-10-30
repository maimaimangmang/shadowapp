import CodexMultiCore
import CodexMultiState
import Foundation

@MainActor
final class AppModelTests {
    private var root: URL!
    private var store: ProfileStore!

    func setUp() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("codex-multi-state-tests-\(UUID().uuidString)")
        store = ProfileStore(root: root)
        _ = try store.load()
        _ = try store.create(name: "Fixture One")
        _ = try store.create(name: "Fixture Two")
    }

    func tearDown() throws { try FileManager.default.removeItem(at: root) }

    private func model() -> AppModel {
        AppModel(store: store, automaticallyDiscover: false, refreshInterval: nil, runningInstances: { [] })
    }

    private var registryURL: URL { root.appendingPathComponent("profiles.json") }

    func testFreshInstallHasNoPretendAccounts() throws {
        let fresh = ProfileStore(root: root.appendingPathComponent("fresh"))
        XCTAssertTrue(try fresh.load().profiles.isEmpty)
        let instance = ProcessReceipt(pid: 12345, launchedAt: Date(), bundlePath: "/Applications/Codex.app")
        let model = AppModel(store: fresh, automaticallyDiscover: false, refreshInterval: nil,
                             runningInstances: { [instance] })
        XCTAssertTrue(model.profiles.isEmpty)
        XCTAssertEqual(model.existingInstances, [instance])
        XCTAssertTrue(try fresh.load().profiles.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.root.appendingPathComponent("profiles").path))
        let saved = try fresh.create(name: "Personal")
        XCTAssertEqual(try ProfileStore(root: fresh.root).load().profiles.first?.id, saved.id)
        XCTAssertEqual(try fresh.load().profiles.first?.name, "Personal")
    }

    func testExistingInstancesExcludeManagedAndHandlePIDReuse() throws {
        let date = Date()
        func receipt(_ pid: Int32, _ offset: TimeInterval = 0) -> ProcessReceipt {
            ProcessReceipt(pid: pid, launchedAt: date.addingTimeInterval(offset), bundlePath: "/Applications/Codex.app")
        }
        let profiles = try store.load().profiles
        try store.record(receipt(101), for: profiles[0].id)
        try store.record(receipt(102), for: profiles[1].id)
        let pending = try store.create(name: "Launch in progress")
        let paths = try store.prepare(pending)
        try FileManager.default.createSymbolicLink(atPath: paths.singletonLock.path, withDestinationPath: "test-host-103")
        var observed = [receipt(101), receipt(102, 10), receipt(103), receipt(104)]
        let before = try Data(contentsOf: registryURL)
        let model = AppModel(store: store, automaticallyDiscover: false, refreshInterval: nil,
                             runningInstances: { observed })
        XCTAssertEqual(model.existingInstances, [receipt(102, 10), receipt(104)])
        XCTAssertEqual(try Data(contentsOf: registryURL), before)
        try Data("broken registry".utf8).write(to: registryURL)
        observed = [receipt(104)]
        model.refresh()
        XCTAssertFalse(model.registryAvailable)
        XCTAssertEqual(model.existingInstances, [receipt(104)])
        observed = []
        model.refresh()
        XCTAssertTrue(model.existingInstances.isEmpty)
    }

    func testFocusRejectsAnExpiredInstance() throws {
        let model = model()
        let before = try Data(contentsOf: registryURL)
        model.focusExistingInstance(ProcessReceipt(pid: Int32.max, launchedAt: Date(), bundlePath: "/Applications/Codex.app"))
        XCTAssertTrue(model.error != nil)
        XCTAssertEqual(try Data(contentsOf: registryURL), before)
    }

    func testRegistryCanRecoverWithoutRestart() throws {
        let model = model()
        let original = try Data(contentsOf: registryURL)
        let profile = try XCTUnwrap(model.profiles.first)
        let invalid = Data("invalid registry fixture; preserve me".utf8)
        try invalid.write(to: registryURL)
        model.refresh()
        XCTAssertFalse(model.registryAvailable)
        XCTAssertTrue(model.registryError != nil)
        XCTAssertEqual(model.status(profile), .unavailable)
        XCTAssertNil(model.error)

        // Repeated timer refreshes must neither replace the file nor create modal errors.
        model.refresh()
        model.retryRegistry()
        XCTAssertEqual(try Data(contentsOf: registryURL), invalid)
        XCTAssertNil(model.error)
        try original.write(to: registryURL)
        model.retryRegistry()
        XCTAssertTrue(model.registryAvailable)
        XCTAssertNil(model.registryError)
        XCTAssertEqual(model.status(profile), .stopped)
        XCTAssertEqual(model.profiles.count, 2)
        try model.create(name: "Created after recovery")
        try model.rename(profile, to: "Renamed after recovery")
        XCTAssertEqual(model.profiles.count, 3)
        XCTAssertEqual(model.profiles.first(where: { $0.id == profile.id })?.name, "Renamed after recovery")
    }

    func testRegistryInvalidAtStartupCanRecover() throws {
        let original = try Data(contentsOf: registryURL)
        try Data("broken before startup".utf8).write(to: registryURL)
        let model = model()
        XCTAssertFalse(model.registryAvailable)
        XCTAssertFalse(model.isChecking)
        XCTAssertTrue(model.profiles.isEmpty)
        try original.write(to: registryURL)
        model.retryRegistry()
        XCTAssertTrue(model.registryAvailable)
        XCTAssertEqual(model.profiles.count, 2)
    }

    func testRegistryFailureBlocksAccountOperations() throws {
        let model = model()
        let profile = try XCTUnwrap(model.profiles.first)
        let invalid = Data("corrupt registry".utf8)
        try invalid.write(to: registryURL)
        model.refresh()
        XCTAssertThrowsError(try model.create(name: "Should not be created"))
        XCTAssertThrowsError(try model.rename(profile, to: "Should not be renamed"))
        // Both methods must return before showing a confirmation or opening an app.
        model.launch(profile)
        model.trash(profile)
        model.requestQuit(profile)
        XCTAssertEqual(try Data(contentsOf: registryURL), invalid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.paths(for: profile).root.path))
    }

    func testMissingRegistryIsNotRecreatedDuringRefresh() throws {
        let model = model()
        let original = try Data(contentsOf: registryURL)
        try FileManager.default.removeItem(at: registryURL)
        model.refresh()
        model.retryRegistry()
        XCTAssertFalse(model.registryAvailable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: registryURL.path))
        try original.write(to: registryURL)
        model.retryRegistry()
        XCTAssertTrue(model.registryAvailable)
    }

    func testRemovedProfileCannotLaunchFromStaleUI() throws {
        let model = model()
        let stale = try XCTUnwrap(model.profiles.first)
        // This unused profile has no folder, so removing it does not use the system Trash.
        try store.moveToTrash(stale.id)
        model.launch(stale)
        XCTAssertTrue(model.error != nil)
        XCTAssertFalse(model.profiles.contains(where: { $0.id == stale.id }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.paths(for: stale).root.path))
    }

    func testDetectionReportsMissingAndUnsupportedApps() async throws {
        let model = model()
        let missing = root.appendingPathComponent("Missing.app")
        await model.checkApplications([missing]).value
        let missingMessage = try XCTUnwrap(model.installationIssue)
        XCTAssertFalse(model.isChecking)
        XCTAssertNil(model.installation)
        XCTAssertNil(model.error)

        let unsupported = try applicationFixture(supported: false)
        await model.checkApplications([missing, unsupported]).value
        let unsupportedMessage = try XCTUnwrap(model.installationIssue)
        XCTAssertNotEqual(missingMessage, unsupportedMessage)
        XCTAssertNil(model.installation)
        XCTAssertNil(model.error)
    }

    func testRecheckClearsFailureAndRejectsStaleInstallation() async throws {
        let model = model()
        let app = try applicationFixture(supported: true)
        let unsupported = try applicationFixture(supported: false)
        let missing = root.appendingPathComponent("Missing.app")
        let firstCheck = model.checkApplications([missing])
        let latestCheck = model.checkApplications([unsupported, app])
        await firstCheck.value
        await latestCheck.value
        XCTAssertEqual(model.installation?.url.path, app.path)
        XCTAssertNil(model.installationIssue)
        XCTAssertEqual(try store.load().applicationPath, app.path)

        try Data("support marker removed by a simulated update".utf8)
            .write(to: app.appendingPathComponent("Contents/Resources/app.asar"))
        await model.checkApplications([app]).value
        XCTAssertNil(model.installation)
        XCTAssertTrue(model.installationIssue != nil)
        XCTAssertFalse(model.isChecking)
    }

    private func applicationFixture(supported: Bool) throws -> URL {
        let app = root.appendingPathComponent(supported ? "Compatible.app" : "Unsupported.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let executable = contents.appendingPathComponent("MacOS/fixture")
        try Data("fixture only; never executed".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let plist = ["CFBundleIdentifier": CodexInstallation.bundleIdentifier,
                     "CFBundleExecutable": "fixture", "CFBundleShortVersionString": "test-only"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data((supported ? "CODEX_ELECTRON_USER_DATA_PATH" : "unsupported fixture").utf8)
            .write(to: contents.appendingPathComponent("Resources/app.asar"))
        return app
    }
}

@MainActor
func runAppModelTests() async -> Int {
    let suite = AppModelTests()
    let tests: [(String, () async throws -> Void)] = [
        ("fresh installs do not create pretend accounts or import running instances", { try suite.testFreshInstallHasNoPretendAccounts() }),
        ("existing instance list excludes managed launches and handles PID reuse", { try suite.testExistingInstancesExcludeManagedAndHandlePIDReuse() }),
        ("focus rejects an expired instance without changing profile data", { try suite.testFocusRejectsAnExpiredInstance() }),
        ("recover profile registry without restarting", { try suite.testRegistryCanRecoverWithoutRestart() }),
        ("recover registry broken before startup", { try suite.testRegistryInvalidAtStartupCanRecover() }),
        ("block account operations while registry is unavailable", { try suite.testRegistryFailureBlocksAccountOperations() }),
        ("do not recreate missing registry during refresh", { try suite.testMissingRegistryIsNotRecreatedDuringRefresh() }),
        ("removed profiles cannot launch from a stale UI", { try suite.testRemovedProfileCannotLaunchFromStaleUI() }),
        ("show distinct missing and incompatible app diagnostics", suite.testDetectionReportsMissingAndUnsupportedApps),
        ("recheck clears errors and invalidates stale installation", suite.testRecheckClearsFailureAndRejectsStaleInstallation)
    ]
    for (name, test) in tests {
        let before = failures
        do { try suite.setUp(); try await test() }
        catch { failures += 1; print("FAIL \(name): \(error)") }
        do { try suite.tearDown() }
        catch { failures += 1; print("FAIL cleanup: \(error)") }
        if failures == before { print("PASS \(name)") }
    }
    return tests.count
}

import Foundation
import CodexMultiCore

func runStorageOperationTests() -> Int {
    let fm = FileManager.default
    func fixture(_ body: (URL, ProfileStore) throws -> Void) throws {
        let root = fm.temporaryDirectory.appendingPathComponent("storage-audit-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let store = ProfileStore(root: root)
        _ = try store.load()
        try body(root, store)
    }
    let tests: [(String, () throws -> Void)] = [
        ("folder reveal permits repair without rewriting broken config or instructions", {
            try fixture { _, store in
                let provider = APIProvider(name: "Fixture", baseURL: "https://example.invalid/v1", modelID: "fixture")
                let profile = try store.create(name: "Repair", provider: provider, apiKey: "fixture-only")
                let paths = store.paths(for: profile)
                try fm.removeItem(at: paths.auth)
                let config = Data("broken configuration to repair".utf8)
                let guidance = Data("<!-- BEGIN CODEX MULTI PROFILE CONTEXT -->".utf8)
                try config.write(to: paths.config)
                let agents = paths.codex.appendingPathComponent("AGENTS.md")
                try guidance.write(to: agents)
                XCTAssertEqual(try store.folderURL(for: profile), paths.root)
                XCTAssertFalse(fm.fileExists(atPath: paths.auth.path))
                XCTAssertEqual(try Data(contentsOf: paths.config), config)
                XCTAssertEqual(try Data(contentsOf: agents), guidance)
            }
        }),
        ("folder reveal for an unused profile creates no auth or config", {
            try fixture { _, store in
                let profile = try store.create(name: "Unused")
                let folder = try store.folderURL(for: profile)
                XCTAssertEqual(try fm.contentsOfDirectory(atPath: folder.path), [])
            }
        }),
        ("stale profile paths cannot redirect preparation or folder reveal", {
            try fixture { _, store in
                let profile = try store.create(name: "Current")
                var stale = profile
                stale.directoryName = "stale-" + profile.id.uuidString.prefix(8).lowercased()
                let expected = store.paths(for: profile)
                XCTAssertEqual(try store.prepare(stale), expected)
                try store.prepareGuidance(for: stale)
                XCTAssertEqual(try store.folderURL(for: stale), expected.root)
                XCTAssertFalse(fm.fileExists(atPath: store.paths(for: stale).root.path))
                XCTAssertThrowsError(try store.folderURL(for: Profile(name: "Removed")))
            }
        }),
        ("trash rejects live locks and receipts before invoking filesystem action", {
            try fixture { root, store in
                let profile = try store.create(name: "Live")
                let paths = try store.prepare(profile)
                var invoked = false
                let checked = ProfileStore(root: root, trashItem: { url in invoked = true; return url })
                try fm.createSymbolicLink(atPath: paths.singletonLock.path, withDestinationPath: "fixture-host-\(ProcessInfo.processInfo.processIdentifier)")
                XCTAssertThrowsError(try checked.moveToTrash(profile.id))
                try fm.removeItem(at: paths.singletonLock)
                try store.record(ProcessReceipt(pid: ProcessInfo.processInfo.processIdentifier, launchedAt: Date(), bundlePath: "/fixture.app"), for: profile.id)
                XCTAssertThrowsError(try checked.moveToTrash(profile.id))
                XCTAssertFalse(invoked)
                XCTAssertTrue(fm.fileExists(atPath: paths.root.path))
                XCTAssertEqual(try store.load().profiles.count, 1)
            }
        }),
        ("trash save failure restores the original folder and preserves data", {
            try fixture { root, store in
                let profile = try store.create(name: "Rollback")
                let paths = try store.prepare(profile)
                let data = try Data(contentsOf: paths.config)
                let registry = root.appendingPathComponent("profiles.json")
                let backup = root.appendingPathComponent("registry-backup")
                let trash = root.appendingPathComponent("simulated-trash")
                let checked = ProfileStore(root: root, trashItem: { url in
                    try fm.moveItem(at: url, to: trash)
                    // Deterministically force registry saving to fail after the move.
                    try fm.moveItem(at: registry, to: backup)
                    try fm.createSymbolicLink(at: registry, withDestinationURL: backup)
                    return trash
                })
                XCTAssertThrowsError(try checked.moveToTrash(profile.id))
                XCTAssertEqual(try Data(contentsOf: paths.config), data)
                XCTAssertFalse(fm.fileExists(atPath: trash.path))
                try fm.removeItem(at: registry)
                try fm.moveItem(at: backup, to: registry)
                XCTAssertEqual(try store.load().profiles.first?.id, profile.id)
            }
        }),
        ("successful trash changes only the selected profile", {
            try fixture { root, store in
                let selected = try store.create(name: "Selected")
                let other = try store.create(name: "Other")
                let paths = try store.prepare(selected)
                let otherPaths = try store.prepare(other)
                let otherConfig = try Data(contentsOf: otherPaths.config)
                let trash = root.appendingPathComponent("simulated-trash")
                let checked = ProfileStore(root: root, trashItem: { url in try fm.moveItem(at: url, to: trash); return trash })
                try checked.moveToTrash(selected.id)
                XCTAssertEqual(try store.load().profiles.map(\.id), [other.id])
                XCTAssertEqual(try Data(contentsOf: otherPaths.config), otherConfig)
                XCTAssertFalse(fm.fileExists(atPath: paths.root.path))
                XCTAssertTrue(fm.fileExists(atPath: trash.appendingPathComponent("codex/config.toml").path))
            }
        }),
        ("folder reveal rejects profile symlinks", {
            try fixture { root, store in
                let profile = try store.create(name: "Symlink")
                let outside = root.appendingPathComponent("outside")
                try fm.createDirectory(at: outside, withIntermediateDirectories: false)
                try fm.createDirectory(at: root.appendingPathComponent("profiles"), withIntermediateDirectories: false)
                try fm.createSymbolicLink(at: store.paths(for: profile).root, withDestinationURL: outside)
                XCTAssertThrowsError(try store.folderURL(for: profile))
                XCTAssertEqual(try fm.contentsOfDirectory(atPath: outside.path), [])
            }
        })
    ]
    for (name, test) in tests {
        let before = failures
        do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }
        if before == failures { print("PASS \(name)") }
    }
    return tests.count
}

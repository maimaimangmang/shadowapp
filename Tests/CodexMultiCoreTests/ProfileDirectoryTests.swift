import Foundation
import CodexMultiCore

func runProfileDirectoryTests() -> Int {
    let tests: [(String, () throws -> Void)] = [
        ("new names are readable, unique and stable on rename", {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = ProfileStore(root: root)
            _ = try store.load()
            let first = try store.create(name: "胜算云")
            XCTAssertTrue(store.paths(for: first).root.lastPathComponent.hasPrefix("胜算云-"))
            let original = try store.prepare(first)
            try store.rename(first.id, to: "工作")
            let renamed = try XCTUnwrap(store.load().profiles.first)
            XCTAssertEqual(store.paths(for: renamed), original)
            let second = try store.create(name: "胜算云")
            XCTAssertNotEqual(store.paths(for: second), original)
            XCTAssertEqual(try store.load().schemaVersion, 2)
        }),
        ("legacy registry keeps existing paths when new profiles are added", {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = ProfileStore(root: root)
            var registry = try store.load()
            registry.schemaVersion = 1
            let old = Profile(name: "Old")
            registry.profiles = [old]
            try JSONEncoder().encode(registry).write(to: root.appendingPathComponent("profiles.json"))
            let before = try store.prepare(old)
            XCTAssertEqual(before.root.lastPathComponent, old.id.uuidString.lowercased())
            _ = try store.create(name: "New")
            let loaded = try XCTUnwrap(store.load().profiles.first(where: { $0.id == old.id }))
            XCTAssertEqual(store.paths(for: loaded), before)
            XCTAssertNil(loaded.directoryName)
        }),
        ("unsafe stored directory names are rejected without rewriting registry", {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = ProfileStore(root: root)
            var registry = try store.load()
            var bad = Profile(name: "Bad")
            let file = root.appendingPathComponent("profiles.json")
            for name in ["../outside", "/tmp/other", "wrong-12345678", "nested/path-" + bad.id.uuidString.prefix(8).lowercased()] {
                bad.directoryName = name
                registry.profiles = [bad]
                let bytes = try JSONEncoder().encode(registry)
                try bytes.write(to: file)
                XCTAssertThrowsError(try store.load())
                XCTAssertEqual(try Data(contentsOf: file), bytes)
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

import Foundation
import CodexMultiCore

func runOperationLeaseTests() -> Int {
    let tests: [(String, () throws -> Void)] = [
        ("launch lease blocks another launcher start edit and trash of the same profile", {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = ProfileStore(root: root)
            let other = ProfileStore(root: root)
            _ = try store.load()
            let provider = APIProvider(name: "Fixture", baseURL: "https://example.invalid/v1", modelID: "fixture")
            let first = try store.create(name: "One", provider: provider, apiKey: "fixture-key")
            let second = try store.create(name: "Two")
            let lease = try store.beginLaunch(first.id)
            XCTAssertThrowsError(try other.beginLaunch(first.id))
            XCTAssertThrowsError(try other.updateProvider(first.id, provider: provider, newAPIKey: "new-fixture"))
            XCTAssertThrowsError(try other.moveToTrash(first.id))
            let independent = try other.beginLaunch(second.id)
            independent.release()
            lease.release()
            lease.release()
            let again = try other.beginLaunch(first.id)
            again.release()
            XCTAssertNoThrow(try other.updateProvider(first.id, provider: provider, newAPIKey: nil))
            XCTAssertEqual(try store.load().profiles.count, 2)
        }),
        ("failed launch preparation and released objects do not strand operation locks", {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = ProfileStore(root: root)
            _ = try store.load()
            let missing = UUID()
            XCTAssertThrowsError(try store.beginLaunch(missing))
            XCTAssertThrowsError(try store.beginLaunch(missing))
            let profile = try store.create(name: "Releasable")
            func scope() throws { let lease = try store.beginLaunch(profile.id); withExtendedLifetime(lease) {} }
            try scope()
            let next = try store.beginLaunch(profile.id)
            next.release()
        }),
        ("operation locks reject symlink redirection", {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = ProfileStore(root: root)
            _ = try store.load()
            let profile = try store.create(name: "Symlink")
            let outside = root.appendingPathComponent("outside")
            try Data("preserve".utf8).write(to: outside)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".operations"), withDestinationURL: outside)
            XCTAssertThrowsError(try store.beginLaunch(profile.id))
            XCTAssertEqual(try String(contentsOf: outside), "preserve")
        })
    ]
    for (name, test) in tests {
        let before = failures
        do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }
        if before == failures { print("PASS \(name)") }
    }
    return tests.count
}

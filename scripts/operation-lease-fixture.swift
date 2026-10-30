import Darwin
import Foundation
import CodexMultiCore

let mode = CommandLine.arguments[1]
let store = ProfileStore(root: URL(fileURLWithPath: CommandLine.arguments[2]), trashItem: { _ in fatalError("Trash must never run in this fixture") })
if mode == "create" {
    _ = try store.load()
    let profile = try store.create(name: "Fixture", provider: APIProvider(name: "Fixture", baseURL: "https://example.invalid/v1", modelID: "fixture"), apiKey: "fixture-only")
    print(profile.id.uuidString)
} else {
    let id = UUID(uuidString: CommandLine.arguments[3])!
    if mode == "hold" {
        let lease = try store.beginLaunch(id)
        print("READY"); fflush(stdout)
        withExtendedLifetime(lease) { RunLoop.current.run() }
    } else if mode == "probe" {
        do { let lease = try store.beginLaunch(id); lease.release(); print("AVAILABLE") }
        catch { print("BUSY") }
    } else if mode == "mutate" {
        do { try store.moveToTrash(id); fatalError("Trash must be blocked") }
        catch { }
        do {
            try store.updateProvider(id, provider: APIProvider(name: "Fixture", baseURL: "https://example.invalid/v1", modelID: "changed"), newAPIKey: nil)
            fatalError("Edit must be blocked")
        } catch { }
        print("BLOCKED")
    }
}

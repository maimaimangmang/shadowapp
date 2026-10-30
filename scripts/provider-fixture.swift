import Foundation
import CodexMultiCore

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let store = ProfileStore(root: root)
_ = try store.load()
let provider = APIProvider(name: "Fixture provider", baseURL: CommandLine.arguments[2], modelID: "fixture/model-id")
let profile: Profile
if CommandLine.arguments.last == "update" {
    profile = try store.load().profiles[0]
    var updated = provider
    updated.modelID = "fixture/updated-model"
    try store.updateProvider(profile.id, provider: updated, newAPIKey: nil)
} else {
    profile = try store.create(name: "API fixture", provider: provider, apiKey: "fixture-key-for-localhost-only")
}
print(store.paths(for: profile).codex.path)

import Foundation
import CodexMultiCore

@main struct ConnectionProbeFixture {
    static func main() async throws {
        let provider = APIProvider(name: "Local fixture", baseURL: CommandLine.arguments[1], modelID: "fixture/model-id")
        let expected = CommandLine.arguments[2]
        let task = Task { try await ProviderConnectionProbe.check(provider: provider, key: "fixture-key-for-localhost-only") }
        if expected == "cancelled" {
            try await Task.sleep(nanoseconds: 200_000_000)
            task.cancel()
        }
        var outcome: String
        do {
            let result = try await task.value
            outcome = result == .completed ? "completed" : "limited"
        } catch is CancellationError { outcome = "cancelled" }
        catch { outcome = "error" }
        guard outcome == expected else { fatalError("Unexpected probe outcome: \(outcome)") }
        print("PASS \(expected)")
    }
}

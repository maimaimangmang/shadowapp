import Foundation
import CodexMultiCore

func runSessionModelEvidenceTests() -> Int {
    let tests: [(String, () throws -> Void)] = [
        ("session metadata ignores model claims and separates profiles", {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: base) }
            let paths = ProfilePaths(base: base, id: UUID())
            let other = ProfilePaths(base: base, id: UUID())
            let sessions = paths.codex.appendingPathComponent("sessions")
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            let content = """
            {"type":"session_meta","payload":{"id":"session-one","model_provider":"codex_multi"}}
            {"type":"turn_context","timestamp":"2026-10-29T02:10:34Z","payload":{"model":"bigmodel/glm-5.3"}}
            {"type":"response_item","payload":{"type":"message","role":"assistant","model":"gpt-5.1-codex","content":"I checked metadata: OpenAI."}}
            """
            try Data(content.utf8).write(to: sessions.appendingPathComponent("one.jsonl"))
            let value = try XCTUnwrap(SessionModelEvidence.latest(in: paths))
            XCTAssertEqual(value.model, "bigmodel/glm-5.3")
            XCTAssertEqual(value.provider, "codex_multi")
            XCTAssertEqual(value.sessionID, "session-one")
            XCTAssertNil(try SessionModelEvidence.latest(in: other))
        }),
        ("latest turn wins and missing new metadata cannot reuse old model", {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: base) }
            let paths = ProfilePaths(base: base, id: UUID())
            let sessions = paths.codex.appendingPathComponent("sessions")
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            let file = sessions.appendingPathComponent("one.jsonl")
            var text = """
            {"type":"session_meta","payload":{"id":"one","model_provider":"codex_multi"}}
            {"type":"turn_context","payload":{"model":"old"}}
            {"type":"turn_context","payload":{"model":"new"}}
            """
            try Data(text.utf8).write(to: file)
            XCTAssertEqual(try SessionModelEvidence.latest(in: paths)?.model, "new")
            text += "\n{\"type\":\"turn_context\",\"payload\":{}}\n"
            try Data(text.utf8).write(to: file)
            XCTAssertThrowsError(try SessionModelEvidence.latest(in: paths))
        }),
        ("session evidence refuses redirected account directories", {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: base) }
            let paths = ProfilePaths(base: base, id: UUID())
            let outside = base.appendingPathComponent("outside")
            try FileManager.default.createDirectory(at: paths.codex, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: paths.codex.appendingPathComponent("sessions"), withDestinationURL: outside)
            XCTAssertThrowsError(try SessionModelEvidence.latest(in: paths))
        })
    ]
    for (name, test) in tests {
        let before = failures
        do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }
        if before == failures { print("PASS \(name)") }
    }
    return tests.count
}

// A tiny assertion runner keeps tests usable with Apple's Command Line Tools alone.
// XCTest is not bundled with all Command Line Tools installations.
import Foundation

var failures = 0
struct AssertionFailure: Error {}

func fail(_ message: String, _ file: StaticString, _ line: UInt) {
    failures += 1
    print("FAIL \(file):\(line): \(message)")
}

func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { fail("Expected true", file, line) } }
    catch { fail("Unexpected error: \(error)", file, line) }
}

func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() { fail("Expected false", file, line) } }
    catch { fail("Unexpected error: \(error)", file, line) }
}

func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T,
                                  file: StaticString = #filePath, line: UInt = #line) {
    do { if try lhs() != rhs() { fail("Values are not equal", file, line) } }
    catch { fail("Unexpected error: \(error)", file, line) }
}

func XCTAssertNotEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    if lhs == rhs { fail("Values must differ", file, line) }
}

func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil { fail("Expected nil", file, line) }
}

func XCTUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value else { fail("Expected a value", file, line); throw AssertionFailure() }
    return value
}

func XCTAssertThrowsError<T>(_ body: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try body(); fail("Expected an error", file, line) } catch { }
}

func XCTAssertNoThrow<T>(_ body: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try body() } catch { fail("Unexpected error: \(error)", file, line) }
}

let suite = ProfileIsolationTests()
let tests: [(String, () throws -> Void)] = [
    ("separate account directories and private permissions", suite.testTwoProfilesDoNotShareAuthHistoryOrDesktopDirectories),
    ("preserve existing configuration", suite.testExistingConfigurationIsPreservedOnRelaunch),
    ("names cannot become paths or shell commands", suite.testNamesNeverBecomePathsOrShellCommandsAndRenameKeepsIdentity),
    ("reject invalid and duplicate names", suite.testInvalidAndDuplicateNamesAreRejected),
    ("preserve corrupt registry", suite.testCorruptRegistryIsNeverReplacedWithDefaults),
    ("preserve future schema", suite.testFutureRegistrySchemaIsPreserved),
    ("reject symlinks redirecting writes", suite.testProfileAndConfigSymlinksCannotRedirectWrites),
    ("preserve changes across store instances", suite.testTwoStoreInstancesDoNotLoseEachOthersChanges),
    ("launch paths with spaces", suite.testLaunchArgumentsKeepSpacesAsOneArgumentAndAllStateRootsAgree),
    ("PID reuse cannot match old instance", suite.testPIDReuseCannotMatchAnOldReceipt),
    ("hyphenated hostname in lock", suite.testSingletonLockParsingWithHyphenatedHostnames),
    ("capability marker at read boundary", suite.testCapabilityMarkerAcrossReadBoundaries),
    ("reject unrelated or incompatible applications", suite.testWrongAppOrMissingIsolationSupportIsRejected)
]
for (name, test) in tests {
    let before = failures
    do { try suite.setUpWithError(); try test() }
    catch { failures += 1; print("FAIL \(name): \(error)") }
    do { try suite.tearDownWithError() }
    catch { failures += 1; print("FAIL cleanup: \(error)") }
    if failures == before { print("PASS \(name)") }
}
print("\(tests.count) tests; \(failures) failures")
exit(failures == 0 ? 0 : 1)

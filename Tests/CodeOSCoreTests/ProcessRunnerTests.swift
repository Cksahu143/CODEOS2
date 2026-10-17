import XCTest
@testable import CodeOSCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesStandardOutput() throws {
        let result = try ProcessRunner.run(executable: "/bin/echo", arguments: ["hello"])
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .newlines), "hello")
    }

    func testArgumentsAreNeverInterpretedAsShell() throws {
        let result = try ProcessRunner.run(executable: "/bin/echo", arguments: ["a; echo injected"])
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .newlines), "a; echo injected")
    }

    func testNonZeroExitIsReported() throws {
        let result = try ProcessRunner.run(executable: "/usr/bin/false", arguments: [])
        XCTAssertFalse(result.succeeded)
        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testTimeoutTerminatesProcess() throws {
        let result = try ProcessRunner.run(executable: "/bin/sleep", arguments: ["5"], timeout: 0.5)
        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.succeeded)
    }

    func testMissingExecutableThrows() {
        XCTAssertThrowsError(try ProcessRunner.run(executable: "/nonexistent/tool", arguments: [])) { error in
            XCTAssertEqual(error as? ProcessRunError, .executableNotFound("/nonexistent/tool"))
        }
    }
}

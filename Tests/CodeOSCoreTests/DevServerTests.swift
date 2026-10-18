import XCTest
@testable import CodeOSCore

final class DevServerTests: XCTestCase {
    func testFindsLocalURLInDevServerOutput() {
        let output = "  VITE v5.0.0  ready in 310 ms\n\n  ➜  Local:   http://localhost:5173/\n  ➜  Network: use --host"
        XCTAssertEqual(DevServerParser.url(in: output)?.absoluteString, "http://localhost:5173/")
    }

    func testAllInterfacesAddressBecomesLocalhost() {
        XCTAssertEqual(DevServerParser.url(in: "serving at http://0.0.0.0:8080")?.absoluteString, "http://localhost:8080")
    }

    func testNoURLMeansNil() {
        XCTAssertNil(DevServerParser.url(in: "compiling assets..."))
    }

    func testRecognizesPortInUse() {
        XCTAssertTrue(DevServerParser.looksLikePortInUse("Error: listen EADDRINUSE: address already in use :::5173"))
        XCTAssertFalse(DevServerParser.looksLikePortInUse("ready in 310 ms"))
    }

    func testParsesProcessTable() {
        let table = DevServerProcess.parsePidTable("  100     1\n  101   100\n")
        XCTAssertEqual(table.count, 2)
        XCTAssertEqual(table[1].pid, 101)
        XCTAssertEqual(table[1].ppid, 100)
    }

    func testFindsEveryDescendantButNotUnrelatedProcesses() {
        let table: [(pid: Int32, ppid: Int32)] = [(100, 1), (101, 100), (102, 101), (200, 1)]
        XCTAssertEqual(DevServerProcess.descendants(of: 100, table: table), [101, 102])
        XCTAssertEqual(DevServerProcess.descendants(of: 200, table: table), [])
    }

    func testStoppedServerHasNoURLAndIsNotRunning() {
        let server = DevServerProcess()
        XCTAssertFalse(server.isRunning)
        XCTAssertNil(server.url)
    }
}

import XCTest
@testable import CodeOSCore

final class ProcessMonitorTests: XCTestCase {
    func testParsesAndRanksByCPU() {
        let output = """
          101   2.5   2048 /Applications/Safari.app/Contents/MacOS/Safari
          202  40.0  10240 /usr/bin/swift-frontend
          303   0.0    512 /sbin/launchd
        """
        let samples = ProcessMonitor.parse(output)
        XCTAssertEqual(samples.map(\.pid), [202, 101, 303])
        XCTAssertEqual(samples[0].residentBytes, 10240 * 1024)
        XCTAssertEqual(samples[1].name, "Safari")
    }

    func testCommandNamesWithSpacesAreKept() {
        let samples = ProcessMonitor.parse("  7 1.0 100 /Applications/My App.app/Contents/MacOS/My App\n")
        XCTAssertEqual(samples.first?.name, "My App")
    }

    func testRespectsLimit() {
        let output = (1...30).map { "\($0) 1.0 100 /bin/x\($0)" }.joined(separator: "\n")
        XCTAssertEqual(ProcessMonitor.parse(output, limit: 5).count, 5)
    }

    func testLiveSampleReturnsProcesses() throws {
        let samples = try ProcessMonitor.sample(limit: 5)
        XCTAssertFalse(samples.isEmpty)
    }
}

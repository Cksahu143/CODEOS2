import XCTest
@testable import CodeOSCore

final class MemoryMonitorTests: XCTestCase {
    func testLiveBreakdownIsConsistent() throws {
        guard let breakdown = MemoryMonitor.breakdown() else {
            throw XCTSkip("Mach host statistics are unavailable in this environment.")
        }
        XCTAssertGreaterThan(breakdown.totalBytes, 0)
        XCTAssertLessThanOrEqual(breakdown.usedBytes, breakdown.totalBytes)
        XCTAssertGreaterThanOrEqual(breakdown.usageFraction, 0)
        XCTAssertLessThanOrEqual(breakdown.usageFraction, 1)
    }

    func testUsageFractionHandlesZeroTotal() {
        let empty = MemoryBreakdown(totalBytes: 0, freeBytes: 0, activeBytes: 5, inactiveBytes: 0, wiredBytes: 0, compressedBytes: 0)
        XCTAssertEqual(empty.usageFraction, 0)
    }
}

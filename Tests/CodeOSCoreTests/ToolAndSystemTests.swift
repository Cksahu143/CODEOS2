import XCTest
@testable import CodeOSCore

final class ToolAndSystemTests: XCTestCase {
    func testLocatesExecutableInGivenDirectory() {
        XCTAssertEqual(ToolDetector.locate("sh", in: ["/bin"]), "/bin/sh")
        XCTAssertNil(ToolDetector.locate("definitely-not-a-tool-xyz", in: ["/bin"]))
    }

    func testStatusForMissingToolIsNotInstalled() {
        let status = ToolDetector.status(for: "definitely-not-a-tool-xyz")
        XCTAssertFalse(status.isInstalled)
        XCTAssertNil(status.version)
    }

    func testSystemSnapshotHasRealValues() {
        let snapshot = SystemInfo.snapshot()
        XCTAssertFalse(snapshot.osVersion.isEmpty)
        XCTAssertGreaterThan(snapshot.physicalMemoryBytes, 0)
        XCTAssertNotNil(snapshot.volumeTotalBytes)
        XCTAssertFalse(snapshot.appArchitecture.isEmpty)
    }
}

import XCTest
@testable import CodeOSCore

final class PortScannerTests: XCTestCase {
    func testParsesListeningSockets() {
        let output = """
        p812
        cnode
        n*:3000
        p640
        cpostgres
        n127.0.0.1:5432
        n[::1]:5432
        """
        let ports = PortScanner.parse(output)
        XCTAssertEqual(ports.map(\.port), [3000, 5432, 5432])
        XCTAssertEqual(ports[0].processName, "node")
        XCTAssertEqual(ports[0].address, "*")
        XCTAssertEqual(ports[1].address, "127.0.0.1")
        XCTAssertEqual(ports[2].address, "[::1]")
    }

    func testEmptyOutputMeansNoPorts() {
        XCTAssertTrue(PortScanner.parse("").isEmpty)
    }
}

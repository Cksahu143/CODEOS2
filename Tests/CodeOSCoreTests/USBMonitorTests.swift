import XCTest
@testable import CodeOSCore

final class USBMonitorTests: XCTestCase {
    private let sample = """
    {"SPUSBDataType":[{"_name":"USB31Bus","_items":[
        {"_name":"USB3.0 Hub","manufacturer":"Acme","_items":[
            {"_name":"Keyboard","serial_num":"123","device_speed":"full_speed"}
        ]}
    ]}]}
    """

    func testWalksTheTreeWithDepths() {
        let devices = USBMonitor.parse(Data(sample.utf8))
        XCTAssertEqual(devices.map(\.name), ["USB31Bus", "USB3.0 Hub", "Keyboard"])
        XCTAssertEqual(devices.map(\.depth), [0, 1, 2])
    }

    func testReadsSerialSpeedAndHubFlag() {
        let devices = USBMonitor.parse(Data(sample.utf8))
        XCTAssertEqual(devices[1].manufacturer, "Acme")
        XCTAssertTrue(devices[1].isHub)
        XCTAssertEqual(devices[2].serial, "123")
        XCTAssertEqual(devices[2].speed, "full_speed")
        XCTAssertFalse(devices[2].isHub)
    }

    func testGarbageGivesNoDevices() {
        XCTAssertTrue(USBMonitor.parse(Data("nope".utf8)).isEmpty)
    }
}

import XCTest
@testable import CodeOSCore

final class SMCDecodeTests: XCTestCase {
    func testSignedFixedPointTemperature() {
        XCTAssertEqual(SMC.decode(type: "sp78", bytes: [0x2C, 0x80]), 44.5)
    }

    func testUnsignedFixedPointFanSpeed() {
        XCTAssertEqual(SMC.decode(type: "fpe2", bytes: [0x12, 0xC0]), 1200)
    }

    func testFloatValue() {
        XCTAssertEqual(SMC.decode(type: "flt ", bytes: [0x00, 0x00, 0x80, 0x3F]), 1.0)
    }

    func testUnsignedByteCount() {
        XCTAssertEqual(SMC.decode(type: "ui8 ", bytes: [2]), 2)
    }

    func testUnknownTypeAndShortDataAreNil() {
        XCTAssertNil(SMC.decode(type: "xxxx", bytes: [1, 2, 3, 4]))
        XCTAssertNil(SMC.decode(type: "sp78", bytes: [0x2C]))
    }

    func testFourCCRoundTrip() {
        XCTAssertEqual(SMC.fourCCString(SMC.fourCC("flt ")), "flt ")
        XCTAssertEqual(SMC.fourCCString(SMC.fourCC("TC0P")), "TC0P")
    }
}

import XCTest
@testable import CodeOSCore

final class PowerModeParserTests: XCTestCase {
    func testReadsOnAndOff() {
        XCTAssertEqual(PowerModeParser.lowPowerMode(fromPmsetOutput: "Battery Power:\n lowpowermode         1\n"), true)
        XCTAssertEqual(PowerModeParser.lowPowerMode(fromPmsetOutput: " lowpowermode 0\n"), false)
    }

    func testMissingLineIsNil() {
        XCTAssertNil(PowerModeParser.lowPowerMode(fromPmsetOutput: " sleep 10\n"))
    }
}

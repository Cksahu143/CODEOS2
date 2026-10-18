import XCTest
@testable import CodeOSCore

final class MacTweaksTests: XCTestCase {
    private func tweak(_ key: String) -> Tweak {
        MacTweaks.catalog.first { $0.key == key }!
    }

    func testBooleanWriteUsesTypedArgument() throws {
        let command = try MacTweaks.writeCommand(tweak("AppleShowAllFiles"), value: "true")
        XCTAssertEqual(command.arguments, ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", "true"])
    }

    func testBooleanRejectsOtherText() {
        XCTAssertThrowsError(try MacTweaks.writeCommand(tweak("autohide"), value: "yes; rm -rf ~"))
    }

    func testNumberMustBeInRange() {
        XCTAssertThrowsError(try MacTweaks.writeCommand(tweak("tilesize"), value: "400"))
        XCTAssertThrowsError(try MacTweaks.writeCommand(tweak("tilesize"), value: "abc"))
        XCTAssertNoThrow(try MacTweaks.writeCommand(tweak("tilesize"), value: "48"))
    }

    func testPathMustBeAnExistingAbsoluteFolder() {
        XCTAssertThrowsError(try MacTweaks.writeCommand(tweak("location"), value: "relative/path"))
        XCTAssertThrowsError(try MacTweaks.writeCommand(tweak("location"), value: "/nonexistent-codeos-folder"))
        XCTAssertNoThrow(try MacTweaks.writeCommand(tweak("location"), value: "/tmp"))
    }

    func testResetDeletesTheSetting() {
        let command = MacTweaks.resetCommand(tweak("tilesize"))
        XCTAssertEqual(command.arguments, ["delete", "com.apple.dock", "tilesize"])
    }

    func testRestartTargets() {
        XCTAssertNil(MacTweaks.restartCommand(.none))
        XCTAssertEqual(MacTweaks.restartCommand(.finder)?.arguments, ["Finder"])
        XCTAssertEqual(MacTweaks.restartCommand(.dock)?.arguments, ["Dock"])
    }

    func testCatalogIdsAreUnique() {
        let ids = MacTweaks.catalog.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}

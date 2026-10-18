import XCTest
@testable import CodeOSCore

final class PaletteMatcherTests: XCTestCase {
    func testLettersMustAppearInOrder() {
        XCTAssertTrue(PaletteMatcher.matches("gg", "Git Graph"))
        XCTAssertFalse(PaletteMatcher.matches("gx", "Git Graph"))
        XCTAssertTrue(PaletteMatcher.matches("GIT", "git graph"))
    }

    func testEmptyQueryReturnsEverythingInOrder() {
        let items = ["Storage", "Git Graph", "Devices"]
        XCTAssertEqual(PaletteMatcher.filter(items, query: "") { $0 }, items)
    }

    func testFiltersOutNonMatches() {
        let items = ["Storage", "Git Graph", "Devices"]
        XCTAssertEqual(PaletteMatcher.filter(items, query: "gr") { $0 }, ["Git Graph"])
    }

    func testPrefixMatchesRankFirst() {
        let items = ["Big Git", "Git Graph"]
        XCTAssertEqual(PaletteMatcher.filter(items, query: "git") { $0 }, ["Git Graph", "Big Git"])
    }
}

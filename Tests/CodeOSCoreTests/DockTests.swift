import XCTest
@testable import CodeOSCore

final class DockTests: XCTestCase {
    func testDefaultsAreValid() {
        for item in DockRules.defaults {
            XCTAssertNil(DockRules.problem(for: item), item.title)
        }
    }

    func testLinksMustBeWeb() {
        XCTAssertNil(DockRules.problem(for: DockItem(kind: .link, title: "Docs", symbol: "book", target: "https://example.com")))
        XCTAssertNotNil(DockRules.problem(for: DockItem(kind: .link, title: "Bad", symbol: "book", target: "file:///etc/passwd")))
    }

    func testFoldersMustExist() {
        XCTAssertNotNil(DockRules.problem(for: DockItem(kind: .folder, title: "X", symbol: "folder", target: "/nonexistent-codeos-dock")))
        XCTAssertNil(DockRules.problem(for: DockItem(kind: .folder, title: "Tmp", symbol: "folder", target: "/tmp")))
    }

    func testEmptyNameIsRejected() {
        XCTAssertNotNil(DockRules.problem(for: DockItem(kind: .section, title: "  ", symbol: "house", target: "home")))
    }

    func testRoundTripsThroughJSON() {
        let data = DockRules.encode(DockRules.defaults)
        XCTAssertEqual(DockRules.decode(data), DockRules.defaults)
    }

    func testGarbageDecodesToNil() {
        XCTAssertNil(DockRules.decode(Data("not json".utf8)))
    }
}

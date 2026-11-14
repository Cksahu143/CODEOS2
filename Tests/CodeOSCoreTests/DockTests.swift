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

    func testSpacersAndSeparatorsNeedNoName() {
        XCTAssertNil(DockRules.problem(for: DockItem(kind: .spacer, title: "", symbol: "", target: "")))
        XCTAssertNil(DockRules.problem(for: DockItem(kind: .separator, title: "", symbol: "", target: "")))
    }

    func testItemsRoundTripThroughJSON() {
        let data = DockRules.encode(DockRules.defaults)
        XCTAssertEqual(DockRules.decode(data), DockRules.defaults)
        XCTAssertNil(DockRules.decode(Data("not json".utf8)))
    }

    func testAppearanceIsValidated() {
        var appearance = DockAppearance()
        XCTAssertNil(DockRules.problem(for: appearance))
        appearance.backgroundHex = "blue"
        XCTAssertNotNil(DockRules.problem(for: appearance))
        appearance = DockAppearance()
        appearance.opacity = 0.05
        XCTAssertNotNil(DockRules.problem(for: appearance))
        appearance = DockAppearance()
        appearance.iconSize = 300
        XCTAssertNotNil(DockRules.problem(for: appearance))
        appearance = DockAppearance()
        appearance.position = "top"
        XCTAssertNotNil(DockRules.problem(for: appearance))
    }

    func testAppearanceRoundTripsThroughJSON() {
        var appearance = DockAppearance()
        appearance.backgroundHex = "#112233"
        appearance.isVisible = true
        XCTAssertEqual(DockRules.decodeAppearance(DockRules.encodeAppearance(appearance)), appearance)
    }
}

import XCTest
@testable import CodeOSCore

final class BatchRenameTests: XCTestCase {
    func testPrefixAndSuffixKeepTheExtension() {
        var rule = BatchRenameRule()
        rule.prefix = "2026-"
        rule.suffix = "_v2"
        let previews = BatchRename.preview(names: ["Photo.jpg", "Notes.txt"], rule: rule)
        XCTAssertEqual(previews.map(\.proposed), ["2026-Photo_v2.jpg", "2026-Notes_v2.txt"])
        XCTAssertTrue(previews.allSatisfy { $0.problem == nil })
    }

    func testNumberingIsPaddedAndStartsWhereAsked() {
        var rule = BatchRenameRule()
        rule.numberStart = 1
        rule.numberWidth = 2
        let previews = BatchRename.preview(names: ["a", "b", "c"], rule: rule)
        XCTAssertEqual(previews.map(\.proposed), ["a 01", "b 02", "c 03"])
    }

    func testFindReplaceChangesEveryOccurrence() {
        var rule = BatchRenameRule()
        rule.find = "draft"
        rule.replaceWith = "final"
        let previews = BatchRename.preview(names: ["draft draft.md"], rule: rule)
        XCTAssertEqual(previews.first?.proposed, "final final.md")
    }

    func testTwoItemsGettingTheSameNameAreFlagged() {
        var rule = BatchRenameRule()
        rule.find = "one"
        rule.replaceWith = "two"
        let previews = BatchRename.preview(names: ["one.txt", "two.txt"], rule: rule)
        XCTAssertNotNil(previews[0].problem)
        XCTAssertNotNil(previews[1].problem)
    }

    func testClashWithAFileOutsideTheBatchIsFlagged() {
        var rule = BatchRenameRule()
        rule.find = "a"
        rule.replaceWith = "b"
        let previews = BatchRename.preview(names: ["a.txt"], rule: rule, existing: ["b.txt"])
        XCTAssertNotNil(previews.first?.problem)
    }

    func testUnchangedNameIsNotAConflict() {
        let previews = BatchRename.preview(names: ["a.txt"], rule: BatchRenameRule(), existing: ["a.txt"])
        XCTAssertNil(previews.first?.problem)
    }

    func testSlashInNewNameIsRejected() {
        var rule = BatchRenameRule()
        rule.find = "a"
        rule.replaceWith = "x/y"
        let previews = BatchRename.preview(names: ["a.txt"], rule: rule)
        XCTAssertNotNil(previews.first?.problem)
    }
}

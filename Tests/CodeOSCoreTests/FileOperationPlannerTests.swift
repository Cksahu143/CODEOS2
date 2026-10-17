import XCTest
@testable import CodeOSCore

final class FileOperationPlannerTests: XCTestCase {
    func testRejectsTraversalAndSeparators() {
        XCTAssertFalse(FileOperationPlanner.isSafeComponent(".."))
        XCTAssertFalse(FileOperationPlanner.isSafeComponent("."))
        XCTAssertFalse(FileOperationPlanner.isSafeComponent("a/b"))
        XCTAssertFalse(FileOperationPlanner.isSafeComponent("a\\b"))
        XCTAssertFalse(FileOperationPlanner.isSafeComponent("   "))
        XCTAssertTrue(FileOperationPlanner.isSafeComponent("Notes.md"))
    }

    func testIsInsideBlocksEscapingRoot() {
        XCTAssertTrue(FileOperationPlanner.isInside("/Users/me/proj/src/a.swift", root: "/Users/me/proj"))
        XCTAssertFalse(FileOperationPlanner.isInside("/Users/me/proj/../other/a", root: "/Users/me/proj"))
        XCTAssertFalse(FileOperationPlanner.isInside("/Users/me/projX/a", root: "/Users/me/proj"))
    }

    func testUniqueNameAddsCounterBeforeExtension() {
        let taken: Set<String> = ["Report.txt", "Report 2.txt"]
        XCTAssertEqual(FileOperationPlanner.uniqueName(for: "Report.txt", existingNames: taken), "Report 3.txt")
        XCTAssertEqual(FileOperationPlanner.uniqueName(for: "Free.txt", existingNames: taken), "Free.txt")
        XCTAssertEqual(FileOperationPlanner.uniqueName(for: "Folder", existingNames: ["Folder"]), "Folder 2")
    }

    func testDestinationNeverSilentlyOverwrites() throws {
        XCTAssertThrowsError(try FileOperationPlanner.destination(directory: "/tmp", newName: "a.txt", existingNames: ["a.txt"])) {
            XCTAssertEqual($0 as? FileOperationError, .destinationExists("a.txt"))
        }
        XCTAssertEqual(
            try FileOperationPlanner.destination(directory: "/tmp", newName: "b.txt", existingNames: []),
            "/tmp/b.txt"
        )
    }
}

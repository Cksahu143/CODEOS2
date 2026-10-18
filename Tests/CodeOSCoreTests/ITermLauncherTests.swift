import XCTest
@testable import CodeOSCore

final class ITermLauncherTests: XCTestCase {
    func testRejectsRelativeAndMissingFolders() {
        XCTAssertThrowsError(try ITermLauncher.arguments(for: "relative/path"))
        XCTAssertThrowsError(try ITermLauncher.arguments(for: "/nonexistent-codeos-folder"))
    }

    func testFolderIsPassedAsTheLastArgumentNotInTheScript() throws {
        let dir = try TempDirectory()
        let tricky = dir.url.appendingPathComponent("my \"quoted\" $(folder); rm -rf x").path
        try FileManager.default.createDirectory(atPath: tricky, withIntermediateDirectories: true)

        let arguments = try ITermLauncher.arguments(for: tricky)
        XCTAssertEqual(arguments.last, tricky)
        let scriptArguments = arguments.dropLast()
        XCTAssertFalse(scriptArguments.contains { $0.contains(tricky) })
        XCTAssertEqual(arguments.filter { $0 == "-e" }.count, ITermLauncher.scriptLines.count)
    }

    func testScriptQuotesTheFolderWithAppleScriptRules() {
        XCTAssertTrue(ITermLauncher.scriptLines.contains { $0.contains("quoted form of folderPath") })
        XCTAssertTrue(ITermLauncher.scriptLines.contains { $0.contains("item 1 of argv") })
    }
}

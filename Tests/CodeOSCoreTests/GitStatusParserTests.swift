import XCTest
@testable import CodeOSCore

final class GitStatusParserTests: XCTestCase {
    func testParsesBranchAheadBehindAndEntries() {
        let output = """
        ## main...origin/main [ahead 2, behind 1]
         M Sources/App.swift
        A  New.swift
        ?? scratch.txt
        R  old.swift -> renamed.swift
        """
        let status = GitStatusParser.parse(output)
        XCTAssertEqual(status.branch, "main")
        XCTAssertEqual(status.aheadCount, 2)
        XCTAssertEqual(status.behindCount, 1)
        XCTAssertEqual(status.entries.count, 4)
        XCTAssertEqual(status.untrackedCount, 1)
        XCTAssertEqual(status.changedCount, 3)
        XCTAssertEqual(status.entries[3].path, "renamed.swift")
        XCTAssertFalse(status.isClean)
    }

    func testCleanRepositoryWithoutUpstream() {
        let status = GitStatusParser.parse("## feature/x\n")
        XCTAssertEqual(status.branch, "feature/x")
        XCTAssertTrue(status.isClean)
    }

    func testInitialRepositoryWithoutCommits() {
        XCTAssertEqual(GitStatusParser.parse("## No commits yet on main\n").branch, "main")
    }
}

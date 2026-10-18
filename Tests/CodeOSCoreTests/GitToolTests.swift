import XCTest
@testable import CodeOSCore

final class GitToolTests: XCTestCase {
    func testPicksTheFirstExistingCandidate() {
        let found = GitTool.locate(candidates: ["/nonexistent/git", "/usr/bin/true"], verify: false)
        XCTAssertEqual(found, "/usr/bin/true")
    }

    func testReturnsNilWhenNoCandidateExists() {
        XCTAssertNil(GitTool.locate(candidates: ["/nonexistent/git"], verify: false))
    }
}

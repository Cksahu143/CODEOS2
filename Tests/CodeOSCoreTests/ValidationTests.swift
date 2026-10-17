import XCTest
@testable import CodeOSCore

final class ValidationTests: XCTestCase {
    func testValidWorkspaceHasNoProblems() {
        let ws = Workspace(name: "EvolvED", projectPath: "/Users/me/evolved", documentationURLs: ["https://example.com/docs"])
        XCTAssertTrue(Validation.problems(in: ws).isEmpty)
    }

    func testWorkspaceRejectsBlankNameAndRelativePath() {
        XCTAssertEqual(Validation.problems(in: Workspace(name: "   ", projectPath: "relative")).count, 2)
    }

    func testWorkspaceRejectsNonWebDocumentationURL() {
        let ws = Workspace(name: "A", projectPath: "/a", documentationURLs: ["file:///etc/passwd", "javascript:alert(1)"])
        XCTAssertEqual(Validation.problems(in: ws).count, 2)
    }

    func testEmptyWorkflowIsRejected() {
        XCTAssertEqual(Validation.problems(in: Workflow(name: "Empty", actions: [])).count, 1)
    }

    func testWorkflowChecksEveryActionKind() {
        let bad = Workflow(name: "Bad", actions: [
            .openFolder(path: "relative"),
            .openFolderInApp(bundleID: "", path: "/ok"),
            .openURL("ftp://example.com"),
            .launchApp(bundleID: " "),
            .gitStatus(repoPath: "x"),
            .openTerminal(path: "y")
        ])
        XCTAssertEqual(Validation.problems(in: bad).count, 6)
    }

    func testURLValidation() {
        XCTAssertTrue(Validation.isWebURL("https://example.com"))
        XCTAssertTrue(Validation.isWebURL("http://localhost:8080"))
        XCTAssertFalse(Validation.isWebURL("ftp://example.com"))
        XCTAssertFalse(Validation.isWebURL("https://"))
        XCTAssertFalse(Validation.isWebURL("not a url"))
    }
}

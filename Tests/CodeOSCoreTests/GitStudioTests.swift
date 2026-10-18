import XCTest
@testable import CodeOSCore

final class GitStudioTests: XCTestCase {
    func testReadOnlyCommandsRunWithoutAsking() {
        XCTAssertEqual(GitCommandPolicy.classify(["status"]), .readOnly)
        XCTAssertEqual(GitCommandPolicy.classify(["log", "--oneline", "-5"]), .readOnly)
    }

    func testStateChangesAskFirst() {
        XCTAssertEqual(GitCommandPolicy.classify(["add", "a.txt"]), .changesState)
        XCTAssertEqual(GitCommandPolicy.classify(["commit", "-m", "x"]), .changesState)
    }

    func testDataLossCommandsAreDestructive() {
        XCTAssertEqual(GitCommandPolicy.classify(["reset", "--hard"]), .destructive)
        XCTAssertEqual(GitCommandPolicy.classify(["push", "--force"]), .destructive)
        XCTAssertEqual(GitCommandPolicy.classify(["branch", "-D", "old"]), .destructive)
        XCTAssertEqual(GitCommandPolicy.classify(["checkout", "--", "a.txt"]), .destructive)
    }

    func testConfigOverridesAndExternalProgramsAreBlocked() {
        if case .blocked = GitCommandPolicy.classify(["-c", "core.pager=evil", "log"]) {} else { XCTFail() }
        if case .blocked = GitCommandPolicy.classify(["log", "--exec=rm"]) {} else { XCTFail() }
        if case .blocked = GitCommandPolicy.classify([]) {} else { XCTFail() }
    }

    func testSplitterGroupsQuotedWords() {
        XCTAssertEqual(GitCommandLine.split("log --oneline \"my branch\""), ["log", "--oneline", "my branch"])
        XCTAssertEqual(GitCommandLine.split("  status  "), ["status"])
        XCTAssertNil(GitCommandLine.split("log \"unbalanced"))
    }

    func testSplitterDoesNotExpandShellSyntax() {
        XCTAssertEqual(GitCommandLine.split("log $(rm -rf x)"), ["log", "$(rm", "-rf", "x)"])
    }

    func testPathsOutsideTheRepositoryAreRefused() {
        XCTAssertFalse(GitStudio.isSafePath("/etc/passwd"))
        XCTAssertFalse(GitStudio.isSafePath("../secret"))
        XCTAssertFalse(GitStudio.isSafePath("-rf"))
        XCTAssertTrue(GitStudio.isSafePath("Sources/App.swift"))
    }

    func testEmptyCommitMessageIsRefused() {
        XCTAssertThrowsError(try GitStudio.commit(message: "   ", in: "/tmp"))
    }

    func testStageCommitAndStatusInARealRepository() throws {
        try XCTSkipUnless(GitTool.resolved != nil)
        let dir = try TempDirectory()
        let repo = dir.url.path
        _ = try GitStudio.run(["init", "-q"], in: repo)
        _ = try GitStudio.run(["config", "user.name", "Test"], in: repo)
        _ = try GitStudio.run(["config", "user.email", "test@example.com"], in: repo)
        try dir.file("one.txt", contents: "1")
        try dir.file("two.txt", contents: "2")

        let before = try GitStudio.status(in: repo)
        XCTAssertEqual(before.entries.count, 2)
        XCTAssertTrue(before.entries.allSatisfy { $0.indexCode == "?" })

        let staged = try GitStudio.stage(["one.txt"], in: repo)
        XCTAssertTrue(staged.succeeded, staged.stderr)
        let mid = try GitStudio.status(in: repo)
        XCTAssertEqual(mid.entries.filter { $0.indexCode == "A" }.map(\.path), ["one.txt"])

        let committed = try GitStudio.commit(message: "Add one", in: repo)
        XCTAssertTrue(committed.succeeded, committed.stderr)
        let after = try GitStudio.status(in: repo)
        XCTAssertEqual(after.entries.map(\.path), ["two.txt"])
    }
}

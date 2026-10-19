import XCTest
@testable import CodeOSCore

final class MergeExecutionTests: XCTestCase {
    func testUntrackedFilesDoNotBlockAMerge() {
        let entries = [GitStatus.Entry(indexCode: "?", worktreeCode: "?", path: "new.txt")]
        XCTAssertTrue(MergeExecution.blockingChanges(entries).isEmpty)
    }

    func testStagedAndUnstagedChangesBlockAMerge() {
        let entries = [
            GitStatus.Entry(indexCode: "M", worktreeCode: " ", path: "a.txt"),
            GitStatus.Entry(indexCode: " ", worktreeCode: "M", path: "b.txt"),
        ]
        XCTAssertEqual(MergeExecution.blockingChanges(entries), ["a.txt", "b.txt"])
    }

    func testOptionLikeBranchIsRefusedBeforeGitRuns() throws {
        let outcome = try MergeExecution.merge(branch: "--strategy=ours", into: "/tmp")
        if case .refused = outcome {} else { XCTFail("expected refusal") }
    }

    func testCleanMergeCompletesInARealRepository() throws {
        try XCTSkipUnless(GitTool.resolved != nil)
        let dir = try TempDirectory()
        let repo = dir.url.path
        _ = try GitStudio.run(["init", "-q"], in: repo)
        _ = try GitStudio.run(["symbolic-ref", "HEAD", "refs/heads/main"], in: repo)
        _ = try GitStudio.run(["config", "user.name", "Test"], in: repo)
        _ = try GitStudio.run(["config", "user.email", "test@example.com"], in: repo)
        try dir.file("a.txt", contents: "base\n")
        _ = try GitStudio.run(["add", "-A"], in: repo)
        _ = try GitStudio.run(["commit", "-q", "-m", "base"], in: repo)
        _ = try GitStudio.run(["checkout", "-q", "-b", "feature"], in: repo)
        try dir.file("b.txt", contents: "feature\n")
        _ = try GitStudio.run(["add", "-A"], in: repo)
        _ = try GitStudio.run(["commit", "-q", "-m", "feature"], in: repo)
        _ = try GitStudio.run(["checkout", "-q", "main"], in: repo)

        let outcome = try MergeExecution.merge(branch: "feature", into: repo)
        if case .merged = outcome {} else { XCTFail("expected a merged result, got \(outcome)") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo + "/b.txt"))
    }

    func testConflictingMergeStopsAndKeepsTheConflict() throws {
        try XCTSkipUnless(GitTool.resolved != nil)
        let dir = try TempDirectory()
        let repo = dir.url.path
        _ = try GitStudio.run(["init", "-q"], in: repo)
        _ = try GitStudio.run(["symbolic-ref", "HEAD", "refs/heads/main"], in: repo)
        _ = try GitStudio.run(["config", "user.name", "Test"], in: repo)
        _ = try GitStudio.run(["config", "user.email", "test@example.com"], in: repo)
        try dir.file("a.txt", contents: "base\n")
        _ = try GitStudio.run(["add", "-A"], in: repo)
        _ = try GitStudio.run(["commit", "-q", "-m", "base"], in: repo)
        _ = try GitStudio.run(["checkout", "-q", "-b", "feature"], in: repo)
        try dir.file("a.txt", contents: "feature\n")
        _ = try GitStudio.run(["commit", "-q", "-am", "feature"], in: repo)
        _ = try GitStudio.run(["checkout", "-q", "main"], in: repo)
        try dir.file("a.txt", contents: "main\n")
        _ = try GitStudio.run(["commit", "-q", "-am", "main"], in: repo)

        let outcome = try MergeExecution.merge(branch: "feature", into: repo)
        if case .conflicts = outcome {} else { XCTFail("expected conflicts, got \(outcome)") }
        let status = try GitStudio.status(in: repo)
        XCTAssertTrue(status.entries.contains { $0.path == "a.txt" })
    }
}

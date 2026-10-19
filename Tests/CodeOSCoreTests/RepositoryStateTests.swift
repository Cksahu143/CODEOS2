import XCTest
@testable import CodeOSCore

final class RepositoryStateTests: XCTestCase {
    private func titles(_ findings: [RepositoryFinding]) -> [String] {
        findings.map(\.title)
    }

    private func check(existing: Set<String> = [], branch: Bool = true, commits: Bool = true,
                       entries: [GitStatus.Entry] = []) -> [RepositoryFinding] {
        RepositoryStateExplainer.findings(
            gitDirectory: "/repo/.git",
            fileExists: { path in existing.contains { path.hasSuffix("/" + $0) } },
            headIsBranch: branch,
            hasCommits: commits,
            entries: entries)
    }

    func testCleanBranchReportsClean() {
        XCTAssertEqual(titles(check()), ["Repository is clean"])
    }

    func testDetachedHeadIsAWarningWithAFix() {
        let findings = check(branch: false)
        XCTAssertEqual(findings.first?.title, "Detached HEAD")
        XCTAssertEqual(findings.first?.severity, .warning)
        XCTAssertNotNil(findings.first?.suggestedCommand)
    }

    func testUnfinishedMergeSuggestsAbort() {
        let findings = check(existing: ["MERGE_HEAD"])
        XCTAssertTrue(findings.contains { $0.title == "Merge in progress" && $0.suggestedCommand == "git merge --abort" })
    }

    func testRebaseInEitherFormIsDetected() {
        XCTAssertTrue(titles(check(existing: ["rebase-merge"])).contains("Rebase in progress"))
        XCTAssertTrue(titles(check(existing: ["rebase-apply"])).contains("Rebase in progress"))
    }

    func testConflictsAreErrors() {
        let entries = [GitStatus.Entry(indexCode: "U", worktreeCode: "U", path: "a.txt")]
        let findings = check(entries: entries)
        XCTAssertTrue(findings.contains { $0.title == "1 file(s) have conflicts" && $0.severity == .error })
    }

    func testUnstagedAndUntrackedAreInformation() {
        let entries = [
            GitStatus.Entry(indexCode: " ", worktreeCode: "M", path: "b.txt"),
            GitStatus.Entry(indexCode: "?", worktreeCode: "?", path: "c.txt"),
        ]
        let findings = check(entries: entries)
        XCTAssertTrue(findings.contains { $0.title == "1 file(s) changed but not staged" && $0.severity == .info })
        XCTAssertTrue(findings.contains { $0.title == "1 untracked file(s)" })
    }

    func testRepositoryWithoutCommitsSaysSo() {
        XCTAssertEqual(titles(check(commits: false)).first, "No commits yet")
    }

    func testRealDetachedRepositoryIsDetected() throws {
        try XCTSkipUnless(GitTool.resolved != nil)
        let dir = try TempDirectory()
        let repo = dir.url.path
        _ = try GitStudio.run(["init", "-q"], in: repo)
        _ = try GitStudio.run(["config", "user.name", "Test"], in: repo)
        _ = try GitStudio.run(["config", "user.email", "test@example.com"], in: repo)
        try dir.file("a.txt", contents: "1")
        _ = try GitStudio.run(["add", "-A"], in: repo)
        _ = try GitStudio.run(["commit", "-q", "-m", "first"], in: repo)
        _ = try GitStudio.run(["checkout", "-q", "--detach", "HEAD"], in: repo)

        let findings = try RepositoryStateExplainer.explain(repository: repo)
        XCTAssertTrue(findings.contains { $0.title == "Detached HEAD" })
    }
}

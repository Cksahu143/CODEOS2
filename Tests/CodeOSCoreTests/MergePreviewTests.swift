import XCTest
@testable import CodeOSCore

final class MergePreviewTests: XCTestCase {
    func testParsesGitVersion() {
        let version = MergePreview.gitVersion("git version 2.39.5 (Apple Git-154)")
        XCTAssertEqual(version?.major, 2)
        XCTAssertEqual(version?.minor, 39)
        XCTAssertTrue(MergePreview.supportsMergeTree(version!))
        XCTAssertFalse(MergePreview.supportsMergeTree((2, 37)))
    }

    func testParsesDivergenceCounts() {
        XCTAssertEqual(MergePreview.parseCounts("2\t3\n"), BranchDivergence(onlyInA: 2, onlyInB: 3))
        XCTAssertNil(MergePreview.parseCounts("garbage"))
    }

    func testCleanMergeHasNoConflicts() {
        XCTAssertEqual(MergePreview.parseMergeTree(output: "abc123\n", exitCode: 0), [])
    }

    func testConflictsAreReadUntilTheBlankLine() {
        let output = "abc123\na.txt\nb.txt\n\nCONFLICT (content): Merge conflict in a.txt\n"
        XCTAssertEqual(MergePreview.parseMergeTree(output: output, exitCode: 1), ["a.txt", "b.txt"])
    }

    func testOtherExitCodesAreNotTreatedAsResults() {
        XCTAssertNil(MergePreview.parseMergeTree(output: "", exitCode: 128))
    }

    func testBranchNamesThatLookLikeOptionsAreRefused() {
        XCTAssertFalse(MergePreview.isSafeBranchName("--output=/etc/x"))
        XCTAssertFalse(MergePreview.isSafeBranchName("a..b"))
        XCTAssertTrue(MergePreview.isSafeBranchName("feature/login"))
    }

    func testPredictsConflictOnSameFileAndCleanForDisjointFiles() throws {
        try XCTSkipUnless(GitTool.resolved != nil)
        let dir = try TempDirectory()
        let repo = dir.url.path
        let versionText = try GitStudio.run(["--version"], in: repo).stdout
        guard let version = MergePreview.gitVersion(versionText), MergePreview.supportsMergeTree(version) else {
            throw XCTSkip("Needs Git 2.38 or newer")
        }

        _ = try GitStudio.run(["init", "-q"], in: repo)
        _ = try GitStudio.run(["symbolic-ref", "HEAD", "refs/heads/main"], in: repo)
        _ = try GitStudio.run(["config", "user.name", "Test"], in: repo)
        _ = try GitStudio.run(["config", "user.email", "test@example.com"], in: repo)
        try dir.file("a.txt", contents: "base\n")
        _ = try GitStudio.run(["add", "-A"], in: repo)
        _ = try GitStudio.run(["commit", "-q", "-m", "base"], in: repo)

        _ = try GitStudio.run(["checkout", "-q", "-b", "feature"], in: repo)
        try dir.file("a.txt", contents: "feature\n")
        try dir.file("b.txt", contents: "feature only\n")
        _ = try GitStudio.run(["add", "-A"], in: repo)
        _ = try GitStudio.run(["commit", "-q", "-m", "feature"], in: repo)

        _ = try GitStudio.run(["checkout", "-q", "main"], in: repo)
        try dir.file("a.txt", contents: "main\n")
        _ = try GitStudio.run(["add", "-A"], in: repo)
        _ = try GitStudio.run(["commit", "-q", "-m", "main change"], in: repo)

        let conflict = try MergePreview.preview(repository: repo, branchA: "main", branchB: "feature")
        XCTAssertEqual(conflict.predictedConflicts, ["a.txt"])
        XCTAssertEqual(conflict.changedOnBoth, ["a.txt"])
        XCTAssertEqual(conflict.divergence, BranchDivergence(onlyInA: 1, onlyInB: 1))

        _ = try GitStudio.run(["checkout", "-q", "-b", "docs", "HEAD~1"], in: repo)
        try dir.file("c.txt", contents: "docs\n")
        _ = try GitStudio.run(["add", "-A"], in: repo)
        _ = try GitStudio.run(["commit", "-q", "-m", "docs"], in: repo)

        let clean = try MergePreview.preview(repository: repo, branchA: "main", branchB: "docs")
        XCTAssertEqual(clean.predictedConflicts, [])
        XCTAssertTrue(clean.changedOnBoth.isEmpty)
    }
}

import XCTest
@testable import CodeOSCore

final class GitDiffTests: XCTestCase {
    private let sample = """
    diff --git a/one.txt b/one.txt
    index 1111111..2222222 100644
    --- a/one.txt
    +++ b/one.txt
    @@ -1 +1,2 @@
    -old line
    +new line
    +extra line
     unchanged
    diff --git a/pic.png b/pic.png
    Binary files a/pic.png and b/pic.png differ
    """

    func testSplitsFilesAndCountsChanges() {
        let files = DiffParser.parse(sample)
        XCTAssertEqual(files.map(\.path), ["one.txt", "pic.png"])
        XCTAssertEqual(files[0].additions, 2)
        XCTAssertEqual(files[0].deletions, 1)
    }

    func testLinesAreLabelledByKind() {
        let lines = DiffParser.parse(sample)[0].lines
        XCTAssertEqual(lines.first { $0.text == "-old line" }?.kind, .removed)
        XCTAssertEqual(lines.first { $0.text == "+new line" }?.kind, .added)
        XCTAssertEqual(lines.first { $0.text == " unchanged" }?.kind, .context)
        XCTAssertEqual(lines.first { $0.text.hasPrefix("@@") }?.kind, .hunk)
    }

    func testFileHeadersDoNotCountAsChanges() {
        let file = DiffParser.parse(sample)[0]
        XCTAssertFalse(file.lines.contains { $0.text == "+++ b/one.txt" && $0.kind == .added })
    }

    func testBinaryFilesAreMarkedNotShownAsText() {
        let binary = DiffParser.parse(sample)[1]
        XCTAssertTrue(binary.isBinary)
        XCTAssertEqual(binary.additions, 0)
    }

    func testEmptyOutputGivesNoFiles() {
        XCTAssertTrue(DiffParser.parse("").isEmpty)
    }

    func testWorkingTreeAndCommitDiffsInARealRepository() throws {
        try XCTSkipUnless(GitTool.resolved != nil)
        let dir = try TempDirectory()
        let repo = dir.url.path
        _ = try GitStudio.run(["init", "-q"], in: repo)
        _ = try GitStudio.run(["symbolic-ref", "HEAD", "refs/heads/main"], in: repo)
        _ = try GitStudio.run(["config", "user.name", "Test"], in: repo)
        _ = try GitStudio.run(["config", "user.email", "test@example.com"], in: repo)
        try dir.file("a.txt", contents: "1\n")
        _ = try GitStudio.run(["add", "-A"], in: repo)
        _ = try GitStudio.run(["commit", "-q", "-m", "first"], in: repo)
        try dir.file("a.txt", contents: "2\n")

        let working = DiffParser.parse(try GitDiffReader.workingTree(repository: repo))
        XCTAssertEqual(working.map(\.path), ["a.txt"])
        XCTAssertEqual(working[0].additions, 1)
        XCTAssertEqual(working[0].deletions, 1)

        _ = try GitStudio.run(["add", "-A"], in: repo)
        _ = try GitStudio.run(["commit", "-q", "-m", "second"], in: repo)
        let commits = try GitDiffReader.recentCommits(repository: repo)
        XCTAssertEqual(commits.map(\.subject), ["second", "first"])
        let committed = DiffParser.parse(try GitDiffReader.commit(repository: repo, hash: commits[0].hash))
        XCTAssertEqual(committed.map(\.path), ["a.txt"])
    }
}

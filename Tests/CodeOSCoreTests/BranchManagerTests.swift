import XCTest
@testable import CodeOSCore

final class BranchManagerTests: XCTestCase {
    func testParsesLocalBranchLines() {
        let output = "*\tmain\torigin/main\t2026-10-01\tAdd login\n \tfeature\t\t2026-09-30\tWIP\n"
        let branches = BranchManager.parseRefs(output, remote: false)
        XCTAssertEqual(branches.map(\.name), ["main", "feature"])
        XCTAssertTrue(branches[0].isCurrent)
        XCTAssertEqual(branches[0].upstream, "origin/main")
        XCTAssertNil(branches[1].upstream)
        XCTAssertEqual(branches[1].lastCommitSubject, "WIP")
    }

    func testRemoteHeadPointersAreSkipped() {
        let branches = BranchManager.parseRefs("\torigin/HEAD\t\t2026-01-01\tx\n\torigin/dev\t\t2026-01-02\ty\n", remote: true)
        XCTAssertEqual(branches.map(\.name), ["origin/dev"])
        XCTAssertTrue(branches[0].isRemote)
    }

    func testCreateSwitchAndSafeDeleteInARealRepository() throws {
        try XCTSkipUnless(GitTool.resolved != nil)
        let dir = try TempDirectory()
        let repo = dir.url.path
        _ = try GitStudio.run(["init", "-q"], in: repo)
        _ = try GitStudio.run(["symbolic-ref", "HEAD", "refs/heads/main"], in: repo)
        _ = try GitStudio.run(["config", "user.name", "Test"], in: repo)
        _ = try GitStudio.run(["config", "user.email", "test@example.com"], in: repo)
        try dir.file("a.txt", contents: "1")
        _ = try GitStudio.run(["add", "-A"], in: repo)
        _ = try GitStudio.run(["commit", "-q", "-m", "first"], in: repo)

        XCTAssertTrue(try BranchManager.isValidNewName("feature-x", in: repo))
        XCTAssertFalse(try BranchManager.isValidNewName("bad..name", in: repo))
        XCTAssertTrue(try BranchManager.create("feature-x", in: repo).succeeded)

        var list = try BranchManager.list(repository: repo)
        XCTAssertEqual(list.first { $0.isCurrent }?.name, "feature-x")

        XCTAssertTrue(try BranchManager.switchTo("main", in: repo).succeeded)
        XCTAssertTrue(try BranchManager.deleteMerged("feature-x", in: repo).succeeded)
        list = try BranchManager.list(repository: repo)
        XCTAssertFalse(list.contains { $0.name == "feature-x" })
    }
}

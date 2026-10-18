import XCTest
@testable import CodeOSCore

final class GitGraphTests: XCTestCase {
    private func commit(_ hash: String, parents: [String]) -> GitCommit {
        GitCommit(hash: hash, parents: parents, refs: [], author: "A", date: "2026-01-01", subject: hash)
    }

    func testLinearHistoryStaysInOneLane() {
        let rows = GitGraph.layout([commit("a", parents: ["b"]), commit("b", parents: ["c"]), commit("c", parents: [])])
        XCTAssertEqual(rows.map(\.lane), [0, 0, 0])
        XCTAssertEqual(rows[0].parentLanes, [0])
        XCTAssertEqual(rows[2].parentLanes, [])
    }

    func testMergeOpensASecondLaneAndClosesIt() {
        // M merges F and S; both descend from P.
        let rows = GitGraph.layout([
            commit("m", parents: ["f", "s"]),
            commit("f", parents: ["p"]),
            commit("s", parents: ["p"]),
            commit("p", parents: []),
        ])
        XCTAssertEqual(rows[0].parentLanes, [0, 1])
        XCTAssertEqual(rows[2].lane, 1)
        XCTAssertEqual(rows[2].parentLanes, [0])
        XCTAssertEqual(rows[3].lane, 0)
        XCTAssertTrue(rows[3].bottomLanes.isEmpty)
    }

    func testParsesFieldsAndRefs() {
        let record = "abc1234567\u{1f}p1 p2\u{1f}HEAD -> main, tag: v1\u{1f}Ann\u{1f}2026-01-01T10:00:00+00:00\u{1f}Subject\u{1e}\n"
        let commits = GitGraph.parse(record)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].parents, ["p1", "p2"])
        XCTAssertEqual(commits[0].refs, ["HEAD -> main", "tag: v1"])
        XCTAssertEqual(commits[0].shortHash, "abc1234")
        XCTAssertEqual(commits[0].subject, "Subject")
    }

    func testNameStatusParsingKeepsRenameDestination() {
        let files = GitInspector.parseNameStatus("M\tSources/a.swift\nR100\told.swift\trenamed.swift\n")
        XCTAssertEqual(files.map(\.path), ["Sources/a.swift", "renamed.swift"])
        XCTAssertEqual(files.map(\.status), ["M", "R100"])
    }

    func testRejectsInvalidHashes() {
        XCTAssertTrue(GitInspector.isValidHash("abcdef1"))
        XCTAssertFalse(GitInspector.isValidHash("--output=/etc/x"))
        XCTAssertFalse(GitInspector.isValidHash("abc"))
    }

    func testNotARepositoryIsReported() {
        XCTAssertThrowsError(try GitGraph.load(repository: "/nonexistent-codeos-repo")) { error in
            XCTAssertEqual(error as? GitError, .notARepository("/nonexistent-codeos-repo"))
        }
    }

    func testRealRepositoryWithMergeIsLaidOutCorrectly() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/git"))
        let dir = try TempDirectory()
        func git(_ arguments: [String]) throws {
            let result = try ProcessRunner.run(
                executable: "/usr/bin/git",
                arguments: ["-c", "user.name=Test", "-c", "user.email=test@example.com"] + arguments,
                workingDirectory: dir.url.path)
            XCTAssertTrue(result.succeeded, result.stderr)
        }
        try git(["init", "-q"])
        try git(["symbolic-ref", "HEAD", "refs/heads/main"])
        try dir.file("a.txt", contents: "1")
        try git(["add", "."]); try git(["commit", "-q", "-m", "first"])
        try git(["checkout", "-q", "-b", "feature"])
        try dir.file("b.txt", contents: "2")
        try git(["add", "."]); try git(["commit", "-q", "-m", "feature work"])
        try git(["checkout", "-q", "main"])
        try dir.file("c.txt", contents: "3")
        try git(["add", "."]); try git(["commit", "-q", "-m", "main work"])
        try git(["merge", "-q", "--no-ff", "feature", "-m", "merge feature"])

        let rows = try GitGraph.load(repository: dir.url.path)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].commit.subject, "merge feature")
        XCTAssertEqual(rows[0].commit.parents.count, 2)
        XCTAssertEqual(rows.last?.commit.subject, "first")

        let files = try GitInspector.changedFiles(repository: dir.url.path, commit: rows[0].commit.hash)
        XCTAssertTrue(files.isEmpty || files.allSatisfy { !$0.path.isEmpty })
        let feature = try XCTUnwrap(rows.first { $0.commit.subject == "feature work" })
        let diff = try GitInspector.diff(repository: dir.url.path, commit: feature.commit.hash, path: "b.txt")
        XCTAssertTrue(diff.contains("+2"))
    }
}

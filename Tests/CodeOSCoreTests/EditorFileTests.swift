import XCTest
@testable import CodeOSCore

final class EditorFileTests: XCTestCase {
    func testLanguageFromExtensionIgnoresCase() {
        XCTAssertEqual(EditorFile.language(for: "App.swift"), "swift")
        XCTAssertEqual(EditorFile.language(for: "README.MD"), "markdown")
        XCTAssertEqual(EditorFile.language(for: "Makefile"), "plaintext")
    }

    func testNulByteMeansBinary() {
        XCTAssertTrue(EditorFile.isBinary(Data([0x41, 0x00, 0x42])))
        XCTAssertFalse(EditorFile.isBinary(Data("plain text".utf8)))
    }

    func testWriteThenReadRoundTrips() throws {
        let dir = try TempDirectory()
        let path = dir.url.appendingPathComponent("note.txt").path
        try EditorFile.write("hello\nworld\n", to: path)
        XCTAssertEqual(try EditorFile.read(path), "hello\nworld\n")
    }

    func testBinaryFileIsRefused() throws {
        let dir = try TempDirectory()
        let path = dir.url.appendingPathComponent("image.bin").path
        FileManager.default.createFile(atPath: path, contents: Data([0x00, 0x01, 0x02]))
        XCTAssertThrowsError(try EditorFile.read(path)) { error in
            XCTAssertEqual(error as? EditorFileError, .binary)
        }
    }

    func testOversizedWriteIsRefused() {
        let big = String(repeating: "a", count: EditorFile.maxBytes + 1)
        XCTAssertThrowsError(try EditorFile.write(big, to: "/tmp/codeos-never-written.txt"))
    }

    func testRepositoryFilesListsTrackedFiles() throws {
        try XCTSkipUnless(GitTool.resolved != nil)
        let dir = try TempDirectory()
        let repo = dir.url.path
        _ = try GitStudio.run(["init", "-q"], in: repo)
        try dir.file("a.txt", contents: "1")
        try dir.file("b.txt", contents: "2")
        _ = try GitStudio.run(["add", "-A"], in: repo)
        let files = try EditorFile.repositoryFiles(repo)
        XCTAssertEqual(files.sorted(), ["a.txt", "b.txt"])
    }
}

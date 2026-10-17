import XCTest
@testable import CodeOSCore

final class DirectoryListingTests: XCTestCase {
    func testFoldersFirstAndHiddenFilesOptional() throws {
        let dir = try TempDirectory()
        try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("Zeta"), withIntermediateDirectories: true)
        try dir.file("beta.txt")
        try dir.file("alpha.txt")
        try dir.file(".secret")

        let visible = try DirectoryListing.list(dir.url.path, showHidden: false)
        XCTAssertEqual(visible.map(\.name), ["Zeta", "alpha.txt", "beta.txt"])

        let all = try DirectoryListing.list(dir.url.path, showHidden: true)
        XCTAssertTrue(all.contains { $0.name == ".secret" })
    }

    func testSortBySizeDescending() {
        let items = [
            FileItem(path: "/a", name: "a", isDirectory: false, isSymbolicLink: false, size: 10, modified: nil),
            FileItem(path: "/b", name: "b", isDirectory: false, isSymbolicLink: false, size: 500, modified: nil),
            FileItem(path: "/c", name: "c", isDirectory: false, isSymbolicLink: false, size: 50, modified: nil)
        ]
        let sorted = DirectoryListing.sorted(items, by: .size, ascending: false)
        XCTAssertEqual(sorted.map(\.name), ["b", "c", "a"])
    }

    func testParentOfRoot() {
        XCTAssertEqual(DirectoryListing.parent(of: "/Users/me"), "/Users")
        XCTAssertEqual(DirectoryListing.parent(of: "/"), "/")
    }

    func testUnreadableFolderThrows() {
        XCTAssertThrowsError(try DirectoryListing.list("/nonexistent-codeos-folder"))
    }
}

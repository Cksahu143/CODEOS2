import XCTest
@testable import CodeOSCore

final class StorageAdvisorTests: XCTestCase {
    func testMeasuresFileSizes() throws {
        let dir = try TempDirectory()
        try dir.file("a.bin", contents: String(repeating: "x", count: 10_000))
        XCTAssertGreaterThan(StorageAdvisor.size(of: dir.url.path), 0)
    }

    func testMissingPathHasZeroSize() {
        XCTAssertEqual(StorageAdvisor.size(of: "/nonexistent-codeos-path"), 0)
    }

    func testFindsNestedArtifactsWithoutDescendingIntoThem() throws {
        let dir = try TempDirectory()
        let fm = FileManager.default
        let project = dir.url.appendingPathComponent("web/app")
        let nested = project.appendingPathComponent("node_modules/dep/node_modules")
        try fm.createDirectory(at: project.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.url.appendingPathComponent("swift/.build"), withIntermediateDirectories: true)

        let hits = StorageAdvisor.findArtifacts(in: dir.url.path, named: ["node_modules", ".build"])
        XCTAssertEqual(hits.count, 2)
        XCTAssertFalse(hits.contains { $0.contains("dep/node_modules") })
    }

    func testMoveToTrashRemovesItemFromOriginalLocation() throws {
        let dir = try TempDirectory()
        let file = try dir.file("disposable.txt", contents: "bye")
        try StorageAdvisor.moveToTrash(file.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testKnownCachesAreUnderHome() {
        let caches = StorageAdvisor.knownCaches(home: "/Users/example")
        XCTAssertFalse(caches.isEmpty)
        XCTAssertTrue(caches.allSatisfy { $0.path.hasPrefix("/Users/example/") })
    }
}

import XCTest
@testable import CodeOSCore

final class ConfigStoreTests: XCTestCase {
    func testMissingFileReturnsDefaults() throws {
        let dir = try TempDirectory()
        let store = ConfigStore(fileURL: dir.url.appendingPathComponent("config.json"))
        let result = try store.load()
        XCTAssertEqual(result.outcome, .createdDefault)
        XCTAssertEqual(result.configuration, AppConfiguration())
    }

    func testRoundTripPersistsWorkspacesAndWorkflows() throws {
        let dir = try TempDirectory()
        let store = ConfigStore(fileURL: dir.url.appendingPathComponent("config.json"))
        let config = AppConfiguration(
            workspaces: [Workspace(name: "Demo", projectPath: "/tmp/demo", documentationURLs: ["https://example.com"])],
            workflows: [Workflow(name: "Start", actions: [.openURL("https://example.com"), .gitStatus(repoPath: "/tmp/demo")])]
        )
        try store.save(config)
        let loaded = try store.load()
        XCTAssertEqual(loaded.outcome, .loaded)
        XCTAssertEqual(loaded.configuration, config)
    }

    func testCorruptFileIsMovedAsideNotDeleted() throws {
        let dir = try TempDirectory()
        let file = try dir.file("config.json", contents: "{ not json")
        let store = ConfigStore(fileURL: file)

        let result = try store.load()
        guard case let .recoveredFromCorruptFile(backup) = result.outcome else {
            return XCTFail("Expected recovery, got \(result.outcome)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try String(contentsOf: backup), "{ not json")
        XCTAssertEqual(result.configuration, AppConfiguration())
    }

    func testNewerSchemaIsRejectedAndLeftUntouched() throws {
        let dir = try TempDirectory()
        let file = dir.url.appendingPathComponent("config.json")
        let future = AppConfiguration(schemaVersion: AppConfiguration.currentSchemaVersion + 1)
        try JSONEncoder().encode(future).write(to: file)

        XCTAssertThrowsError(try ConfigStore(fileURL: file).load()) { error in
            XCTAssertEqual(error as? ConfigStoreError, .unsupportedSchemaVersion(future.schemaVersion))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}

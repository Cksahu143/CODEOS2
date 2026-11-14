import XCTest
@testable import CodeOSCore

final class SystemDockTests: XCTestCase {
    func testSizeRangesAreEnforced() throws {
        XCTAssertEqual(try SystemDock.validatedNumber("tilesize", "48"), 48)
        XCTAssertThrowsError(try SystemDock.validatedNumber("tilesize", "400"))
        XCTAssertThrowsError(try SystemDock.validatedNumber("tilesize", "big"))
        XCTAssertThrowsError(try SystemDock.validatedNumber("unknownKey", "10"))
    }

    func testAppTileIsBuiltFromAPath() {
        let tile = SystemDock.tileDictionary(forApp: "/Applications/Safari.app")
        let data = tile["tile-data"] as? [String: Any]
        XCTAssertEqual(data?["file-label"] as? String, "Safari")
        XCTAssertEqual(data?["file-type"] as? Int, 41)
        XCTAssertEqual(tile["tile-type"] as? String, "file-tile")
    }

    func testFolderTileIsDirectory() {
        let tile = SystemDock.tileDictionary(forFolder: "/Users/example/Projects")
        XCTAssertEqual(tile["tile-type"] as? String, "directory-tile")
        XCTAssertEqual((tile["tile-data"] as? [String: Any])?["file-label"] as? String, "Projects")
    }

    func testTilesAreReadBackWithTheirPaths() {
        let tile = SystemDock.tileDictionary(forApp: "/Applications/Notes.app")
        let dictionary: [String: Any] = [SystemDock.appsKey: [tile]]
        let tiles = SystemDock.tiles(in: dictionary, section: SystemDock.appsKey)
        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].label, "Notes")
        XCTAssertEqual(tiles[0].path, "/Applications/Notes.app")
    }

    func testRemoveOnlyTouchesTheChosenTile() {
        let first = SystemDock.tileDictionary(forApp: "/Applications/A.app")
        let second = SystemDock.tileDictionary(forApp: "/Applications/B.app")
        var dictionary: [String: Any] = [SystemDock.appsKey: [first, second], "tilesize": 48]
        XCTAssertTrue(SystemDock.remove(section: SystemDock.appsKey, index: 0, from: &dictionary))
        XCTAssertEqual(SystemDock.tiles(in: dictionary, section: SystemDock.appsKey).map(\.label), ["B"])
        XCTAssertEqual(dictionary["tilesize"] as? Int, 48)
        XCTAssertFalse(SystemDock.remove(section: SystemDock.appsKey, index: 9, from: &dictionary))
    }
}

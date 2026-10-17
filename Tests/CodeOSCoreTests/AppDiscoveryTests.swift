import XCTest
@testable import CodeOSCore

final class AppDiscoveryTests: XCTestCase {
    func testFindsBundleWithIdentifierInDirectory() throws {
        let dir = try TempDirectory()
        let contents = dir.url.appendingPathComponent("Demo.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.test.demo", "CFBundleName": "Demo"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try dir.file("NotAnApp.txt")

        let apps = AppDiscovery.scan(directories: [dir.url.path])
        XCTAssertEqual(apps.map(\.bundleID), ["com.test.demo"])
        XCTAssertEqual(apps.first?.name, "Demo")
    }

    func testEmptyWhenDirectoryMissing() {
        XCTAssertTrue(AppDiscovery.scan(directories: ["/nonexistent-codeos-apps"]).isEmpty)
    }
}

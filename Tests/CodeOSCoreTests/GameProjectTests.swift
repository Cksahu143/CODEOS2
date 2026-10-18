import XCTest
@testable import CodeOSCore

final class GameProjectTests: XCTestCase {
    private let packageJSON = """
    {
      "name": "demo-game",
      "dependencies": { "phaser": "^3.80.1" },
      "devDependencies": { "typescript": "^5.4.0", "vite": "^5.0.0" },
      "scripts": { "dev": "vite", "build": "tsc && vite build", "test": "vitest" }
    }
    """

    func testDetectsAFullPhaserProject() throws {
        let dir = try TempDirectory()
        try dir.file("package.json", contents: packageJSON)
        try dir.file("index.html", contents: "<html></html>")
        try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("public/assets"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("node_modules"), withIntermediateDirectories: true)

        let project = GameProjectDetector.inspect(folder: dir.url.path)
        XCTAssertEqual(project.name, "demo-game")
        XCTAssertEqual(project.engines.map(\.name), ["phaser"])
        XCTAssertEqual(project.engines.first?.version, "^3.80.1")
        XCTAssertTrue(project.usesTypeScript)
        XCTAssertEqual(project.bundler, "vite")
        XCTAssertEqual(project.scripts, ["build", "dev", "test"])
        XCTAssertTrue(project.hasIndexHTML)
        XCTAssertEqual(project.assetFolders, ["public/assets"])
        XCTAssertTrue(project.hasNodeModules)
        XCTAssertTrue(project.issues.isEmpty)
    }

    func testMissingPackageJSONIsReportedNotCrashed() throws {
        let dir = try TempDirectory()
        let project = GameProjectDetector.inspect(folder: dir.url.path)
        XCTAssertTrue(project.issues.contains { $0.contains("No package.json") })
        XCTAssertTrue(project.engines.isEmpty)
    }

    func testMissingEngineAndNodeModulesAreFlagged() throws {
        let dir = try TempDirectory()
        try dir.file("package.json", contents: #"{"name":"plain","scripts":{"build":"tsc"}}"#)
        let project = GameProjectDetector.inspect(folder: dir.url.path)
        XCTAssertTrue(project.issues.contains { $0.contains("No game engine") })
        XCTAssertTrue(project.issues.contains { $0.contains("not installed") })
        XCTAssertTrue(project.issues.contains { $0.contains("index.html") })
    }

    func testOnlySafeScriptsAreRunnable() {
        XCTAssertEqual(GameProjectRunner.runnable(["dev", "build", "test", "start"]), ["build", "test"])
    }

    func testRunnerRefusesScriptsOutsideTheAllowList() throws {
        let dir = try TempDirectory()
        try dir.file("package.json", contents: packageJSON)
        let project = GameProjectDetector.inspect(folder: dir.url.path)
        XCTAssertThrowsError(try GameProjectRunner.run(project: project, script: "dev", npmPath: "/usr/bin/npm"))
    }
}

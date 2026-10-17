import XCTest
@testable import CodeOSCore

final class WorkspaceLauncherTests: XCTestCase {
    func testUsesEditorWhenConfigured() {
        let ws = Workspace(name: "EvolvED", projectPath: "/Users/me/evolved", editorBundleID: "com.example.editor",
                           documentationURLs: ["https://docs.example"], supportingAppBundleIDs: ["com.example.tool"])
        let workflow = WorkspaceLauncher.workflow(for: ws)
        XCTAssertEqual(workflow.id, ws.id)
        XCTAssertEqual(workflow.actions, [
            .openFolderInApp(bundleID: "com.example.editor", path: "/Users/me/evolved"),
            .openTerminal(path: "/Users/me/evolved"),
            .openURL("https://docs.example"),
            .launchApp(bundleID: "com.example.tool")
        ])
        XCTAssertTrue(Validation.problems(in: workflow).isEmpty)
    }

    func testFallsBackToFolderWithoutEditor() {
        let ws = Workspace(name: "Plain", projectPath: "/tmp/plain")
        XCTAssertEqual(WorkspaceLauncher.workflow(for: ws).actions.first, .openFolder(path: "/tmp/plain"))
    }
}

import XCTest
@testable import CodeOSCore

final class WorkflowActionTests: XCTestCase {
    func testAppearanceStepIsAlwaysValid() {
        let workflow = Workflow(name: "Night", actions: [.setSystemAppearance(dark: true)])
        XCTAssertTrue(Validation.problems(in: workflow).isEmpty)
    }

    func testCommandMustUseAbsoluteExecutable() {
        let bad = Workflow(name: "Build", actions: [.runCommand(executable: "swift", arguments: ["build"], workingDirectory: nil)])
        XCTAssertEqual(Validation.problems(in: bad).count, 1)

        let good = Workflow(name: "Build", actions: [.runCommand(executable: "/usr/bin/swift", arguments: ["build"], workingDirectory: "/tmp")])
        XCTAssertTrue(Validation.problems(in: good).isEmpty)
    }

    func testCommandWorkingFolderMustBeAbsolute() {
        let workflow = Workflow(name: "Build", actions: [.runCommand(executable: "/bin/ls", arguments: [], workingDirectory: "relative")])
        XCTAssertEqual(Validation.problems(in: workflow).count, 1)
    }

    func testRunsCommandsDetectsCommandSteps() {
        let plain = Workflow(name: "Plain", actions: [.openURL("https://example.com")])
        let commands = Workflow(name: "Cmd", actions: [.runCommand(executable: "/bin/ls", arguments: [], workingDirectory: nil)])
        XCTAssertFalse(plain.runsCommands)
        XCTAssertTrue(commands.runsCommands)
    }

    func testTitlesAreReadable() {
        XCTAssertEqual(WorkflowAction.setSystemAppearance(dark: true).title, "Switch macOS to Dark appearance")
        XCTAssertEqual(WorkflowAction.runCommand(executable: "/usr/bin/swift", arguments: ["test"], workingDirectory: nil).title,
                       "Run /usr/bin/swift test")
    }

    func testNewActionsRoundTripThroughJSON() throws {
        let original = Workflow(name: "All", actions: [
            .setSystemAppearance(dark: false),
            .runCommand(executable: "/bin/echo", arguments: ["hi"], workingDirectory: "/tmp")
        ])
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(Workflow.self, from: data), original)
    }
}

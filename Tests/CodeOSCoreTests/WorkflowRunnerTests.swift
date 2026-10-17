import XCTest
@testable import CodeOSCore

private enum FakeError: Error, LocalizedError {
    case boom
    var errorDescription: String? { "boom" }
}

private struct FakeExecutor: ActionExecutor {
    let failing: Set<String>
    func execute(_ action: WorkflowAction) async throws -> String {
        if failing.contains(action.title) { throw FakeError.boom }
        return "done: \(action.title)"
    }
}

final class WorkflowRunnerTests: XCTestCase {
    func testContinuesAfterAFailedStep() async {
        let workflow = Workflow(name: "Mixed", actions: [
            .openURL("https://a.example"),
            .openURL("https://b.example"),
            .openURL("https://c.example")
        ])
        let failing: Set<String> = [WorkflowAction.openURL("https://b.example").title]
        let report = await WorkflowRunner.run(workflow, using: FakeExecutor(failing: failing))

        XCTAssertEqual(report.steps.count, 3)
        XCTAssertTrue(report.steps[0].isSuccess)
        XCTAssertTrue(report.steps[1].isFailure)
        XCTAssertTrue(report.steps[2].isSuccess)
        XCTAssertEqual(report.failureCount, 1)
        XCTAssertFalse(report.allSucceeded)
    }

    func testInvalidWorkflowIsNotExecuted() async {
        let workflow = Workflow(name: "Bad", actions: [.openURL("ftp://nope")])
        let report = await WorkflowRunner.run(workflow, using: FakeExecutor(failing: []))
        XCTAssertFalse(report.problems.isEmpty)
        XCTAssertEqual(report.steps.count, 1)
        XCTAssertFalse(report.steps[0].isSuccess)
        XCTAssertFalse(report.steps[0].isFailure)
    }

    func testAllSucceedReportsSuccess() async {
        let workflow = Workflow(name: "Ok", actions: [.openURL("https://a.example")])
        let report = await WorkflowRunner.run(workflow, using: FakeExecutor(failing: []))
        XCTAssertTrue(report.allSucceeded)
    }
}

import Foundation

/// Performs one workflow action. The app supplies the real implementation;
/// tests supply fakes.
public protocol ActionExecutor {
    /// Returns a short summary on success, or throws with the reason.
    func execute(_ action: WorkflowAction) async throws -> String
}

public enum StepResult: Equatable {
    case succeeded(summary: String)
    case failed(message: String)
    case skipped(reason: String)

    public var isSuccess: Bool {
        if case .succeeded = self { return true }
        return false
    }

    public var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    public var text: String {
        switch self {
        case .succeeded(let summary): return summary
        case .failed(let message): return message
        case .skipped(let reason): return reason
        }
    }
}

public struct WorkflowRunReport: Equatable {
    public let workflowName: String
    /// Non-empty when the workflow was rejected before running.
    public let problems: [String]
    /// One entry per action, in the same order as the workflow.
    public let steps: [StepResult]

    public var allSucceeded: Bool {
        problems.isEmpty && steps.allSatisfy { $0.isSuccess }
    }

    public var failureCount: Int {
        steps.filter { $0.isFailure }.count
    }
}

public enum WorkflowRunner {
    /// Runs every step in order. A failed step does not stop independent later steps.
    /// Cancelling the surrounding task skips the remaining steps.
    public static func run(_ workflow: Workflow, using executor: ActionExecutor) async -> WorkflowRunReport {
        let problems = Validation.problems(in: workflow)
        guard problems.isEmpty else {
            return WorkflowRunReport(
                workflowName: workflow.name,
                problems: problems,
                steps: workflow.actions.map { _ in .skipped(reason: "Not run: the workflow is invalid.") }
            )
        }
        var steps: [StepResult] = []
        for action in workflow.actions {
            if Task.isCancelled {
                steps.append(.skipped(reason: "Cancelled before this step ran."))
                continue
            }
            do {
                steps.append(.succeeded(summary: try await executor.execute(action)))
            } catch {
                steps.append(.failed(message: error.localizedDescription))
            }
        }
        return WorkflowRunReport(workflowName: workflow.name, problems: [], steps: steps)
    }
}

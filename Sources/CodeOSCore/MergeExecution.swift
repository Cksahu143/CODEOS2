import Foundation

public enum MergeOutcome: Equatable {
    case merged(output: String)
    case conflicts(output: String)
    case refused(reason: String)
}

/// Performs a merge only when it is safe to start. Git does the merge; CodeOS decides when to run it.
public enum MergeExecution {
    /// Lines from `git status --porcelain` that would block or be carried into a merge.
    public static func blockingChanges(_ entries: [GitStatus.Entry]) -> [String] {
        entries.filter { $0.indexCode != "?" }.map(\.path)
    }

    public static func merge(branch: String, into repository: String) throws -> MergeOutcome {
        guard MergePreview.isSafeBranchName(branch) else {
            return .refused(reason: "That branch name is not allowed.")
        }
        let status = try GitStudio.status(in: repository)
        let changes = blockingChanges(status.entries)
        if !changes.isEmpty {
            return .refused(reason: "Commit or stash these changes first:\n" + changes.prefix(20).joined(separator: "\n"))
        }
        let result = try GitStudio.run(["merge", "--no-edit", branch], in: repository)
        let output = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        if result.succeeded {
            return .merged(output: output)
        }
        if output.contains("CONFLICT") {
            return .conflicts(output: output)
        }
        return .refused(reason: output.isEmpty ? "Git could not merge \(branch)." : output)
    }
}

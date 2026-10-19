import Foundation

public struct RepositoryFinding: Identifiable, Equatable {
    public var id: String { title }
    public let severity: FindingSeverity
    public let title: String
    public let detail: String
    /// The command that would resolve this. Shown for the user to copy; CodeOS never runs it.
    public let suggestedCommand: String?
}

/// Explains what state a repository is in. Every check only reads Git's own files and status.
public enum RepositoryStateExplainer {
    public static func explain(repository: String) throws -> [RepositoryFinding] {
        let directory = try GitStudio.run(["rev-parse", "--git-dir"], in: repository)
        guard directory.succeeded else {
            throw GitError.failed(directory.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let raw = directory.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let gitDirectory = raw.hasPrefix("/") ? raw : (repository as NSString).appendingPathComponent(raw)
        let branch = try GitStudio.run(["symbolic-ref", "-q", "HEAD"], in: repository)
        let commit = try GitStudio.run(["rev-parse", "--verify", "-q", "HEAD"], in: repository)
        let status = try GitStudio.status(in: repository)
        return findings(
            gitDirectory: gitDirectory,
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            headIsBranch: branch.succeeded,
            hasCommits: commit.succeeded,
            entries: status.entries)
    }

    /// The pure rules, separated so they can be tested without a repository.
    public static func findings(
        gitDirectory: String,
        fileExists: (String) -> Bool,
        headIsBranch: Bool,
        hasCommits: Bool,
        entries: [GitStatus.Entry]
    ) -> [RepositoryFinding] {
        func exists(_ name: String) -> Bool {
            fileExists((gitDirectory as NSString).appendingPathComponent(name))
        }
        var result: [RepositoryFinding] = []

        if !hasCommits {
            result.append(RepositoryFinding(
                severity: .info, title: "No commits yet",
                detail: "Make a first commit to start the history.", suggestedCommand: nil))
        }
        if hasCommits && !headIsBranch {
            result.append(RepositoryFinding(
                severity: .warning, title: "Detached HEAD",
                detail: "You are not on a branch. Commits made here are easy to lose when you switch away. Create a branch to keep them.",
                suggestedCommand: "git switch -c <new-branch-name>"))
        }
        if exists("MERGE_HEAD") {
            result.append(RepositoryFinding(
                severity: .warning, title: "Merge in progress",
                detail: "Resolve the conflicts, stage the files, and commit to finish. Or cancel the merge.",
                suggestedCommand: "git merge --abort"))
        }
        if exists("rebase-merge") || exists("rebase-apply") {
            result.append(RepositoryFinding(
                severity: .warning, title: "Rebase in progress",
                detail: "Fix the current step, stage it, then continue. Or abort to return to where the rebase started.",
                suggestedCommand: "git rebase --continue   (or git rebase --abort)"))
        }
        if exists("CHERRY_PICK_HEAD") {
            result.append(RepositoryFinding(
                severity: .warning, title: "Cherry-pick in progress",
                detail: "Finish the pick after resolving conflicts, or cancel it.",
                suggestedCommand: "git cherry-pick --abort"))
        }
        if exists("REVERT_HEAD") {
            result.append(RepositoryFinding(
                severity: .warning, title: "Revert in progress",
                detail: "Finish the revert after resolving conflicts, or cancel it.",
                suggestedCommand: "git revert --abort"))
        }
        if exists("BISECT_LOG") {
            result.append(RepositoryFinding(
                severity: .info, title: "Bisect in progress",
                detail: "The repository is in a bisect search. Reset it when you have found the commit.",
                suggestedCommand: "git bisect reset"))
        }

        let conflicted = entries.filter(isConflict)
        if !conflicted.isEmpty {
            result.append(RepositoryFinding(
                severity: .error, title: "\(conflicted.count) file(s) have conflicts",
                detail: "Edit each file to choose the right lines, then stage it. Conflicts block commits until they are resolved.",
                suggestedCommand: "git add <file>"))
        }
        let unstaged = entries.filter { $0.worktreeCode != " " && $0.worktreeCode != "?" && !isConflict($0) }
        if !unstaged.isEmpty {
            result.append(RepositoryFinding(
                severity: .info, title: "\(unstaged.count) file(s) changed but not staged",
                detail: "Switching branches is refused if these files differ between branches. Commit or stash them first.",
                suggestedCommand: "git stash push"))
        }
        let untracked = entries.filter { $0.indexCode == "?" }
        if !untracked.isEmpty {
            result.append(RepositoryFinding(
                severity: .info, title: "\(untracked.count) untracked file(s)",
                detail: "New files that Git does not track yet. Stage them to include them in a commit.",
                suggestedCommand: nil))
        }
        if result.isEmpty {
            result.append(RepositoryFinding(
                severity: .ok, title: "Repository is clean",
                detail: "No problems found.", suggestedCommand: nil))
        }
        return result
    }

    static func isConflict(_ entry: GitStatus.Entry) -> Bool {
        let pair = [entry.indexCode, entry.worktreeCode]
        return pair.contains("U")
            || (entry.indexCode == "A" && entry.worktreeCode == "A")
            || (entry.indexCode == "D" && entry.worktreeCode == "D")
    }
}

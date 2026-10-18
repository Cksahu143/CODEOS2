import Foundation

public enum GitError: Error, LocalizedError, Equatable {
    case notARepository(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notARepository(let path): return "“\(path)” is not a Git repository."
        case .failed(let message): return message.isEmpty ? "Git reported an error." : message
        }
    }
}

public struct GitCommit: Identifiable, Equatable {
    public var id: String { hash }
    public let hash: String
    public let parents: [String]
    /// Branch, tag, and HEAD labels from `git log %D`.
    public let refs: [String]
    public let author: String
    public let date: String
    public let subject: String

    public var shortHash: String { String(hash.prefix(7)) }
}

/// One row of the graph. Lanes are columns; `topLanes` and `bottomLanes` hold the hash each
/// column is waiting for above and below this commit.
public struct GitGraphRow: Identifiable, Equatable {
    public var id: String { commit.hash }
    public let commit: GitCommit
    public let lane: Int
    public let topLanes: [String?]
    public let bottomLanes: [String?]
    /// Columns this commit connects to in the row below, first parent first.
    public let parentLanes: [Int]

    public var laneCount: Int { max(topLanes.count, bottomLanes.count, lane + 1) }
}

public struct ChangedFile: Identifiable, Equatable {
    public var id: String { path }
    /// Git's status letter: A, M, D, R100, and so on.
    public let status: String
    public let path: String
}

public enum GitGraph {
    static let format = "%H%x1f%P%x1f%D%x1f%an%x1f%aI%x1f%s%x1e"

    /// Loads recent history from every branch and tag, in Git's date order.
    public static func load(repository: String, limit: Int = 1000) throws -> [GitGraphRow] {
        let probe = try ProcessRunner.run(
            executable: GitTool.resolved ?? "/usr/bin/git",
            arguments: ["rev-parse", "--is-inside-work-tree"],
            workingDirectory: repository,
            timeout: 10)
        let probeText = probe.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard probe.succeeded, probeText == "true" else {
            if probe.stderr.lowercased().contains("not a git repository") {
                throw GitError.notARepository(repository)
            }
            let detail = probe.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitError.failed(detail.isEmpty ? "Git could not read this folder." : detail)
        }
        let result = try ProcessRunner.run(
            executable: GitTool.resolved ?? "/usr/bin/git",
            arguments: ["log", "--all", "--date-order", "--max-count=\(limit)", "--format=\(format)"],
            workingDirectory: repository,
            timeout: 30)
        if !result.succeeded {
            if result.stderr.contains("does not have any commits") { return [] }
            throw GitError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return layout(parse(result.stdout))
    }

    /// Parses the records produced by `format`. Fields are separated by 0x1f, records by 0x1e.
    public static func parse(_ output: String) -> [GitCommit] {
        var commits: [GitCommit] = []
        for record in output.split(separator: "\u{1e}") {
            let fields = record
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\u{1f}", omittingEmptySubsequences: false)
                .map { String($0) }
            guard fields.count == 6, !fields[0].isEmpty else { continue }
            let parents = fields[1].split(separator: " ").map { String($0) }
            let refs = fields[2].split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            commits.append(GitCommit(hash: fields[0], parents: parents, refs: refs,
                                     author: fields[3], date: fields[4], subject: fields[5]))
        }
        return commits
    }

    /// Assigns each commit a lane. Input is newest first, as `git log` prints it.
    public static func layout(_ commits: [GitCommit]) -> [GitGraphRow] {
        var lanes: [String?] = []
        var rows: [GitGraphRow] = []
        for commit in commits {
            let top = lanes
            // Lanes waiting for this commit end here. The first one hosts the commit.
            let waiting = lanes.indices.filter { lanes[$0] == commit.hash }
            let lane = waiting.first ?? freeSlot(&lanes)
            for index in waiting { lanes[index] = nil }
            var parentLanes: [Int] = []
            for (position, parent) in commit.parents.enumerated() {
                if let existing = lanes.firstIndex(of: parent) {
                    parentLanes.append(existing)
                } else if position == 0 {
                    lanes[lane] = parent
                    parentLanes.append(lane)
                } else {
                    let slot = freeSlot(&lanes)
                    lanes[slot] = parent
                    parentLanes.append(slot)
                }
            }
            while let last = lanes.last, last == nil {
                lanes.removeLast()
            }
            rows.append(GitGraphRow(commit: commit, lane: lane, topLanes: top,
                                    bottomLanes: lanes, parentLanes: parentLanes))
        }
        return rows
    }

    private static func freeSlot(_ lanes: inout [String?]) -> Int {
        if let index = lanes.firstIndex(where: { $0 == nil }) { return index }
        lanes.append(nil)
        return lanes.count - 1
    }
}

public enum GitInspector {
    public static func isValidHash(_ text: String) -> Bool {
        (7...40).contains(text.count) && text.allSatisfy { $0.isHexDigit }
    }

    public static func isRepository(_ path: String) -> Bool {
        guard let result = try? ProcessRunner.run(
                executable: GitTool.resolved ?? "/usr/bin/git",
                arguments: ["rev-parse", "--is-inside-work-tree"],
                workingDirectory: path,
                timeout: 5) else { return false }
        return result.succeeded && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    public static func changedFiles(repository: String, commit: String) throws -> [ChangedFile] {
        guard isValidHash(commit) else { throw GitError.failed("That is not a valid commit.") }
        let result = try ProcessRunner.run(
            executable: GitTool.resolved ?? "/usr/bin/git",
            arguments: ["show", "--format=", "--name-status", commit],
            workingDirectory: repository,
            timeout: 30)
        guard result.succeeded else {
            throw GitError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parseNameStatus(result.stdout)
    }

    /// Parses `--name-status` lines. Renames show "R100<tab>old<tab>new"; the new name is kept.
    public static func parseNameStatus(_ output: String) -> [ChangedFile] {
        output.split(separator: "\n").compactMap { line -> ChangedFile? in
            let parts = line.split(separator: "\t").map { String($0) }
            guard parts.count >= 2, let status = parts.first, let path = parts.last else { return nil }
            return ChangedFile(status: status, path: path)
        }
    }

    /// The patch for one commit, optionally limited to one file. Binary files get no text diff.
    public static func diff(repository: String, commit: String, path: String?) throws -> String {
        guard isValidHash(commit) else { throw GitError.failed("That is not a valid commit.") }
        var arguments = ["show", "--format=", "--patch", commit]
        if let path { arguments += ["--", path] }
        let result = try ProcessRunner.run(
            executable: GitTool.resolved ?? "/usr/bin/git",
            arguments: arguments,
            workingDirectory: repository,
            timeout: 30)
        guard result.succeeded else {
            throw GitError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if result.stdout.contains("Binary files") {
            return "Binary file: no text diff is shown."
        }
        return String(result.stdout.prefix(300_000))
    }
}

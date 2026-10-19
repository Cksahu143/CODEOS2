import Foundation

public enum DiffLineKind: Equatable {
    case context, added, removed, hunk, header
}

public struct DiffLine: Equatable {
    public let kind: DiffLineKind
    public let text: String
}

public struct DiffFile: Identifiable, Equatable {
    public var id: String { path }
    public let path: String
    public let lines: [DiffLine]
    public let additions: Int
    public let deletions: Int
    public let isBinary: Bool
}

public struct CommitSummary: Identifiable, Equatable {
    public var id: String { hash }
    public let hash: String
    public let shortHash: String
    public let date: String
    public let subject: String
}

/// Parses Git's unified diff format. It only groups and labels lines; it never changes their text.
public enum DiffParser {
    public static func parse(_ text: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var path: String?
        var lines: [DiffLine] = []
        var binary = false

        func finishFile() {
            if let path {
                let additions = lines.filter { $0.kind == .added }.count
                let deletions = lines.filter { $0.kind == .removed }.count
                files.append(DiffFile(path: path, lines: lines, additions: additions,
                                      deletions: deletions, isBinary: binary))
            }
            lines = []
            binary = false
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("diff --git ") {
                finishFile()
                path = pathFromHeader(line)
                lines.append(DiffLine(kind: .header, text: line))
            } else if line.hasPrefix("Binary files ") || line == "GIT binary patch" {
                binary = true
                lines.append(DiffLine(kind: .header, text: line))
            } else if line.hasPrefix("@@") {
                lines.append(DiffLine(kind: .hunk, text: line))
            } else if line.hasPrefix("+++") || line.hasPrefix("---") {
                lines.append(DiffLine(kind: .header, text: line))
            } else if line.hasPrefix("+") {
                lines.append(DiffLine(kind: .added, text: line))
            } else if line.hasPrefix("-") {
                lines.append(DiffLine(kind: .removed, text: line))
            } else if line.hasPrefix(" ") {
                lines.append(DiffLine(kind: .context, text: line))
            } else {
                lines.append(DiffLine(kind: .header, text: line))
            }
        }
        finishFile()
        return files
    }

    /// "diff --git a/old b/new" -> "new"
    static func pathFromHeader(_ line: String) -> String {
        if let range = line.range(of: " b/", options: .backwards) {
            return String(line[range.upperBound...])
        }
        return line
    }
}

public enum GitDiffReader {
    public static func workingTree(repository: String) throws -> String {
        let result = try GitStudio.run(["diff", "--no-color"], in: repository)
        guard result.succeeded else {
            throw GitError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(result.stdout.prefix(300_000))
    }

    public static func commit(repository: String, hash: String) throws -> String {
        guard GitInspector.isValidHash(hash) else {
            throw GitError.failed("That is not a valid commit.")
        }
        let result = try GitStudio.run(["show", "--no-color", "--format=", "--patch", hash], in: repository)
        guard result.succeeded else {
            throw GitError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(result.stdout.prefix(300_000))
    }

    public static func recentCommits(repository: String, limit: Int = 50) throws -> [CommitSummary] {
        let result = try GitStudio.run(
            ["log", "-n", String(limit), "--date=short", "--format=%H%x1f%h%x1f%ad%x1f%s"],
            in: repository)
        guard result.succeeded else {
            throw GitError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var commits: [CommitSummary] = []
        for line in result.stdout.split(separator: "\n") {
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map { String($0) }
            guard fields.count == 4 else { continue }
            commits.append(CommitSummary(hash: fields[0], shortHash: fields[1], date: fields[2], subject: fields[3]))
        }
        return commits
    }
}

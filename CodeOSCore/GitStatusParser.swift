import Foundation

public struct GitStatus: Equatable {
    public struct Entry: Equatable {
        public let indexCode: Character
        public let worktreeCode: Character
        public let path: String
    }

    public var branch: String?
    public var aheadCount: Int
    public var behindCount: Int
    public var entries: [Entry]

    public var isClean: Bool { entries.isEmpty }
    public var untrackedCount: Int { entries.filter { $0.indexCode == "?" }.count }
    public var changedCount: Int { entries.count - untrackedCount }
}

/// Parses `git status --porcelain=v1 --branch`. Read-only analysis only.
public enum GitStatusParser {
    public static func parse(_ output: String) -> GitStatus {
        var status = GitStatus(branch: nil, aheadCount: 0, behindCount: 0, entries: [])
        for line in output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if line.hasPrefix("## ") {
                parseBranchLine(String(line.dropFirst(3)), into: &status)
                continue
            }
            let chars = Array(line)
            guard chars.count >= 4 else { continue }
            var path = String(chars[3...])
            if let arrow = path.range(of: " -> ") {
                path = String(path[arrow.upperBound...])   // renamed: keep destination
            }
            status.entries.append(GitStatus.Entry(indexCode: chars[0], worktreeCode: chars[1], path: path))
        }
        return status
    }

    private static func parseBranchLine(_ text: String, into status: inout GitStatus) {
        var namePart = text
        if let bracket = text.range(of: " [") {
            let counts = text[bracket.upperBound...].dropLast()
            for item in counts.split(separator: ",") {
                let parts = item.trimmingCharacters(in: .whitespaces).split(separator: " ")
                guard parts.count == 2, let value = Int(parts[1]) else { continue }
                if parts[0] == "ahead" { status.aheadCount = value }
                if parts[0] == "behind" { status.behindCount = value }
            }
            namePart = String(text[..<bracket.lowerBound])
        }
        if let dots = namePart.range(of: "...") {
            namePart = String(namePart[..<dots.lowerBound])
        }
        let noCommitsPrefix = "No commits yet on "
        status.branch = namePart.hasPrefix(noCommitsPrefix)
            ? String(namePart.dropFirst(noCommitsPrefix.count))
            : namePart
    }
}

import Foundation

/// How far two branches have diverged. `onlyInA` counts commits on A that B lacks, and vice versa.
public struct BranchDivergence: Equatable {
    public let onlyInA: Int
    public let onlyInB: Int
}

public struct MergePreviewResult: Equatable {
    public let base: String?
    public let divergence: BranchDivergence
    public let changedOnA: [String]
    public let changedOnB: [String]
    /// Files both branches changed. A merge may conflict here.
    public let changedOnBoth: [String]
    /// Files that would conflict, or nil when Git is too old to check.
    public let predictedConflicts: [String]?
    public let note: String?
}

/// Previews a merge without changing the working tree, the index, or any branch.
/// `git merge-tree --write-tree` writes objects into the object database only.
public enum MergePreview {
    public static func gitVersion(_ text: String) -> (major: Int, minor: Int)? {
        // "git version 2.39.5 (Apple Git-154)"
        guard let word = text.split(separator: " ").dropFirst(2).first else { return nil }
        let parts = word.split(separator: ".")
        guard parts.count >= 2, let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
        return (major, minor)
    }

    public static func supportsMergeTree(_ version: (major: Int, minor: Int)) -> Bool {
        version.major > 2 || (version.major == 2 && version.minor >= 38)
    }

    /// "2\t3" from `rev-list --left-right --count A...B`.
    public static func parseCounts(_ text: String) -> BranchDivergence? {
        let parts = text.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "\n" })
        guard parts.count == 2, let left = Int(parts[0]), let right = Int(parts[1]) else { return nil }
        return BranchDivergence(onlyInA: left, onlyInB: right)
    }

    public static func parseNameList(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Exit 0 means a clean merge. Exit 1 means conflicts, listed after the tree id, before a blank line.
    public static func parseMergeTree(output: String, exitCode: Int32) -> [String]? {
        switch exitCode {
        case 0:
            return []
        case 1:
            var names: [String] = []
            for line in output.split(separator: "\n", omittingEmptySubsequences: false).dropFirst() {
                let name = line.trimmingCharacters(in: .whitespaces)
                if name.isEmpty { break }
                names.append(name)
            }
            return names
        default:
            return nil
        }
    }

    /// A branch name Git accepts and that cannot be read as an option.
    public static func isSafeBranchName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("-") && !name.contains(" ") && !name.contains("..")
    }

    public static func preview(repository: String, branchA: String, branchB: String) throws -> MergePreviewResult {
        guard isSafeBranchName(branchA), isSafeBranchName(branchB) else {
            throw GitError.failed("That branch name is not allowed.")
        }
        let counts = try GitStudio.run(["rev-list", "--left-right", "--count", "\(branchA)...\(branchB)"], in: repository)
        guard counts.succeeded, let divergence = parseCounts(counts.stdout) else {
            throw GitError.failed(counts.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let baseResult = try GitStudio.run(["merge-base", branchA, branchB], in: repository)
        let base = baseResult.succeeded ? baseResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil

        var changedA: [String] = []
        var changedB: [String] = []
        if let base, !base.isEmpty {
            changedA = parseNameList(try GitStudio.run(["diff", "--name-only", base, branchA], in: repository).stdout)
            changedB = parseNameList(try GitStudio.run(["diff", "--name-only", base, branchB], in: repository).stdout)
        }
        let both = Array(Set(changedA).intersection(changedB)).sorted()

        var conflicts: [String]? = nil
        var note: String? = nil
        let versionText = try GitStudio.run(["--version"], in: repository).stdout
        if let version = gitVersion(versionText), supportsMergeTree(version) {
            let check = try GitStudio.run(["merge-tree", "--write-tree", "--name-only", branchA, branchB], in: repository)
            conflicts = parseMergeTree(output: check.stdout, exitCode: check.exitCode)
            if conflicts == nil {
                note = "Git could not check for conflicts: " + check.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            note = "Conflict check needs Git 2.38 or newer. Update Git with MacPorts or Homebrew to enable it."
        }
        if base == nil || base?.isEmpty == true {
            note = "These branches share no history, so a merge may not be possible."
        }
        return MergePreviewResult(
            base: base,
            divergence: divergence,
            changedOnA: changedA,
            changedOnB: changedB,
            changedOnBoth: both,
            predictedConflicts: conflicts,
            note: note)
    }
}

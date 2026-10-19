import Foundation

public struct BranchInfo: Identifiable, Equatable {
    public var id: String { (isRemote ? "remote:" : "local:") + name }
    public let name: String
    public let isRemote: Bool
    public let isCurrent: Bool
    /// The remote branch this one tracks, such as origin/main. Nil when it tracks nothing.
    public let upstream: String?
    public let ahead: Int
    public let behind: Int
    public let lastCommitDate: String
    public let lastCommitSubject: String
}

/// Lists and changes branches. Create, switch, and delete are the only writes, and delete is always safe:
/// `git branch -d` refuses to delete a branch that is not fully merged.
public enum BranchManager {
    static let format = "%(HEAD)%09%(refname:short)%09%(upstream:short)%09%(committerdate:short)%09%(subject)"

    public static func list(repository: String) throws -> [BranchInfo] {
        let local = try GitStudio.run(["for-each-ref", "--format=\(format)", "refs/heads"], in: repository)
        guard local.succeeded else {
            throw GitError.failed(local.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var result: [BranchInfo] = []
        for info in parseRefs(local.stdout, remote: false) {
            guard let upstream = info.upstream else {
                result.append(info)
                continue
            }
            var ahead = 0
            var behind = 0
            let counts = try GitStudio.run(["rev-list", "--left-right", "--count", "\(info.name)...\(upstream)"], in: repository)
            if counts.succeeded, let divergence = MergePreview.parseCounts(counts.stdout) {
                ahead = divergence.onlyInA
                behind = divergence.onlyInB
            }
            result.append(BranchInfo(name: info.name, isRemote: false, isCurrent: info.isCurrent,
                                     upstream: upstream, ahead: ahead, behind: behind,
                                     lastCommitDate: info.lastCommitDate, lastCommitSubject: info.lastCommitSubject))
        }
        let remote = try GitStudio.run(["for-each-ref", "--format=\(format)", "refs/remotes"], in: repository)
        if remote.succeeded {
            result += parseRefs(remote.stdout, remote: true)
        }
        return result
    }

    /// Parses lines written with `format`. Fields are tab-separated; the subject may hold anything after the fourth tab.
    public static func parseRefs(_ output: String, remote: Bool) -> [BranchInfo] {
        var branches: [BranchInfo] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map { String($0) }
            guard fields.count == 5 else { continue }
            let name = fields[1]
            if name.isEmpty || name.hasSuffix("/HEAD") { continue }
            branches.append(BranchInfo(
                name: name,
                isRemote: remote,
                isCurrent: fields[0] == "*",
                upstream: fields[2].isEmpty ? nil : fields[2],
                ahead: 0,
                behind: 0,
                lastCommitDate: fields[3],
                lastCommitSubject: fields[4]))
        }
        return branches
    }

    /// Asks Git whether the name is allowed, using its own rules.
    public static func isValidNewName(_ name: String, in repository: String) throws -> Bool {
        guard MergePreview.isSafeBranchName(name) else { return false }
        return try GitStudio.run(["check-ref-format", "--branch", name], in: repository).succeeded
    }

    public static func create(_ name: String, in repository: String) throws -> ProcessResult {
        guard try isValidNewName(name, in: repository) else {
            throw GitError.failed("Git does not allow that branch name.")
        }
        return try GitStudio.run(["switch", "-c", name], in: repository)
    }

    public static func switchTo(_ name: String, in repository: String) throws -> ProcessResult {
        guard MergePreview.isSafeBranchName(name) else {
            throw GitError.failed("That branch name is not allowed.")
        }
        return try GitStudio.run(["switch", name], in: repository)
    }

    public static func deleteMerged(_ name: String, in repository: String) throws -> ProcessResult {
        guard MergePreview.isSafeBranchName(name) else {
            throw GitError.failed("That branch name is not allowed.")
        }
        return try GitStudio.run(["branch", "-d", name], in: repository)
    }
}

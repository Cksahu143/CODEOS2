import Foundation

/// How much a Git command can change. The console uses this to decide what to ask first.
public enum GitRisk: Equatable {
    /// Only reads the repository. Runs immediately.
    case readOnly
    /// Changes the repository in a normal, recoverable way. Asks first.
    case changesState
    /// Can lose work or rewrite history. Asks with a warning.
    case destructive
    /// Not allowed here, with the reason.
    case blocked(String)
}

public enum GitCommandPolicy {
    static let readOnlyCommands: Set<String> = [
        "status", "log", "show", "diff", "rev-parse", "ls-files", "blame", "describe", "shortlog", "version",
    ]
    static let destructiveCommands: Set<String> = [
        "reset", "clean", "push", "rebase", "gc", "prune", "filter-branch", "update-ref", "replace", "revert",
    ]
    static let destructiveFlags: Set<String> = [
        "--hard", "--force", "-f", "--force-with-lease", "-D", "-d", "--delete", "--prune", "-x", "-X",
    ]
    static let forbiddenFlags: Set<String> = ["-c", "--git-dir", "--work-tree", "--exec-path", "--namespace"]

    public static func classify(_ arguments: [String]) -> GitRisk {
        guard let command = arguments.first, !command.hasPrefix("-") else {
            return .blocked("Start with a Git command, such as status or log.")
        }
        if arguments.contains(where: { forbiddenFlags.contains($0) || $0.hasPrefix("--git-dir") || $0.hasPrefix("--work-tree") }) {
            return .blocked("Changing Git's configuration or repository location is not allowed here.")
        }
        if arguments.contains(where: { $0.hasPrefix("--exec") }) {
            return .blocked("Commands that run other programs are not allowed here.")
        }
        if destructiveCommands.contains(command) || arguments.contains(where: { destructiveFlags.contains($0) }) {
            return .destructive
        }
        if command == "checkout" && arguments.contains("--") {
            return .destructive
        }
        if readOnlyCommands.contains(command) {
            return .readOnly
        }
        return .changesState
    }
}

public enum GitCommandLine {
    /// Splits a typed command like: log --oneline "my branch". Quotes group words. Returns nil when
    /// quotes are unbalanced. No shell expansion happens.
    public static func split(_ text: String) -> [String]? {
        var arguments: [String] = []
        var current = ""
        var quote: Character? = nil
        var inToken = false
        for character in text {
            if let open = quote {
                if character == open {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
                inToken = true
            } else if character.isWhitespace {
                if inToken {
                    arguments.append(current)
                    current = ""
                    inToken = false
                }
            } else {
                current.append(character)
                inToken = true
            }
        }
        if quote != nil { return nil }
        if inToken { arguments.append(current) }
        return arguments
    }
}

public enum GitStudio {
    public static func run(_ arguments: [String], in repository: String, timeout: TimeInterval = 120) throws -> ProcessResult {
        guard let git = GitTool.resolved else {
            throw GitError.failed("Git was not found. Install it with MacPorts, Homebrew, or the Command Line Tools.")
        }
        return try ProcessRunner.run(executable: git, arguments: arguments, workingDirectory: repository, timeout: timeout)
    }

    /// A path inside the repository: relative, no "..", and not starting with "-".
    public static func isSafePath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && !path.hasPrefix("-")
            && !path.split(separator: "/").contains("..")
            && !path.contains("\0")
    }

    public static func status(in repository: String) throws -> GitStatus {
        let result = try run(["status", "--porcelain=v1", "--branch"], in: repository)
        guard result.succeeded else {
            throw GitError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return GitStatusParser.parse(result.stdout)
    }

    public static func stage(_ paths: [String], in repository: String) throws -> ProcessResult {
        guard !paths.isEmpty, paths.allSatisfy(isSafePath) else {
            throw GitError.failed("Only files inside the repository can be staged.")
        }
        return try run(["add", "--"] + paths, in: repository)
    }

    public static func stageEverything(in repository: String) throws -> ProcessResult {
        try run(["add", "-A"], in: repository)
    }

    public static func unstage(_ paths: [String], in repository: String) throws -> ProcessResult {
        guard !paths.isEmpty, paths.allSatisfy(isSafePath) else {
            throw GitError.failed("Only files inside the repository can be unstaged.")
        }
        return try run(["restore", "--staged", "--"] + paths, in: repository)
    }

    /// The message is one argument. It is never interpreted by a shell.
    public static func commit(message: String, in repository: String) throws -> ProcessResult {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitError.failed("Write a commit message first.") }
        return try run(["commit", "-m", trimmed], in: repository)
    }
}

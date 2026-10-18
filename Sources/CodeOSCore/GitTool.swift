import Foundation

/// Finds a working Git. Apple's /usr/bin/git is only a shim that needs the Command Line Tools,
/// so MacPorts and Homebrew installs are tried first.
public enum GitTool {
    public static let candidates = [
        "/opt/local/bin/git",
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/usr/bin/git",
    ]

    /// The first candidate that actually runs. Nil when no Git works.
    public static let resolved: String? = locate()

    public static func locate(candidates: [String] = GitTool.candidates, verify: Bool = true) -> String? {
        candidates.first { path in
            FileManager.default.isExecutableFile(atPath: path) && (!verify || isWorking(path))
        }
    }

    static func isWorking(_ path: String) -> Bool {
        guard let result = try? ProcessRunner.run(executable: path, arguments: ["--version"], timeout: 10) else {
            return false
        }
        return result.succeeded && result.stdout.hasPrefix("git version")
    }
}

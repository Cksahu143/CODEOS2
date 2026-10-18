import Foundation

public enum FindingSeverity: Int, Comparable {
    case ok = 0, info, warning, error

    public static func < (lhs: FindingSeverity, rhs: FindingSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct DoctorFinding: Identifiable, Equatable {
    public var id: String { title }
    public let severity: FindingSeverity
    public let title: String
    public let detail: String
    /// What to do about it. Read-only: CodeOS shows the command and never runs it for you.
    public let fix: String?

    public init(severity: FindingSeverity, title: String, detail: String, fix: String? = nil) {
        self.severity = severity
        self.title = title
        self.detail = detail
        self.fix = fix
    }
}

/// Everything the doctor needs to know about the machine. Tests supply a fake.
public protocol EnvironmentProbe {
    func exists(_ path: String) -> Bool
    func isExecutable(_ path: String) -> Bool
    /// The first line of `<executable> <arguments>` output, or nil when it fails.
    func version(of executable: String, arguments: [String]) -> String?
    func pathEntries() -> [String]
    func environmentValue(_ name: String) -> String?
    /// Output of `xcode-select -p`, or nil.
    func commandLineToolsPath() -> String?
    /// Output of `xcrun --show-sdk-path`, or nil.
    func sdkPath() -> String?
}

public enum EnvironmentDoctor {
    static let gitPaths = GitTool.candidates
    static let pythonPaths = [
        "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/opt/local/bin/python3",
    ]
    static let nodePaths = [
        "/opt/homebrew/bin/node", "/usr/local/bin/node", "/opt/local/bin/node", "/usr/bin/node",
    ]

    public static func diagnose(_ probe: EnvironmentProbe) -> [DoctorFinding] {
        var findings: [DoctorFinding] = []
        findings.append(contentsOf: commandLineTools(probe))
        findings.append(contentsOf: git(probe))
        findings.append(contentsOf: python(probe))
        findings.append(contentsOf: node(probe))
        findings.append(contentsOf: packageManagers(probe))
        findings.append(contentsOf: path(probe))
        findings.append(contentsOf: terminal(probe))
        return findings.sorted { $0.severity > $1.severity }
    }

    static func commandLineTools(_ probe: EnvironmentProbe) -> [DoctorFinding] {
        guard let tools = probe.commandLineToolsPath(), probe.exists(tools) else {
            return [DoctorFinding(
                severity: .error,
                title: "Command Line Tools are missing",
                detail: "Git, Swift, and other developer tools that Apple ships depend on them.",
                fix: "Run: xcode-select --install   (if it fails, reinstall from developer.apple.com/download/all)")]
        }
        guard probe.sdkPath() != nil else {
            return [DoctorFinding(
                severity: .error,
                title: "Command Line Tools are damaged",
                detail: "They are installed at \(tools), but xcrun cannot find the macOS SDK. This breaks swift build and Apple's /usr/bin/git shim.",
                fix: "Run: xcode-select --install   (if it fails, reinstall from developer.apple.com/download/all)")]
        }
        return [DoctorFinding(severity: .ok, title: "Command Line Tools work", detail: tools)]
    }

    static func git(_ probe: EnvironmentProbe) -> [DoctorFinding] {
        var working: [(path: String, version: String)] = []
        for path in gitPaths where probe.isExecutable(path) {
            if path == "/usr/bin/git", probe.commandLineToolsPath() == nil { continue }
            if let version = probe.version(of: path, arguments: ["--version"]), version.hasPrefix("git version") {
                working.append((path, version))
            }
        }
        guard let first = working.first else {
            return [DoctorFinding(
                severity: .error,
                title: "No working Git",
                detail: "CodeOS cannot find a Git that runs.",
                fix: "Install Git with MacPorts (sudo port install git), Homebrew (brew install git), or the Command Line Tools.")]
        }
        var findings = [DoctorFinding(severity: .ok, title: "Git works",
                                      detail: "\(first.version) at \(first.path)")]
        if working.count > 1 {
            findings.append(DoctorFinding(
                severity: .info,
                title: "More than one Git is installed",
                detail: working.map { "\($0.path) (\($0.version))" }.joined(separator: "\n")
                    + "\nCodeOS uses the first one in this list, which prefers MacPorts and Homebrew over Apple's."))
        }
        return findings
    }

    static func python(_ probe: EnvironmentProbe) -> [DoctorFinding] {
        for path in pythonPaths where probe.isExecutable(path) {
            guard let version = probe.version(of: path, arguments: ["--version"]),
                  let minor = pythonMinor(version) else { continue }
            if minor >= 8 {
                return [DoctorFinding(severity: .ok, title: "Python 3 works", detail: "\(version) at \(path)")]
            }
        }
        var findings = [DoctorFinding(
            severity: .error,
            title: "No Python 3.8 or newer outside macOS's stub",
            detail: "The Opera bridge needs a real Python. /usr/bin/python3 only asks to install the Command Line Tools.",
            fix: "Install Python from python.org/downloads/macos, then run bridge/install.sh again.")]
        if probe.exists("/usr/bin/python3") {
            findings.append(DoctorFinding(
                severity: .info,
                title: "/usr/bin/python3 is a stub",
                detail: "It prompts for the Command Line Tools even when Python is installed elsewhere. Do not use it."))
        }
        return findings
    }

    /// "Python 3.12.3" -> 12. Nil when the text is not a Python 3 version.
    static func pythonMinor(_ text: String) -> Int? {
        let parts = text.replacingOccurrences(of: "Python ", with: "").split(separator: ".")
        guard parts.count >= 2, parts[0] == "3", let minor = Int(parts[1]) else { return nil }
        return minor
    }

    static func node(_ probe: EnvironmentProbe) -> [DoctorFinding] {
        for path in nodePaths where probe.isExecutable(path) {
            if let version = probe.version(of: path, arguments: ["--version"]) {
                return [DoctorFinding(severity: .ok, title: "Node.js works", detail: "\(version) at \(path)")]
            }
        }
        return [DoctorFinding(
            severity: .warning,
            title: "Node.js not found",
            detail: "Game projects, npm scripts, and the live preview need Node.js.",
            fix: "Install Node.js from nodejs.org, or use MacPorts (sudo port install nodejs20) or Homebrew (brew install node).")]
    }

    static func packageManagers(_ probe: EnvironmentProbe) -> [DoctorFinding] {
        let homebrew = probe.exists("/opt/homebrew/bin/brew") || probe.exists("/usr/local/bin/brew")
        let macports = probe.exists("/opt/local/bin/port")
        if homebrew && macports {
            return [DoctorFinding(
                severity: .warning,
                title: "Homebrew and MacPorts are both installed",
                detail: "Two package managers can install two versions of the same tool. Whichever appears first in PATH wins.",
                fix: "Keep one for each tool. Check which one runs with: which git node python3")]
        }
        if !homebrew && !macports {
            return [DoctorFinding(severity: .info, title: "No package manager found",
                                  detail: "Homebrew or MacPorts makes installing Git, Node, and Python easier.")]
        }
        return [DoctorFinding(severity: .ok, title: "One package manager", detail: homebrew ? "Homebrew" : "MacPorts")]
    }

    static func path(_ probe: EnvironmentProbe) -> [DoctorFinding] {
        let missing = probe.pathEntries().filter { !probe.exists($0) }
        guard !missing.isEmpty else {
            return [DoctorFinding(severity: .ok, title: "PATH folders all exist", detail: "")]
        }
        return [DoctorFinding(
            severity: .warning,
            title: "\(missing.count) PATH folder(s) do not exist",
            detail: missing.prefix(5).joined(separator: "\n"),
            fix: "Remove them from your shell startup file (~/.zshrc or ~/.zprofile) when you are ready.")]
    }

    static func terminal(_ probe: EnvironmentProbe) -> [DoctorFinding] {
        var findings: [DoctorFinding] = []
        if let shell = probe.environmentValue("SHELL") {
            findings.append(DoctorFinding(severity: .info, title: "Login shell", detail: shell))
        }
        if probe.exists("/Applications/iTerm.app") {
            findings.append(DoctorFinding(severity: .ok, title: "iTerm2 is installed", detail: "/Applications/iTerm.app"))
        } else {
            findings.append(DoctorFinding(severity: .info, title: "iTerm2 is not installed",
                                          detail: "Optional. CodeOS can open projects in iTerm2 once it is installed."))
        }
        return findings
    }
}

/// The real machine. Commands are fixed paths with argument lists, and none are run through a shell.
public struct LiveEnvironmentProbe: EnvironmentProbe {
    public init() {}

    public func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    public func version(of executable: String, arguments: [String]) -> String? {
        guard isExecutable(executable) else { return nil }
        // Apple's git shim can open a system prompt, so it is not run without the Command Line Tools.
        if executable == "/usr/bin/git" && commandLineToolsPath() == nil { return nil }
        guard let result = try? ProcessRunner.run(executable: executable, arguments: arguments, timeout: 5),
              result.succeeded else { return nil }
        let text = result.stdout.isEmpty ? result.stderr : result.stdout
        return text.split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    public func pathEntries() -> [String] {
        (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    }

    public func environmentValue(_ name: String) -> String? {
        ProcessInfo.processInfo.environment[name]
    }

    public func commandLineToolsPath() -> String? {
        guard let result = try? ProcessRunner.run(executable: "/usr/bin/xcode-select", arguments: ["-p"], timeout: 5),
              result.succeeded else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    public func sdkPath() -> String? {
        guard commandLineToolsPath() != nil else { return nil }
        guard let result = try? ProcessRunner.run(executable: "/usr/bin/xcrun", arguments: ["--show-sdk-path"], timeout: 10),
              result.succeeded else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}

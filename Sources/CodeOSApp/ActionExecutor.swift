import AppKit
import CodeOSCore
import Foundation

/// Native helpers that wrap NSWorkspace calls in async functions and surface real errors.
enum NativeOpen {
    static func applicationURL(bundleID: String) throws -> URL {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw AppActionError.appNotInstalled(bundleID)
        }
        return url
    }

    static func open(_ urls: [URL], withApplicationAt appURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    static func launch(_ appURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    static func requireFolder(_ path: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AppActionError.folderNotFound(path)
        }
    }
}

enum AppActionError: LocalizedError {
    case folderNotFound(String)
    case appNotInstalled(String)
    case openFailed(String)
    case invalidLink(String)
    case gitFailed(String)
    case appearanceChangeFailed(String)
    case appearanceNotChanged
    case commandFailed(name: String, status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .folderNotFound(let path):
            return "The folder “\(path)” does not exist or is not accessible."
        case .appNotInstalled(let bundleID):
            return "The application “\(bundleID)” is not installed. Choose another in Workflows or Workspaces."
        case .openFailed(let target):
            return "macOS could not open “\(target)”."
        case .invalidLink(let link):
            return "“\(link)” is not a valid http or https link."
        case .gitFailed(let message):
            return message.isEmpty ? "Git reported an error." : "Git reported an error: \(message)"
        case .appearanceChangeFailed(let message):
            return message
        case .appearanceNotChanged:
            return "macOS did not report the new appearance."
        case .commandFailed(let name, let status, let output):
            let tail = output.split(separator: "\n").suffix(3).joined(separator: "\n")
            return tail.isEmpty ? "\(name) exited with status \(status)." : "\(name) exited with status \(status):\n\(tail)"
        }
    }
}

/// Carries out workflow actions with real macOS calls.
struct AppActionExecutor: ActionExecutor {
    func execute(_ action: WorkflowAction) async throws -> String {
        switch action {
        case .openFolder(let path):
            try NativeOpen.requireFolder(path)
            guard NSWorkspace.shared.open(URL(fileURLWithPath: path)) else {
                throw AppActionError.openFailed(path)
            }
            return "Opened folder \(path)"

        case .openFolderInApp(let bundleID, let path):
            try NativeOpen.requireFolder(path)
            let appURL = try NativeOpen.applicationURL(bundleID: bundleID)
            try await NativeOpen.open([URL(fileURLWithPath: path)], withApplicationAt: appURL)
            return "Opened \(path) in \(appName(appURL))"

        case .openURL(let link):
            guard Validation.isWebURL(link), let url = URL(string: link) else {
                throw AppActionError.invalidLink(link)
            }
            guard NSWorkspace.shared.open(url) else { throw AppActionError.openFailed(link) }
            return "Opened \(link)"

        case .launchApp(let bundleID):
            let appURL = try NativeOpen.applicationURL(bundleID: bundleID)
            try await NativeOpen.launch(appURL)
            return "Launched \(appName(appURL))"

        case .openTerminal(let path):
            try NativeOpen.requireFolder(path)
            let terminal = try NativeOpen.applicationURL(bundleID: "com.apple.Terminal")
            try await NativeOpen.open([URL(fileURLWithPath: path)], withApplicationAt: terminal)
            return "Opened Terminal at \(path)"

        case .gitStatus(let repoPath):
            try NativeOpen.requireFolder(repoPath)
            let result = try await Task.detached(priority: .utility) {
                try ProcessRunner.run(
                    executable: GitTool.resolved ?? "/usr/bin/git",
                    arguments: ["status", "--porcelain=v1", "--branch"],
                    workingDirectory: repoPath
                )
            }.value
            guard result.succeeded else {
                throw AppActionError.gitFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let status = GitStatusParser.parse(result.stdout)
            let branch = status.branch ?? "detached HEAD"
            if status.isClean { return "\(branch): clean" }
            return "\(branch): \(status.changedCount) changed, \(status.untrackedCount) untracked"

        case .setSystemAppearance(let dark):
            try await SystemAppearance.apply(dark: dark)
            return dark ? "macOS is now in Dark appearance" : "macOS is now in Light appearance"

        case .runCommand(let executable, let arguments, let workingDirectory):
            if let workingDirectory { try NativeOpen.requireFolder(workingDirectory) }
            let name = (executable as NSString).lastPathComponent
            let result = try await Task.detached(priority: .utility) {
                try ProcessRunner.run(
                    executable: executable,
                    arguments: arguments,
                    workingDirectory: workingDirectory,
                    timeout: 600
                )
            }.value
            if result.timedOut {
                throw AppActionError.commandFailed(name: name, status: -1, output: "The command took longer than 10 minutes and was stopped.")
            }
            guard result.succeeded else {
                let output = result.stderr.isEmpty ? result.stdout : result.stderr
                throw AppActionError.commandFailed(name: name, status: result.exitCode, output: output)
            }
            return "\(name) finished successfully"
        }
    }

    private func appName(_ appURL: URL) -> String {
        appURL.deletingPathExtension().lastPathComponent
    }
}

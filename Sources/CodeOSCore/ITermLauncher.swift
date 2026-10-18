import Foundation

public enum ITermError: Error, LocalizedError, Equatable {
    case notInstalled
    case notAFolder(String)
    case permissionDenied
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "iTerm2 is not installed in /Applications. Install it from iterm2.com, then try again."
        case .notAFolder(let path):
            return "“\(path)” is not an existing folder."
        case .permissionDenied:
            return "macOS did not allow CodeOS to control iTerm2. Allow it in System Settings > Privacy & Security > Automation, then try again."
        case .failed(let message):
            return message.isEmpty ? "iTerm2 could not open the folder." : message
        }
    }
}

/// Opens a folder in a new iTerm2 window. The folder is an argument to a fixed AppleScript and is
/// quoted with AppleScript's `quoted form`, so its text is never treated as code.
public enum ITermLauncher {
    public static let appPath = "/Applications/iTerm.app"

    static let scriptLines = [
        "on run argv",
        "set folderPath to item 1 of argv",
        "tell application \"iTerm2\"",
        "activate",
        "create window with default profile",
        "tell current session of current window",
        "write text (\"cd \" & quoted form of folderPath & \" && clear\")",
        "end tell",
        "end tell",
        "end run",
    ]

    public static func arguments(for folder: String) throws -> [String] {
        guard folder.hasPrefix("/") else { throw ITermError.notAFolder(folder) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ITermError.notAFolder(folder)
        }
        var arguments: [String] = []
        for line in scriptLines {
            arguments += ["-e", line]
        }
        arguments.append(folder)
        return arguments
    }

    public static func open(folder: String) throws {
        guard FileManager.default.fileExists(atPath: appPath) else { throw ITermError.notInstalled }
        let arguments = try arguments(for: folder)
        let result = try ProcessRunner.run(executable: "/usr/bin/osascript", arguments: arguments, timeout: 20)
        guard result.succeeded else {
            if result.stderr.contains("-1743") { throw ITermError.permissionDenied }
            throw ITermError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

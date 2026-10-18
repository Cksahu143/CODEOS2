import Foundation

public enum TweakKind: Equatable {
    case bool
    case int(range: ClosedRange<Int>)
    /// An existing absolute folder path.
    case path
}

public enum TweakRestart: Equatable {
    case none, finder, dock, systemUI
}

public struct Tweak: Identifiable, Equatable {
    public var id: String { domain + "." + key }
    public let title: String
    public let detail: String
    public let domain: String
    public let key: String
    public let kind: TweakKind
    public let restart: TweakRestart
}

/// A command to run with an explicit argument list. Nothing is passed through a shell.
public struct TweakCommand: Equatable {
    public let executable: String
    public let arguments: [String]
}

public enum TweakError: Error, LocalizedError, Equatable {
    case invalidValue(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidValue(let message): return message
        case .commandFailed(let message): return message.isEmpty ? "The change could not be made." : message
        }
    }
}

/// Settings that macOS exposes through its standard defaults system. These are preferences only,
/// not code injection, and every one can be reset to the macOS default.
public enum MacTweaks {
    public static let catalog: [Tweak] = [
        Tweak(title: "Show hidden files in Finder", detail: "Shows files whose names start with a dot.",
              domain: "com.apple.finder", key: "AppleShowAllFiles", kind: .bool, restart: .finder),
        Tweak(title: "Show all file extensions", detail: "Always shows .txt, .pdf and other extensions.",
              domain: "NSGlobalDomain", key: "AppleShowAllExtensions", kind: .bool, restart: .none),
        Tweak(title: "Auto-hide the Dock", detail: "Hides the Dock until the pointer reaches the edge.",
              domain: "com.apple.dock", key: "autohide", kind: .bool, restart: .dock),
        Tweak(title: "Dock icon size", detail: "Size of Dock icons in points, 16 to 128.",
              domain: "com.apple.dock", key: "tilesize", kind: .int(range: 16...128), restart: .dock),
        Tweak(title: "Key repeat speed", detail: "Lower is faster. Units of 15 ms, 2 to 120.",
              domain: "NSGlobalDomain", key: "KeyRepeat", kind: .int(range: 2...120), restart: .none),
        Tweak(title: "Delay before key repeat", detail: "Lower is shorter. Units of 15 ms, 15 to 120.",
              domain: "NSGlobalDomain", key: "InitialKeyRepeat", kind: .int(range: 15...120), restart: .none),
        Tweak(title: "Screenshot folder", detail: "Where screenshots are saved.",
              domain: "com.apple.screencapture", key: "location", kind: .path, restart: .systemUI),
    ]

    public static func readCommand(_ tweak: Tweak) -> TweakCommand {
        TweakCommand(executable: "/usr/bin/defaults", arguments: ["read", tweak.domain, tweak.key])
    }

    public static func writeCommand(_ tweak: Tweak, value: String) throws -> TweakCommand {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let arguments: [String]
        switch tweak.kind {
        case .bool:
            guard trimmed == "true" || trimmed == "false" else {
                throw TweakError.invalidValue("Choose on or off.")
            }
            arguments = ["write", tweak.domain, tweak.key, "-bool", trimmed]
        case .int(let range):
            guard let number = Int(trimmed), range.contains(number) else {
                throw TweakError.invalidValue("Enter a whole number from \(range.lowerBound) to \(range.upperBound).")
            }
            arguments = ["write", tweak.domain, tweak.key, "-int", String(number)]
        case .path:
            guard trimmed.hasPrefix("/") else {
                throw TweakError.invalidValue("Choose a folder.")
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw TweakError.invalidValue("That folder does not exist.")
            }
            arguments = ["write", tweak.domain, tweak.key, "-string", trimmed]
        }
        return TweakCommand(executable: "/usr/bin/defaults", arguments: arguments)
    }

    public static func resetCommand(_ tweak: Tweak) -> TweakCommand {
        TweakCommand(executable: "/usr/bin/defaults", arguments: ["delete", tweak.domain, tweak.key])
    }

    /// Restarts the process that owns a setting. Returns nil when no restart is needed.
    public static func restartCommand(_ restart: TweakRestart) -> TweakCommand? {
        let process: String
        switch restart {
        case .none: return nil
        case .finder: process = "Finder"
        case .dock: process = "Dock"
        case .systemUI: process = "SystemUIServer"
        }
        return TweakCommand(executable: "/usr/bin/killall", arguments: [process])
    }

    public static func execute(_ command: TweakCommand) throws -> String {
        let result = try ProcessRunner.run(executable: command.executable, arguments: command.arguments, timeout: 10)
        guard result.succeeded else {
            // Deleting a setting that was never changed is not an error: it is already the default.
            if command.arguments.first == "delete" && result.stderr.contains("does not exist") { return "" }
            throw TweakError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

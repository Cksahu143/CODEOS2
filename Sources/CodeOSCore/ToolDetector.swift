import Foundation

public struct ToolStatus: Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let path: String?
    public let version: String?
    public var isInstalled: Bool { path != nil }
}

/// Detects developer tools from the actual file system and PATH.
public enum ToolDetector {
    public static var searchDirectories: [String] {
        let fromPath = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        return fromPath + ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]
    }

    public static func locate(_ name: String, in directories: [String] = searchDirectories) -> String? {
        for directory in directories {
            let candidate = (directory as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    public static func status(for name: String, versionArguments: [String] = ["--version"]) -> ToolStatus {
        guard let path = locate(name) else {
            return ToolStatus(name: name, path: nil, version: nil)
        }
        var version: String?
        if let result = try? ProcessRunner.run(executable: path, arguments: versionArguments, timeout: 5) {
            let text = (result.stdout.isEmpty ? result.stderr : result.stdout)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            version = text.split(separator: "\n").first.map(String.init)
        }
        return ToolStatus(name: name, path: path, version: version)
    }
}

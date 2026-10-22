import Foundation

public enum EditorFileError: Error, LocalizedError, Equatable {
    case tooLarge(Int)
    case binary
    case notUTF8

    public var errorDescription: String? {
        switch self {
        case .tooLarge(let bytes):
            return "This file is \(bytes / 1024) KB. The editor opens files up to \(EditorFile.maxBytes / 1024 / 1024) MB."
        case .binary:
            return "This is a binary file, so it can't be edited as text."
        case .notUTF8:
            return "This file is not UTF-8 text, so the editor can't open it safely."
        }
    }
}

/// Reads and writes text files for the editor. It refuses binary, oversized, and non-UTF-8 files.
public enum EditorFile {
    public static let maxBytes = 5 * 1024 * 1024

    static let languages: [String: String] = [
        "swift": "swift", "js": "javascript", "mjs": "javascript", "ts": "typescript", "tsx": "typescript",
        "jsx": "javascript", "py": "python", "html": "html", "htm": "html", "css": "css", "scss": "scss",
        "json": "json", "md": "markdown", "sh": "shell", "zsh": "shell", "bash": "shell", "c": "c",
        "h": "c", "cpp": "cpp", "cc": "cpp", "hpp": "cpp", "go": "go", "rs": "rust", "java": "java",
        "yml": "yaml", "yaml": "yaml", "xml": "xml", "sql": "sql", "rb": "ruby", "php": "php",
    ]

    public static func language(for path: String) -> String {
        languages[(path as NSString).pathExtension.lowercased()] ?? "plaintext"
    }

    /// Git's own test: a NUL byte in the first 8 KB means binary.
    public static func isBinary(_ data: Data) -> Bool {
        data.prefix(8192).contains(0)
    }

    public static func read(_ path: String) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxBytes else { throw EditorFileError.tooLarge(size) }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard !isBinary(data) else { throw EditorFileError.binary }
        guard let text = String(data: data, encoding: .utf8) else { throw EditorFileError.notUTF8 }
        return text
    }

    public static func write(_ text: String, to path: String) throws {
        guard text.utf8.count <= maxBytes else { throw EditorFileError.tooLarge(text.utf8.count) }
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Files Git tracks in the repository, relative to its root.
    public static func repositoryFiles(_ repository: String, limit: Int = 5000) throws -> [String] {
        let result = try GitStudio.run(["ls-files"], in: repository)
        guard result.succeeded else {
            throw GitError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Array(result.stdout.split(separator: "\n").map { String($0) }.prefix(limit))
    }
}

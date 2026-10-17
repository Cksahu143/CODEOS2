import Foundation

public enum FileOperationError: Error, Equatable, LocalizedError {
    case invalidName(String)
    case destinationExists(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            return "“\(name)” is not a valid name. Names cannot be empty, “.” or “..”, or contain “/”."
        case .destinationExists(let name):
            return "An item named “\(name)” already exists here. Nothing was changed."
        }
    }
}

/// Pure path logic for file operations. It performs no writes, so it can be tested
/// and previewed before anything changes on disk.
public enum FileOperationPlanner {
    /// A single path component: non-empty, not "." or "..", and without separators or NUL.
    public static func isSafeComponent(_ name: String) -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard name != ".", name != ".." else { return false }
        return !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    /// True when `child` is strictly inside `root` after standardizing both paths.
    public static func isInside(_ child: String, root: String) -> Bool {
        let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        let normalizedChild = URL(fileURLWithPath: child).standardizedFileURL.path
        let prefix = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"
        return normalizedChild.hasPrefix(prefix)
    }

    /// "Report.txt" -> "Report 2.txt" -> "Report 3.txt" when names are taken.
    public static func uniqueName(for name: String, existingNames: Set<String>) -> String {
        guard existingNames.contains(name) else { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ext.isEmpty ? name : ns.deletingPathExtension
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            if !existingNames.contains(candidate) { return candidate }
            counter += 1
        }
    }

    /// Validated destination path. Never overwrites: an existing name throws.
    public static func destination(directory: String, newName: String, existingNames: Set<String>) throws -> String {
        guard isSafeComponent(newName) else { throw FileOperationError.invalidName(newName) }
        guard !existingNames.contains(newName) else { throw FileOperationError.destinationExists(newName) }
        return (directory as NSString).appendingPathComponent(newName)
    }
}

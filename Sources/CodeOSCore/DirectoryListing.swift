import Foundation

public enum SortKey: String, CaseIterable, Identifiable {
    case name, modified, size
    public var id: String { rawValue }
}

public struct FileItem: Identifiable, Equatable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let size: Int64?
    public let modified: Date?
}

/// Reads one folder level. It never follows symbolic links during listing.
public enum DirectoryListing {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey
    ]

    public static func list(_ path: String, showHidden: Bool = false) throws -> [FileItem] {
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: showHidden ? [] : [.skipsHiddenFiles]
        )
        let items: [FileItem] = urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let size: Int64? = values?.fileSize.map { Int64($0) }
            return FileItem(
                path: url.path,
                name: url.lastPathComponent,
                isDirectory: values?.isDirectory ?? false,
                isSymbolicLink: values?.isSymbolicLink ?? false,
                size: size,
                modified: values?.contentModificationDate
            )
        }
        return sorted(items)
    }

    /// Folders always come first. Ties fall back to name.
    public static func sorted(_ items: [FileItem], by key: SortKey = .name, ascending: Bool = true) -> [FileItem] {
        items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            let order: ComparisonResult
            switch key {
            case .name: order = lhs.name.localizedStandardCompare(rhs.name)
            case .modified: order = compare(lhs.modified, rhs.modified)
            case .size: order = compare(lhs.size, rhs.size)
            }
            if order == .orderedSame {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    public static func parent(of path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if standardized == "/" { return "/" }
        return URL(fileURLWithPath: standardized).deletingLastPathComponent().standardizedFileURL.path
    }

    private static func compare<T: Comparable>(_ a: T?, _ b: T?) -> ComparisonResult {
        switch (a, b) {
        case let (x?, y?):
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
            return .orderedSame
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        }
    }
}

import Foundation

public struct CacheLocation: Identifiable, Equatable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let note: String
}

/// Finds reclaimable developer storage. It is advisory: it reports sizes and moves
/// items to the Trash only after the user confirms in the UI.
public enum StorageAdvisor {
    public static func knownCaches(home: String = NSHomeDirectory()) -> [CacheLocation] {
        func path(_ relative: String) -> String {
            (home as NSString).appendingPathComponent(relative)
        }
        return [
            CacheLocation(name: "Xcode derived data", path: path("Library/Developer/Xcode/DerivedData"),
                          note: "Rebuilt automatically the next time you build."),
            CacheLocation(name: "iOS Simulator caches", path: path("Library/Developer/CoreSimulator/Caches"),
                          note: "Simulator recreates these as needed."),
            CacheLocation(name: "npm cache", path: path(".npm"),
                          note: "Packages are downloaded again when needed."),
            CacheLocation(name: "Yarn cache", path: path("Library/Caches/Yarn"),
                          note: "Packages are downloaded again when needed."),
            CacheLocation(name: "Homebrew downloads", path: path("Library/Caches/Homebrew"),
                          note: "Downloads are fetched again when needed."),
            CacheLocation(name: "Gradle caches", path: path(".gradle/caches"),
                          note: "Dependencies are downloaded again on the next build."),
            CacheLocation(name: "Cargo registry cache", path: path(".cargo/registry/cache"),
                          note: "Crates are downloaded again on the next build.")
        ]
    }

    /// Total allocated size of a path. Symbolic links are not followed.
    public static func size(of path: String) -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true, let bytes = values.totalFileAllocatedSize {
                total += Int64(bytes)
            }
        }
        return total
    }

    /// Finds directories with the given names under `root`, without descending into matches
    /// or following symbolic links.
    public static func findArtifacts(in root: String, named names: Set<String>, maxDepth: Int = 5) -> [String] {
        var hits: [String] = []
        collect(URL(fileURLWithPath: root, isDirectory: true), names: names, depth: maxDepth, into: &hits)
        return hits.sorted()
    }

    private static func collect(_ directory: URL, names: Set<String>, depth: Int, into hits: inout [String]) {
        guard depth > 0,
              let children = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
              ) else { return }
        for child in children {
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else { continue }
            if names.contains(child.lastPathComponent) {
                hits.append(child.path)
            } else {
                collect(child, names: names, depth: depth - 1, into: &hits)
            }
        }
    }

    /// Moves an item to the Trash. The operation is recoverable.
    public static func moveToTrash(_ path: String) throws {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
    }
}

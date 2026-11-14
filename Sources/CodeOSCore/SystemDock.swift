import Foundation

public enum SystemDockError: Error, LocalizedError, Equatable {
    case readFailed(String)
    case writeFailed(String)
    case invalidValue(String)
    case noBackup

    public var errorDescription: String? {
        switch self {
        case .readFailed(let message): return "The Dock settings could not be read. " + message
        case .writeFailed(let message): return "The Dock settings could not be written. " + message
        case .invalidValue(let message): return message
        case .noBackup: return "No original Dock backup exists yet. Change a Dock setting once to create one."
        }
    }
}

/// A tile in the Dock: an app (persistent-apps) or a folder (persistent-others).
public struct DockTile: Identifiable, Equatable {
    public var id: String { section + "|" + String(index) }
    public let section: String
    public let index: Int
    public let label: String
    public let path: String
}

/// Reads and changes the macOS Dock through its standard preferences domain, com.apple.dock.
/// Colors and transparency are drawn by macOS itself and cannot be changed without code injection,
/// so they are not offered here.
public enum SystemDock {
    public static let domain = "com.apple.dock"
    public static let appsKey = "persistent-apps"
    public static let foldersKey = "persistent-others"

    public static let sizeRanges: [String: ClosedRange<Int>] = [
        "tilesize": 16...128,
        "largesize": 36...128,
    ]
    public static let booleanKeys = ["magnification", "autohide", "show-recents", "minimize-to-application"]
    public static let orientations = ["bottom", "left", "right"]
    public static let effects = ["genie", "scale"]

    public static var originalBackupURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CodeOS/dock-original.plist")
    }

    public static func validatedNumber(_ key: String, _ text: String) throws -> Int {
        guard let range = sizeRanges[key] else { throw SystemDockError.invalidValue("Unknown Dock setting.") }
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), range.contains(value) else {
            throw SystemDockError.invalidValue("Enter a whole number from \(range.lowerBound) to \(range.upperBound).")
        }
        return value
    }

    public static func tileDictionary(forApp path: String) -> [String: Any] {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return [
            "tile-data": [
                "file-data": ["_CFURLString": URL(fileURLWithPath: path).absoluteString, "_CFURLStringType": 15],
                "file-label": name,
                "file-type": 41,
            ],
            "tile-type": "file-tile",
        ]
    }

    public static func tileDictionary(forFolder path: String) -> [String: Any] {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return [
            "tile-data": [
                "file-data": ["_CFURLString": URL(fileURLWithPath: path, isDirectory: true).absoluteString, "_CFURLStringType": 15],
                "file-label": name,
                "file-type": 2,
                "arrangement": 2,
                "displayas": 1,
                "showas": 2,
            ],
            "tile-type": "directory-tile",
        ]
    }

    public static func tiles(in dictionary: [String: Any], section: String) -> [DockTile] {
        let items = dictionary[section] as? [[String: Any]] ?? []
        return items.enumerated().compactMap { index, item in
            guard let data = item["tile-data"] as? [String: Any] else { return nil }
            let label = data["file-label"] as? String ?? "Untitled"
            let urlText = (data["file-data"] as? [String: Any])?["_CFURLString"] as? String ?? ""
            let path = URL(string: urlText)?.path ?? urlText
            return DockTile(section: section, index: index, label: label, path: path)
        }
    }

    /// Removes one tile. Returns false when the index does not exist.
    public static func remove(section: String, index: Int, from dictionary: inout [String: Any]) -> Bool {
        var items = dictionary[section] as? [[String: Any]] ?? []
        guard items.indices.contains(index) else { return false }
        items.remove(at: index)
        dictionary[section] = items
        return true
    }

    public static func export() throws -> [String: Any] {
        let result = try ProcessRunner.run(executable: "/usr/bin/defaults", arguments: ["export", domain, "-"], timeout: 10)
        guard result.succeeded else {
            throw SystemDockError.readFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let data = result.stdout.data(using: .utf8),
              let dictionary = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw SystemDockError.readFailed("The output was not a settings file.")
        }
        return dictionary
    }

    /// Writes the whole Dock domain back. Everything not changed is written exactly as it was read.
    public static func write(_ dictionary: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("codeos-dock-\(UUID().uuidString).plist")
        try data.write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let result = try ProcessRunner.run(executable: "/usr/bin/defaults", arguments: ["import", domain, temporary.path], timeout: 10)
        guard result.succeeded else {
            throw SystemDockError.writeFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Saves the Dock exactly as it was, once, before CodeOS first changes anything.
    public static func backupOriginalIfNeeded() throws {
        let url = originalBackupURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let original = try export()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: original, format: .xml, options: 0)
        try data.write(to: url)
    }

    public static func restoreOriginal() throws {
        let url = originalBackupURL
        guard FileManager.default.fileExists(atPath: url.path) else { throw SystemDockError.noBackup }
        let data = try Data(contentsOf: url)
        guard let original = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw SystemDockError.readFailed("The backup is not a settings file.")
        }
        try write(original)
        try restart()
    }

    /// Applies changes. The Dock restarts itself; no app or login session needs to restart.
    public static func restart() throws {
        _ = try ProcessRunner.run(executable: "/usr/bin/killall", arguments: ["Dock"], timeout: 5)
    }
}

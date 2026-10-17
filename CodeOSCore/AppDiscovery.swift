import Foundation

public struct InstalledApp: Identifiable, Equatable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let path: String
}

/// Finds applications by reading the bundles on disk. Nothing is hardcoded.
public enum AppDiscovery {
    public static var defaultSearchDirectories: [String] {
        [
            "/Applications",
            "/System/Applications",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        ]
    }

    public static func scan(directories: [String] = defaultSearchDirectories) -> [InstalledApp] {
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for directory in directories {
            let base = URL(fileURLWithPath: directory, isDirectory: true)
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where entry.pathExtension == "app" {
                guard let bundle = Bundle(url: entry),
                      let bundleID = bundle.bundleIdentifier,
                      !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)
                let info = bundle.infoDictionary ?? [:]
                let name = (info["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? entry.deletingPathExtension().lastPathComponent
                apps.append(InstalledApp(bundleID: bundleID, name: name, path: entry.path))
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

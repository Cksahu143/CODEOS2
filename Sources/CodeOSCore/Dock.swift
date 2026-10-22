import Foundation

/// One button on the dock. A dock item can open a section, an app, a folder, or a web link.
/// It never runs a shell command, so editing the dock cannot run anything on your Mac.
public struct DockItem: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable, CaseIterable {
        case section, application, folder, link
    }

    public var id: UUID
    public var kind: Kind
    public var title: String
    /// An SF Symbol name, such as "house" or "terminal".
    public var symbol: String
    /// A section name, bundle identifier, absolute folder path, or http(s) link, depending on kind.
    public var target: String

    public init(id: UUID = UUID(), kind: Kind, title: String, symbol: String, target: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.symbol = symbol
        self.target = target
    }
}

public enum DockRules {
    public static let defaults: [DockItem] = [
        DockItem(kind: .section, title: "Home", symbol: "house", target: "home"),
        DockItem(kind: .section, title: "Studio", symbol: "rectangle.split.3x1", target: "studio"),
        DockItem(kind: .section, title: "Files", symbol: "folder", target: "files"),
        DockItem(kind: .section, title: "Apps", symbol: "square.grid.2x2", target: "applications"),
        DockItem(kind: .section, title: "Monitor", symbol: "waveform.path.ecg", target: "monitor"),
        DockItem(kind: .section, title: "Doctor", symbol: "stethoscope", target: "doctor"),
    ]

    /// Why an item cannot be used, or nil when it is valid.
    public static func problem(for item: DockItem) -> String? {
        if item.title.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Give this button a name."
        }
        let target = item.target.trimmingCharacters(in: .whitespaces)
        switch item.kind {
        case .section:
            return target.isEmpty ? "Choose a section." : nil
        case .application:
            return target.isEmpty ? "Choose an application." : nil
        case .folder:
            var isDirectory: ObjCBool = false
            guard target.hasPrefix("/"), FileManager.default.fileExists(atPath: target, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return "Choose a folder that exists." }
            return nil
        case .link:
            return Validation.isWebURL(target) ? nil : "The link must start with http:// or https://."
        }
    }

    public static func encode(_ items: [DockItem]) -> Data {
        (try? JSONEncoder().encode(items)) ?? Data()
    }

    public static func decode(_ data: Data) -> [DockItem]? {
        try? JSONDecoder().decode([DockItem].self, from: data)
    }
}

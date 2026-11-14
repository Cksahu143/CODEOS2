import Foundation

/// One item on the CodeOS dock. Items open things or group others. None runs a shell command.
public struct DockItem: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable, CaseIterable {
        case section, application, folder, link, spacer, separator
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

/// How the dock looks. Values are checked before they are used.
public struct DockAppearance: Codable, Equatable {
    public static let positions = ["bottom", "left", "right"]

    public var backgroundHex: String = "#1E2330"
    public var opacity: Double = 0.85
    public var cornerRadius: Double = 18
    public var iconSize: Double = 44
    public var position: String = "bottom"
    public var isVisible: Bool = false

    public init() {}
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

    /// Why an item cannot be used, or nil when it is valid. Spacers and separators need no target.
    public static func problem(for item: DockItem) -> String? {
        switch item.kind {
        case .spacer, .separator:
            return nil
        default:
            break
        }
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
        case .spacer, .separator:
            return nil
        }
    }

    public static func problem(for appearance: DockAppearance) -> String? {
        if !isHexColor(appearance.backgroundHex) { return "Use a color like #1E2330." }
        if !(0.2...1.0).contains(appearance.opacity) { return "Opacity must be between 0.2 and 1." }
        if !(24.0...96.0).contains(appearance.iconSize) { return "Icon size must be between 24 and 96." }
        if !(0.0...40.0).contains(appearance.cornerRadius) { return "Corner radius must be between 0 and 40." }
        if !DockAppearance.positions.contains(appearance.position) { return "Position must be bottom, left, or right." }
        return nil
    }

    public static func isHexColor(_ text: String) -> Bool {
        guard text.count == 7, text.hasPrefix("#") else { return false }
        return text.dropFirst().allSatisfy { $0.isHexDigit }
    }

    public static func encode(_ items: [DockItem]) -> Data {
        (try? JSONEncoder().encode(items)) ?? Data()
    }

    public static func decode(_ data: Data) -> [DockItem]? {
        try? JSONDecoder().decode([DockItem].self, from: data)
    }

    public static func encodeAppearance(_ appearance: DockAppearance) -> Data {
        (try? JSONEncoder().encode(appearance)) ?? Data()
    }

    public static func decodeAppearance(_ data: Data) -> DockAppearance? {
        try? JSONDecoder().decode(DockAppearance.self, from: data)
    }
}

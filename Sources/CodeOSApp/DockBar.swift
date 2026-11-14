import AppKit
import CodeOSCore
import SwiftUI

extension Notification.Name {
    /// Posted by the dock to switch the CodeOS window to a section. The object is the section's raw name.
    static let codeosSelectSection = Notification.Name("codeosSelectSection")
}

/// The dock's items and appearance. Both are saved whenever they change.
@MainActor
final class DockModel: ObservableObject {
    static let shared = DockModel()
    private static let itemsKey = "dockItems"
    private static let appearanceKey = "dockAppearance"

    @Published var items: [DockItem] {
        didSet {
            UserDefaults.standard.set(DockRules.encode(items), forKey: DockModel.itemsKey)
        }
    }

    @Published var appearance: DockAppearance {
        didSet {
            UserDefaults.standard.set(DockRules.encodeAppearance(appearance), forKey: DockModel.appearanceKey)
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: DockModel.itemsKey), let saved = DockRules.decode(data) {
            items = saved
        } else {
            items = DockRules.defaults
        }
        if let data = UserDefaults.standard.data(forKey: DockModel.appearanceKey),
           let saved = DockRules.decodeAppearance(data) {
            appearance = saved
        } else {
            appearance = DockAppearance()
        }
    }

    func add(_ item: DockItem) {
        items.append(item)
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func move(_ id: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard target >= 0, target < items.count else { return }
        items.swapAt(index, target)
    }

    func resetToDefaults() {
        items = DockRules.defaults
    }
}

/// What a dock button does. Each action opens something; none runs a shell command.
@MainActor
enum DockActions {
    static func activate(_ item: DockItem) {
        switch item.kind {
        case .section:
            NotificationCenter.default.post(name: .codeosSelectSection, object: item.target)
            NSApp.activate(ignoringOtherApps: true)
        case .application:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.target) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        case .folder:
            NSWorkspace.shared.open(URL(fileURLWithPath: item.target))
        case .link:
            if let url = URL(string: item.target) {
                NSWorkspace.shared.open(url)
            }
        case .spacer, .separator:
            break
        }
    }
}

extension Color {
    /// Builds a color from "#RRGGBB".
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(digits, radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }

    /// The color as "#RRGGBB", in sRGB.
    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        return String(
            format: "#%02X%02X%02X",
            Int32(color.redComponent * 255),
            Int32(color.greenComponent * 255),
            Int32(color.blueComponent * 255))
    }
}

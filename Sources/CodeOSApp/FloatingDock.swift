import AppKit
import CodeOSCore
import SwiftUI

struct WindowPreview: Identifiable {
    let id: Int
    let title: String
    let image: NSImage?
}

/// Window lists and thumbnails. Thumbnails need Screen Recording permission, which macOS asks for once.
enum WindowPreviews {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func windows(forProcess pid: pid_t) -> [(id: Int, title: String)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { window in
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber, owner.int32Value == pid,
                  let layer = window[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0,
                  let number = window[kCGWindowNumber as String] as? NSNumber else { return nil }
            let title = (window[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Window"
            return (number.intValue, title)
        }
    }

    static func thumbnail(windowID: Int) -> NSImage? {
        guard let image = CGWindowListCreateImage(
            .null, .optionIncludingWindow, CGWindowID(windowID), [.boundsIgnoreFraming, .bestResolution]) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

enum AppIcons {
    static func icon(forBundleID bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// The floating CodeOS dock. Its size changes only when items or appearance change, so it never jumps under the pointer.
/// Hover previews live in a separate window that ignores the mouse.
@MainActor
final class FloatingDock: ObservableObject {
    static let shared = FloatingDock()

    @Published private(set) var runningBundleIDs: Set<String> = []
    @Published private(set) var hoveredItem: DockItem?
    @Published private(set) var previews: [WindowPreview] = []
    @Published private(set) var needsPermission = false

    private var panel: NSPanel?
    private var bubble: NSPanel?
    private var timer: Timer?

    func setVisible(_ visible: Bool) {
        var appearance = DockModel.shared.appearance
        appearance.isVisible = visible
        DockModel.shared.appearance = appearance
        if visible {
            show()
        } else {
            hide()
        }
    }

    /// Shows the dock at launch if it was visible when CodeOS last quit.
    func restoreIfNeeded() {
        if DockModel.shared.appearance.isVisible {
            show()
        }
    }

    func show() {
        if panel == nil {
            buildDock()
        }
        refreshRunning()
        resize()
        panel?.orderFrontRegardless()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshRunning() }
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        hover(nil)
        panel?.orderOut(nil)
    }

    /// Called when the pointer enters or leaves a tile. Only moves the bubble; the dock itself does not resize.
    func hover(_ item: DockItem?) {
        guard item != hoveredItem else { return }
        hoveredItem = item
        previews = []
        needsPermission = false
        if let item, item.kind == .application,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: item.target).first {
            if WindowPreviews.hasPermission {
                previews = WindowPreviews.windows(forProcess: app.processIdentifier).prefix(4).map { window in
                    WindowPreview(id: window.id, title: window.title, image: WindowPreviews.thumbnail(windowID: window.id))
                }
            } else {
                needsPermission = true
            }
        }
        // Wait one run-loop turn so SwiftUI has laid out the new bubble before it is measured.
        DispatchQueue.main.async { [weak self] in
            self?.placeBubble()
        }
    }

    /// Fits the dock to its contents. Keeps the spot the user chose, so it does not snap back to the default edge.
    func resize() {
        guard let panel, let hosting = panel.contentView as? NSHostingView<FloatingDockView>,
              let screen = NSScreen.main?.visibleFrame else { return }
        let before = panel.frame
        let wasShown = panel.isVisible
        let size = hosting.fittingSize
        panel.setContentSize(size)
        let position = DockModel.shared.appearance.position
        var origin: NSPoint
        if wasShown {
            switch position {
            case "left":
                origin = NSPoint(x: before.minX, y: before.midY - size.height / 2)
            case "right":
                origin = NSPoint(x: before.maxX - size.width, y: before.midY - size.height / 2)
            default:
                origin = NSPoint(x: before.midX - size.width / 2, y: before.minY)
            }
        } else {
            switch position {
            case "left":
                origin = NSPoint(x: screen.minX + 12, y: screen.midY - size.height / 2)
            case "right":
                origin = NSPoint(x: screen.maxX - size.width - 12, y: screen.midY - size.height / 2)
            default:
                origin = NSPoint(x: screen.midX - size.width / 2, y: screen.minY + 12)
            }
        }
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        panel.setFrameOrigin(origin)
        placeBubble()
    }

    private func placeBubble() {
        guard let panel, panel.isVisible, hoveredItem != nil else {
            bubble?.orderOut(nil)
            return
        }
        if bubble == nil {
            buildBubble()
        }
        guard let bubble, let hosting = bubble.contentView as? NSHostingView<HoverBubbleView> else { return }
        let size = hosting.fittingSize
        bubble.setContentSize(size)
        let frame = panel.frame
        let origin: NSPoint
        switch DockModel.shared.appearance.position {
        case "left":
            origin = NSPoint(x: frame.maxX + 10, y: frame.midY - size.height / 2)
        case "right":
            origin = NSPoint(x: frame.minX - size.width - 10, y: frame.midY - size.height / 2)
        default:
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY + 10)
        }
        bubble.setFrameOrigin(origin)
        bubble.orderFrontRegardless()
    }

    private func buildDock() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(rootView: FloatingDockView(model: DockModel.shared, dock: self))
        panel = window
    }

    private func buildBubble() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(rootView: HoverBubbleView(dock: self))
        bubble = window
    }

    private func refreshRunning() {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        if ids != runningBundleIDs {
            runningBundleIDs = ids
        }
    }
}

/// The name and window previews above a hovered icon. It lives in its own window, so it never moves the dock.
struct HoverBubbleView: View {
    @ObservedObject var dock: FloatingDock

    var body: some View {
        if let item = dock.hoveredItem {
            VStack(spacing: 6) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                if dock.needsPermission {
                    VStack(spacing: 4) {
                        Text("Window previews need Screen Recording permission.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button("Allow…") { WindowPreviews.requestPermission() }
                            .controlSize(.small)
                    }
                } else if !dock.previews.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(dock.previews) { preview in
                            VStack(spacing: 3) {
                                if let image = preview.image {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 150, height: 94)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(width: 150, height: 94)
                                }
                                Text(preview.title)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(width: 150)
                            }
                        }
                    }
                }
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .fixedSize()
        }
    }
}

struct FloatingDockView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var dock: FloatingDock

    var body: some View {
        let style = model.appearance
        let vertical = style.position != "bottom"
        Group {
            if vertical {
                VStack(spacing: 6) { tiles(vertical: true) }
            } else {
                HStack(spacing: 6) { tiles(vertical: false) }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(Color(hex: style.backgroundHex).opacity(style.opacity)))
        .onHover { inside in
            if !inside { FloatingDock.shared.hover(nil) }
        }
        .onChange(of: model.appearance) { _ in FloatingDock.shared.resize() }
        .onChange(of: model.items) { _ in FloatingDock.shared.resize() }
    }

    @ViewBuilder
    private func tiles(vertical: Bool) -> some View {
        ForEach(model.items) { item in
            tile(item, vertical: vertical)
        }
    }

    @ViewBuilder
    private func tile(_ item: DockItem, vertical: Bool) -> some View {
        let size = model.appearance.iconSize
        switch item.kind {
        case .spacer:
            Color.clear.frame(width: vertical ? 1 : 24, height: vertical ? 24 : 1)
        case .separator:
            Rectangle()
                .fill(Color.primary.opacity(0.25))
                .frame(width: vertical ? 36 : 1, height: vertical ? 1 : 36)
        default:
            Button {
                DockActions.activate(item)
            } label: {
                VStack(spacing: 3) {
                    iconImage(item, size: size)
                    Circle()
                        .fill(isRunning(item) ? Color.primary : Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside {
                    FloatingDock.shared.hover(item)
                } else if FloatingDock.shared.hoveredItem?.id == item.id {
                    FloatingDock.shared.hover(nil)
                }
            }
            .help(item.title)
        }
    }

    @ViewBuilder
    private func iconImage(_ item: DockItem, size: Double) -> some View {
        if item.kind == .application, let icon = AppIcons.icon(forBundleID: item.target) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: item.symbol)
                .font(.system(size: size * 0.55, weight: .medium))
                .frame(width: size, height: size)
        }
    }

    private func isRunning(_ item: DockItem) -> Bool {
        item.kind == .application && dock.runningBundleIDs.contains(item.target)
    }
}

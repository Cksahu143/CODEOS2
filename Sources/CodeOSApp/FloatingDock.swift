import AppKit
import CodeOSCore
import SwiftUI

/// A floating panel that shows the CodeOS dock above other windows. It does not change the system Dock,
/// and it cannot reserve screen space the way the system Dock does.
@MainActor
final class FloatingDock: ObservableObject {
    static let shared = FloatingDock()

    @Published private(set) var runningBundleIDs: Set<String> = []
    private var panel: NSPanel?
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
            build()
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
        panel?.orderOut(nil)
    }

    /// Fits the panel to its contents and places it on the chosen edge of the main screen.
    func resize() {
        guard let panel, let hosting = panel.contentView as? NSHostingView<FloatingDockView> else { return }
        let size = hosting.fittingSize
        panel.setContentSize(size)
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let origin: NSPoint
        switch DockModel.shared.appearance.position {
        case "left":
            origin = NSPoint(x: screen.minX + 12, y: screen.midY - size.height / 2)
        case "right":
            origin = NSPoint(x: screen.maxX - size.width - 12, y: screen.midY - size.height / 2)
        default:
            origin = NSPoint(x: screen.midX - size.width / 2, y: screen.minY + 12)
        }
        panel.setFrameOrigin(origin)
    }

    private func build() {
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

    private func refreshRunning() {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        if ids != runningBundleIDs {
            runningBundleIDs = ids
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
                    Image(systemName: item.symbol)
                        .font(.system(size: size * 0.55, weight: .medium))
                        .frame(width: size, height: size)
                    Circle()
                        .fill(isRunning(item) ? Color.primary : Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
            .buttonStyle(.plain)
            .help(item.title)
        }
    }

    private func isRunning(_ item: DockItem) -> Bool {
        item.kind == .application && dock.runningBundleIDs.contains(item.target)
    }
}

import AppKit
import QuickLookUI
import SwiftUI

/// Gives Quick Look a URL it can preview.
final class PreviewItem: NSObject, QLPreviewItem {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    var previewItemURL: URL? { url }
    var previewItemTitle: String? { url.lastPathComponent }
}

/// Apple's Quick Look engine. It previews text, PDF, Word, Excel, PowerPoint, audio, video,
/// and HTML with the macOS built-in generators. Office formats and HTML depend on those generators.
struct QuickLookView: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> QLPreviewView {
        let view: QLPreviewView? = QLPreviewView(frame: .zero, style: .normal)
        return view ?? QLPreviewView()
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if view.previewItem?.previewItemURL != url {
            view.previewItem = url.map { PreviewItem(url: $0) }
        }
    }
}

/// Opens a file in its own window. That window has the standard full-screen button.
@MainActor
enum PreviewWindows {
    private static var windows: [NSWindow] = []

    static func show(_ url: URL, fullScreen: Bool = false) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = url.lastPathComponent
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = NSHostingView(rootView: QuickLookView(url: url)
            .frame(minWidth: 480, minHeight: 360))
        window.center()
        windows.append(window)
        window.makeKeyAndOrderFront(nil)
        if fullScreen {
            window.toggleFullScreen(nil)
        }
    }
}

enum FilePicker {
    static func chooseFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Preview"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Sidebar section: open any file and preview it, or send it to a full-screen window.
struct PreviewView: View {
    @State private var url: URL?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(url?.lastPathComponent ?? "No file open")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Open…") {
                    if let chosen = FilePicker.chooseFile() { url = chosen }
                }
                Button {
                    if let url { PreviewWindows.show(url, fullScreen: true) }
                } label: {
                    Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .disabled(url == nil)
            }
            .padding(12)
            Divider()
            if url == nil {
                EmptyStateView(
                    title: "Preview any file",
                    message: "Word, Excel, PowerPoint, text, PDF, audio, video, and HTML. Open a file here, or select one in Files and choose Quick Look Preview.",
                    systemImage: "eye")
            } else {
                QuickLookView(url: url)
            }
        }
        .navigationTitle("Preview")
    }
}

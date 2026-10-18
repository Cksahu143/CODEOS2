import AppKit
import CodeOSCore
import SwiftUI

/// One tab for everything: Git, the commit graph, games, and the terminal.
/// Each pane stays loaded, so switching panes keeps the terminal session and the Git position.
struct StudioView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case git, graph, games, terminal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .git: return "Git"
            case .graph: return "Graph"
            case .games: return "Games"
            case .terminal: return "Terminal"
            }
        }
    }

    @State private var pane: Pane = .git
    @AppStorage("gitGraphRepository") private var repository = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Pane", selection: $pane) {
                    ForEach(Pane.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 340)
                Spacer()
                Button {
                    openInVSCode()
                } label: {
                    Label("Open in VS Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .disabled(repository.isEmpty)
            }
            .padding(10)
            Divider()
            ZStack {
                pane(.git, GitStudioView())
                pane(.graph, GitGraphView())
                pane(.games, GamesView())
                pane(.terminal, TerminalSectionView())
            }
        }
        .navigationTitle("Studio")
    }

    private func pane<Content: View>(_ value: Pane, _ content: Content) -> some View {
        content
            .opacity(pane == value ? 1 : 0)
            .allowsHitTesting(pane == value)
    }

    /// Opens the Git repository in VS Code. If VS Code is not installed, says so.
    private func openInVSCode() {
        let folder = URL(fileURLWithPath: repository)
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") else {
            let alert = NSAlert()
            alert.messageText = "VS Code is not installed"
            alert.informativeText = "Get it from code.visualstudio.com, then try again."
            alert.runModal()
            return
        }
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}

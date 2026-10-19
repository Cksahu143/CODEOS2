import AppKit
import CodeOSCore
import SwiftUI

/// One tab for everything: Git, the commit graph, merge preview, games, and the terminal.
/// Only the selected pane is created, so an unselected pane never runs in the background.
struct StudioView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case git, graph, merge, games, terminal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .git: return "Git"
            case .graph: return "Graph"
            case .merge: return "Merge"
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
                .frame(width: 440)
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
            content
        }
        .navigationTitle("Studio")
    }

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .git: GitStudioView()
        case .graph: GitGraphView()
        case .merge: MergePreviewView()
        case .games: GamesView()
        case .terminal: TerminalSectionView()
        }
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

import AppKit
import CodeOSCore
import SwiftUI

/// One tab for everything. The repository is chosen once, here; every Git pane reads it.
/// Only the selected pane is created, so an unselected pane never runs in the background.
struct StudioView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case git, graph, branches, merge, state, games, terminal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .git: return "Git"
            case .graph: return "Graph"
            case .branches: return "Branches"
            case .merge: return "Merge"
            case .state: return "State"
            case .games: return "Games"
            case .terminal: return "Terminal"
            }
        }
    }

    @State private var pane: Pane = .git
    @AppStorage("gitGraphRepository") private var repository = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Studio")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                if let path = FolderPicker.chooseFolder(prompt: "Choose") { repository = path }
            } label: {
                Label("Choose Repository…", systemImage: "folder")
            }
            Text(repository.isEmpty ? "No repository chosen" : URL(fileURLWithPath: repository).lastPathComponent)
                .font(.callout)
                .foregroundStyle(repository.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .help(repository)
            Picker("Pane", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 640)
            Spacer()
            Button {
                openInVSCode()
            } label: {
                Label("Open in VS Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .disabled(repository.isEmpty)
        }
        .padding(10)
    }

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .git: GitStudioView()
        case .graph: GitGraphView()
        case .branches: BranchManagerView()
        case .merge: MergePreviewView()
        case .state: RepositoryStateView()
        case .games: GamesView()
        case .terminal: TerminalSectionView()
        }
    }

    /// Opens the chosen repository in VS Code. If VS Code is not installed, says so.
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

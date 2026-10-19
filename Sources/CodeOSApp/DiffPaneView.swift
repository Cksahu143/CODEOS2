import CodeOSCore
import SwiftUI

struct DiffPaneView: View {
    @AppStorage("gitGraphRepository") private var repository = ""
    @State private var commits: [CommitSummary] = []
    @State private var source = "working"
    @State private var files: [DiffFile] = []
    @State private var selectedFile: String?
    @State private var note: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("Show", selection: $source) {
                    Text("Uncommitted changes").tag("working")
                    ForEach(commits) { commit in
                        Text("\(commit.shortHash)  \(commit.subject)").tag(commit.id)
                    }
                }
                .frame(width: 460)
                Button {
                    Task { await loadAll() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(repository.isEmpty || busy)
                if busy { ProgressView().controlSize(.small) }
                Spacer()
            }
            if let note {
                Text(note).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HSplitView {
                List(files, selection: $selectedFile) { file in
                    HStack(spacing: 8) {
                        Text(file.path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("+\(file.additions)").foregroundStyle(.green).font(.caption.monospacedDigit())
                        Text("-\(file.deletions)").foregroundStyle(.red).font(.caption.monospacedDigit())
                    }
                    .tag(file.path)
                }
                .frame(minWidth: 260)
                diffBody
                    .frame(minWidth: 420)
            }
        }
        .padding(12)
        .task(id: repository) { await loadAll() }
        .onChange(of: source) { _ in Task { await load() } }
    }

    private var diffBody: some View {
        let shown = files.first { $0.path == selectedFile } ?? files.first
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let shown {
                    if shown.isBinary {
                        Text("Binary file: no text diff is shown.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    ForEach(Array(shown.lines.enumerated()), id: \.offset) { _, line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(line.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .background(background(line.kind))
                            .textSelection(.enabled)
                    }
                } else {
                    EmptyStateView(
                        title: "No changes to show",
                        message: "Pick a commit above, or edit files in the repository to see uncommitted changes here.",
                        systemImage: "doc.text.magnifyingglass")
                }
            }
        }
    }

    private func color(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        case .hunk: return .accentColor
        case .header: return .secondary
        case .context: return .primary
        }
    }

    private func background(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .added: return .green.opacity(0.10)
        case .removed: return .red.opacity(0.10)
        default: return .clear
        }
    }

    private func loadAll() async {
        guard !repository.isEmpty else {
            commits = []
            files = []
            return
        }
        let path = repository
        do {
            commits = try await Task.detached(priority: .utility) {
                try GitDiffReader.recentCommits(repository: path)
            }.value
        } catch {
            commits = []
            note = error.localizedDescription
        }
        await load()
    }

    private func load() async {
        guard !repository.isEmpty else { return }
        busy = true
        defer { busy = false }
        let path = repository
        let choice = source
        do {
            let text = try await Task.detached(priority: .utility) { () throws -> String in
                if choice == "working" {
                    return try GitDiffReader.workingTree(repository: path)
                }
                return try GitDiffReader.commit(repository: path, hash: choice)
            }.value
            files = DiffParser.parse(text)
            selectedFile = files.first?.path
            note = files.isEmpty ? "No changes in this view." : nil
        } catch {
            files = []
            note = error.localizedDescription
        }
    }
}

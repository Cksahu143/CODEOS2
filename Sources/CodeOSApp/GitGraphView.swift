import CodeOSCore
import SwiftUI

/// Draws one row's lanes: incoming lines, the commit dot, and lines to its parents.
struct GitGraphCanvas: View {
    let row: GitGraphRow
    static let laneWidth: CGFloat = 14
    static let rowHeight: CGFloat = 36
    static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .yellow]

    static func width(lanes: Int) -> CGFloat {
        CGFloat(max(lanes, 1)) * laneWidth + 20
    }

    var body: some View {
        Canvas { context, size in
            let height = size.height
            let middle = height / 2
            func x(_ lane: Int) -> CGFloat { 10 + CGFloat(lane) * GitGraphCanvas.laneWidth }
            func color(_ lane: Int) -> Color { GitGraphCanvas.palette[lane % GitGraphCanvas.palette.count] }

            for (index, hash) in row.topLanes.enumerated() {
                guard let hash else { continue }
                var path = Path()
                path.move(to: CGPoint(x: x(index), y: 0))
                if hash == row.commit.hash {
                    path.addLine(to: CGPoint(x: x(row.lane), y: middle))
                } else if let below = row.bottomLanes.firstIndex(of: hash) {
                    path.addLine(to: CGPoint(x: x(below), y: height))
                } else {
                    continue
                }
                context.stroke(path, with: .color(color(index)), lineWidth: 2)
            }
            for parent in row.parentLanes {
                var path = Path()
                path.move(to: CGPoint(x: x(row.lane), y: middle))
                path.addLine(to: CGPoint(x: x(parent), y: height))
                context.stroke(path, with: .color(color(parent)), lineWidth: 2)
            }
            let dot = CGRect(x: x(row.lane) - 4, y: middle - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: dot), with: .color(color(row.lane)))
        }
        .frame(width: GitGraphCanvas.width(lanes: row.laneCount), height: GitGraphCanvas.rowHeight)
    }
}

struct GitGraphView: View {
    @AppStorage("gitGraphRepository") private var repository = ""
    @State private var rows: [GitGraphRow] = []
    @State private var selectedID: String?
    @State private var files: [ChangedFile] = []
    @State private var selectedFile: String?
    @State private var diffLines: [String] = []
    @State private var query = ""
    @State private var note: String?
    @State private var loading = false
    @State private var maxLanes = 1
    @State private var visibleRows: [GitGraphRow] = []


    private func recomputeVisible() {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        visibleRows = needle.isEmpty ? rows : rows.filter { row in
            row.commit.subject.lowercased().contains(needle)
                || row.commit.author.lowercased().contains(needle)
                || row.commit.hash.hasPrefix(needle)
        }
    }

    /// Arrow keys move the selection and keep the new commit in view.
    private func move(_ direction: MoveCommandDirection, proxy: ScrollViewProxy) {
        guard !visibleRows.isEmpty else { return }
        let current = visibleRows.firstIndex { $0.id == selectedID } ?? -1
        let next: Int
        switch direction {
        case .down: next = min(current + 1, visibleRows.count - 1)
        case .up: next = max(current - 1, 0)
        default: return
        }
        let row = visibleRows[next]
        select(row)
        proxy.scrollTo(row.id, anchor: .center)
    }

    private var selectedRow: GitGraphRow? {
        rows.first { $0.id == selectedID }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if loading {
                    ProgressView().controlSize(.small).padding()
                }
                if rows.isEmpty && !loading {
                    EmptyStateView(
                        title: repository.isEmpty ? "Choose a repository" : "No commits to show",
                        message: repository.isEmpty
                            ? "Pick a Git repository to see its branches, merges, and history. CodeOS only reads it."
                            : (note ?? "This repository has no commits yet."),
                        systemImage: "arrow.triangle.branch")
                } else {
                    ScrollViewReader { proxy in
                        graphList(proxy: proxy)
                    }
                }
            }
            .frame(minWidth: 460)
            detail
                .frame(minWidth: 320)
        }
        .navigationTitle("Git Graph")
        .task(id: repository) { await load() }
        .onChange(of: query) { _ in recomputeVisible() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await load() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(repository.isEmpty || loading)
            TextField("Search subject, author, or hash", text: $query)
                .textFieldStyle(.roundedBorder)
            Text(repository.isEmpty ? "" : URL(fileURLWithPath: repository).lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private func graphList(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(visibleRows) { row in
                    commitRow(row).id(row.id)
                }
            }
        }
        .onMoveCommand { direction in move(direction, proxy: proxy) }
        .overlay(alignment: .bottom) {
            if !query.isEmpty {
                Text("Showing matches only. Clear the search to see the full graph.")
                    .font(.caption)
                    .padding(6)
                    .background(.quaternary, in: Capsule())
                    .padding(8)
            }
        }
    }

    private func commitRow(_ row: GitGraphRow) -> some View {
        HStack(spacing: 8) {
            GitGraphCanvas(row: row)
                .frame(width: GitGraphCanvas.width(lanes: maxLanes))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.commit.subject).fontWeight(.medium).lineLimit(1)
                    ForEach(row.commit.refs.prefix(3), id: \.self) { ref in
                        Text(ref)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text("\(row.commit.shortHash) · \(row.commit.author) · \(row.commit.date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: GitGraphCanvas.rowHeight)
        .background(row.id == selectedID ? Color.accentColor.opacity(0.22) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { select(row) }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let commit = selectedRow?.commit {
                Text(commit.subject).font(.headline).textSelection(.enabled)
                Text("\(commit.hash)")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text("\(commit.author) · \(commit.date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(commit.parents.isEmpty
                     ? "Root commit"
                     : "Parents: " + commit.parents.map { String($0.prefix(7)) }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Text("Changed files (\(files.count))").font(.subheadline).fontWeight(.medium)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(files) { file in
                            Button { showDiff(file) } label: {
                                HStack(spacing: 8) {
                                    Text(file.status)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(width: 36, alignment: .leading)
                                    Text(file.path).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                .background(file.path == selectedFile ? Color.accentColor.opacity(0.2) : Color.clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 180)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(diffColor(line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else {
                EmptyStateView(
                    title: "Select a commit",
                    message: "Its changed files and diffs appear here.",
                    systemImage: "doc.text.magnifyingglass")
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .padding(16)
    }

    private func diffColor(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red }
        if line.hasPrefix("@@") { return .accentColor }
        return .primary
    }

    private func load() async {
        guard !repository.isEmpty else {
            rows = []
            visibleRows = []
            return
        }
        loading = true
        defer { loading = false }
        let path = repository
        do {
            rows = try await Task.detached(priority: .utility) { try GitGraph.load(repository: path) }.value
            maxLanes = rows.map(\.laneCount).max() ?? 1
            recomputeVisible()
            note = nil
        } catch {
            rows = []
            note = error.localizedDescription
        }
        selectedID = nil
        files = []
        diffLines = []
        recomputeVisible()
    }

    private func select(_ row: GitGraphRow) {
        selectedID = row.id
        selectedFile = nil
        diffLines = []
        let path = repository
        let hash = row.id
        Task {
            do {
                files = try await Task.detached(priority: .utility) {
                    try GitInspector.changedFiles(repository: path, commit: hash)
                }.value
                note = nil
            } catch {
                files = []
                note = error.localizedDescription
            }
        }
    }

    private func showDiff(_ file: ChangedFile) {
        selectedFile = file.path
        let path = repository
        let hash = selectedID ?? ""
        let target = file.path
        Task {
            do {
                let text = try await Task.detached(priority: .utility) {
                    try GitInspector.diff(repository: path, commit: hash, path: target)
                }.value
                diffLines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
            } catch {
                diffLines = [error.localizedDescription]
            }
        }
    }
}

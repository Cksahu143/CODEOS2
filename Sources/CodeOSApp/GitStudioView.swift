import CodeOSCore
import SwiftUI

struct GitStudioView: View {
    @AppStorage("gitGraphRepository") private var repository = ""
    @State private var status: GitStatus?
    @State private var selected = Set<String>()
    @State private var message = ""
    @State private var command = ""
    @State private var log: [String] = []
    @State private var note: String?
    @State private var busy = false
    @State private var pending: [String]?
    @State private var pendingRisk: GitRisk?

    private var stagedCount: Int {
        (status?.entries ?? []).filter { isStaged($0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                changes.frame(minWidth: 380)
                VStack(alignment: .leading, spacing: 10) {
                    commitBox
                    Divider()
                    console
                }
                .padding(12)
                .frame(minWidth: 320)
            }
        }
        .navigationTitle("Git Studio")
        .task(id: repository) { await refresh() }
        .confirmationDialog(
            pendingRisk == .destructive ? "This can lose work" : "Run this Git command?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { args in
            Button(pendingRisk == .destructive ? "Run Anyway" : "Run", role: pendingRisk == .destructive ? .destructive : nil) {
                Task { await execute(args) }
            }
        } message: { args in
            Text("git " + args.joined(separator: " "))
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("Choose Repository…") {
                if let path = FolderPicker.chooseFolder(prompt: "Choose") { repository = path }
            }
            Button {
                Task { await refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(repository.isEmpty || busy)
            if let branch = status?.branch {
                Label(branch, systemImage: "arrow.triangle.branch").font(.callout)
            }
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
    }

    private var changes: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Changes (\(status?.entries.count ?? 0))").font(.headline)
                Spacer()
                Button("Select All") { selected = Set((status?.entries ?? []).map(\.path)) }
                Button("Clear") { selected = [] }
            }
            HStack {
                Button("Stage Selected") { stageSelected() }.disabled(selected.isEmpty || busy)
                Button("Unstage Selected") { unstageSelected() }.disabled(selected.isEmpty || busy)
                Button("Stage Everything") { stageAll() }.disabled(busy || (status?.entries.isEmpty ?? true))
            }
            if status?.entries.isEmpty ?? true {
                EmptyStateView(title: "Nothing to commit", message: "Edit files in the repository, and they appear here.", systemImage: "checkmark.circle")
            } else {
                List {
                    ForEach(status?.entries ?? [], id: \.path) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: selected.contains(entry.path) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selected.contains(entry.path) ? Color.accentColor : Color.secondary)
                            Text(code(entry))
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 40, alignment: .leading)
                            Text(entry.path).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(isStaged(entry) ? "staged" : "unstaged")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(entry.path) }
                    }
                }
            }
        }
        .padding(12)
    }

    private var commitBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Commit (\(stagedCount) staged)").font(.headline)
            TextEditor(text: $message)
                .font(.callout)
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Button {
                Task { await commit() }
            } label: {
                Label("Commit Staged Changes", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || stagedCount == 0 || message.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var console: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Git console").font(.headline)
            Text("Type a Git command without the word git. Example: log --oneline -5")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("status", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { runTyped() }
                Button("Run") { runTyped() }
                    .disabled(busy || command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView {
                Text(log.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 160)
            .padding(8)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
        }
    }

    // MARK: Helpers

    private func isStaged(_ entry: GitStatus.Entry) -> Bool {
        entry.indexCode != " " && entry.indexCode != "?"
    }

    private func code(_ entry: GitStatus.Entry) -> String {
        String([entry.indexCode, entry.worktreeCode])
    }

    private func toggle(_ path: String) {
        if selected.contains(path) { selected.remove(path) } else { selected.insert(path) }
    }

    private func refresh() async {
        guard !repository.isEmpty else {
            status = nil
            return
        }
        let path = repository
        do {
            status = try await Task.detached(priority: .utility) { try GitStudio.status(in: path) }.value
            note = nil
            selected = selected.filter { p in (status?.entries ?? []).contains { $0.path == p } }
        } catch {
            status = nil
            note = error.localizedDescription
        }
    }

    private func stageSelected() {
        perform("git add", paths: Array(selected)) { try GitStudio.stage($0, in: repository) }
    }

    private func unstageSelected() {
        let staged = Array(selected.filter { path in
            (status?.entries ?? []).contains { $0.path == path && isStaged($0) }
        })
        perform("git restore --staged", paths: staged) { try GitStudio.unstage($0, in: repository) }
    }

    private func stageAll() {
        busy = true
        let path = repository
        Task {
            defer { busy = false }
            do {
                let result = try await Task.detached(priority: .utility) { try GitStudio.stageEverything(in: path) }.value
                record("git add -A", result)
            } catch {
                note = error.localizedDescription
            }
            await refresh()
        }
    }

    private func perform(_ label: String, paths: [String], _ action: @escaping ([String]) throws -> ProcessResult) {
        guard !paths.isEmpty else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let result = try await Task.detached(priority: .utility) { try action(paths) }.value
                record("\(label) \(paths.joined(separator: " "))", result)
                selected = []
            } catch {
                note = error.localizedDescription
            }
            await refresh()
        }
    }

    private func commit() async {
        busy = true
        defer { busy = false }
        let path = repository
        let text = message
        do {
            let result = try await Task.detached(priority: .utility) { try GitStudio.commit(message: text, in: path) }.value
            record("git commit", result)
            if result.succeeded { message = "" }
        } catch {
            note = error.localizedDescription
        }
        await refresh()
    }

    private func runTyped() {
        guard let args = GitCommandLine.split(command), !args.isEmpty else {
            note = "That command has an unbalanced quote."
            return
        }
        switch GitCommandPolicy.classify(args) {
        case .blocked(let reason):
            note = reason
        case .readOnly:
            Task { await execute(args) }
        case .changesState:
            pendingRisk = .changesState
            pending = args
        case .destructive:
            pendingRisk = .destructive
            pending = args
        }
    }

    private func execute(_ args: [String]) async {
        busy = true
        defer { busy = false }
        let path = repository
        do {
            let result = try await Task.detached(priority: .utility) { try GitStudio.run(args, in: path) }.value
            record("git " + args.joined(separator: " "), result)
            command = ""
        } catch {
            note = error.localizedDescription
        }
        await refresh()
    }

    private func record(_ title: String, _ result: ProcessResult) {
        let output = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        let status = result.succeeded ? "" : "  (exit \(result.exitCode))"
        log.append("$ \(title)\(status)")
        if !output.isEmpty {
            log.append(String(output.prefix(20_000)))
        }
        log.append("")
        note = result.succeeded ? "Done." : "Git reported an error. See the console."
    }
}

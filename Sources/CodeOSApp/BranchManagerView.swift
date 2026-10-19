import CodeOSCore
import SwiftUI

struct BranchManagerView: View {
    @AppStorage("gitGraphRepository") private var repository = ""
    @State private var branches: [BranchInfo] = []
    @State private var note: String?
    @State private var busy = false
    @State private var creating = false
    @State private var switchTarget: String?
    @State private var deleteTarget: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Branches").font(.title3).fontWeight(.semibold)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("New Branch…") { creating = true }
                    .disabled(repository.isEmpty || busy)
                Button {
                    Task { await load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(repository.isEmpty || busy)
            }
            if repository.isEmpty {
                EmptyStateView(title: "Choose a repository", message: "Use Choose Repository in the Studio header.", systemImage: "folder")
            } else if branches.isEmpty {
                EmptyStateView(title: "No branches yet", message: "Make a first commit, then branches appear here.", systemImage: "arrow.triangle.branch")
            } else {
                List(branches) { branch in
                    row(branch)
                }
            }
            if let note {
                Text(note).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding(16)
        .task(id: repository) { await load() }
        .sheet(isPresented: $creating) {
            NameSheet(title: "New Branch", actionTitle: "Create and Switch", name: "") { name in
                validateAndCreate(name)
            }
        }
        .confirmationDialog(
            "Switch branches?",
            isPresented: Binding(get: { switchTarget != nil }, set: { if !$0 { switchTarget = nil } }),
            presenting: switchTarget
        ) { name in
            Button("Switch to \(name)") {
                let path = repository
                runOperation("Switched to \(name).") { try BranchManager.switchTo(name, in: path) }
            }
        } message: { _ in
            Text("Git refuses the switch if your uncommitted changes would be overwritten. Nothing is discarded.")
        }
        .confirmationDialog(
            "Delete this branch?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            presenting: deleteTarget
        ) { name in
            Button("Delete \(name)", role: .destructive) {
                let path = repository
                runOperation("Deleted \(name).") { try BranchManager.deleteMerged(name, in: path) }
            }
        } message: { _ in
            Text("Only branches fully merged into their upstream or HEAD are deleted. Git refuses otherwise.")
        }
    }

    private func row(_ branch: BranchInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: branch.isCurrent ? "circle.fill" : (branch.isRemote ? "cloud" : "circle"))
                .foregroundStyle(branch.isCurrent ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(branch.name).fontWeight(branch.isCurrent ? .bold : .regular)
                    if branch.isRemote {
                        Text("remote").font(.caption2).padding(.horizontal, 5).background(.quaternary, in: Capsule())
                    }
                }
                if let upstream = branch.upstream {
                    Text("tracks \(upstream)").font(.caption).foregroundStyle(.secondary)
                }
                Text("\(branch.lastCommitDate) · \(branch.lastCommitSubject)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if branch.upstream != nil {
                Text("↑\(branch.ahead) ↓\(branch.behind)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !branch.isCurrent && !branch.isRemote {
                Button("Switch") { switchTarget = branch.name }
                    .disabled(busy)
                Button("Delete") { deleteTarget = branch.name }
                    .disabled(busy)
            }
        }
        .padding(.vertical, 4)
    }

    /// Checks the name synchronously, because the sheet needs an answer before it closes.
    private func validateAndCreate(_ name: String) -> String? {
        do {
            guard try BranchManager.isValidNewName(name, in: repository) else {
                return "Git does not allow that branch name."
            }
        } catch {
            return error.localizedDescription
        }
        let path = repository
        runOperation("Created and switched to \(name).") { try BranchManager.create(name, in: path) }
        return nil
    }

    private func runOperation(_ success: String, _ operation: @escaping () throws -> ProcessResult) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let result = try await Task.detached(priority: .utility) { try operation() }.value
                note = result.succeeded
                    ? success
                    : "Git said: " + result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                note = error.localizedDescription
            }
            await load()
        }
    }

    private func load() async {
        guard !repository.isEmpty else {
            branches = []
            return
        }
        let path = repository
        do {
            branches = try await Task.detached(priority: .utility) {
                try BranchManager.list(repository: path)
            }.value
        } catch {
            branches = []
            note = error.localizedDescription
        }
    }
}

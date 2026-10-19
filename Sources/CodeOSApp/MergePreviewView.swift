import CodeOSCore
import SwiftUI

struct MergePreviewView: View {
    @AppStorage("gitGraphRepository") private var repository = ""
    @State private var branches: [String] = []
    @State private var branchA = ""
    @State private var branchB = ""
    @State private var result: MergePreviewResult?
    @State private var note: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Merge preview").font(.title3).fontWeight(.semibold)
                Text("Nothing in your working tree or branches changes here. Git may write temporary objects while it checks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Picker("Branch A", selection: $branchA) {
                        ForEach(branches, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(width: 220)
                    Text("merge into or with").foregroundStyle(.secondary)
                    Picker("Branch B", selection: $branchB) {
                        ForEach(branches, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(width: 220)
                    Button("Preview") { Task { await preview() } }
                        .disabled(busy || branchA.isEmpty || branchB.isEmpty || branchA == branchB)
                    Button {
                        Task { await loadBranches() }
                    } label: {
                        Label("Reload branches", systemImage: "arrow.clockwise")
                    }
                    .disabled(repository.isEmpty)
                    if busy { ProgressView().controlSize(.small) }
                }
                if let note {
                    Text(note).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let result {
                    summary(result)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: repository) { await loadBranches() }
    }

    @ViewBuilder
    private func summary(_ result: MergePreviewResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(branchA) has \(result.divergence.onlyInA) commit(s) that \(branchB) lacks. \(branchB) has \(result.divergence.onlyInB) that \(branchA) lacks.")
                .font(.callout)
            if let predicted = result.predictedConflicts {
                if predicted.isEmpty {
                    Label("No conflicts predicted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Predicted conflicts in \(predicted.count) file(s)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    ForEach(predicted, id: \.self) { file in
                        Text(file).font(.system(.callout, design: .monospaced)).padding(.leading, 20)
                    }
                }
            }
            fileList("Changed on \(branchA)", result.changedOnA)
            fileList("Changed on \(branchB)", result.changedOnB)
            fileList("Changed on both (review these)", result.changedOnBoth)
        }
    }

    private func fileList(_ title: String, _ files: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) (\(files.count))").font(.subheadline).fontWeight(.medium)
            ForEach(files.prefix(200), id: \.self) { file in
                Text(file).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private func loadBranches() async {
        guard !repository.isEmpty else { return }
        let path = repository
        do {
            let list = try await Task.detached(priority: .utility) {
                let result = try GitStudio.run(["branch", "--format=%(refname:short)"], in: path)
                guard result.succeeded else {
                    throw GitError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return MergePreview.parseNameList(result.stdout)
            }.value
            branches = list
            if !list.contains(branchA) { branchA = list.first ?? "" }
            if !list.contains(branchB) { branchB = list.dropFirst().first ?? list.first ?? "" }
            note = nil
        } catch {
            branches = []
            note = error.localizedDescription
        }
    }

    private func preview() async {
        busy = true
        defer { busy = false }
        let path = repository
        let a = branchA
        let b = branchB
        do {
            result = try await Task.detached(priority: .utility) {
                try MergePreview.preview(repository: path, branchA: a, branchB: b)
            }.value
            note = result?.note
        } catch {
            result = nil
            note = error.localizedDescription
        }
    }
}

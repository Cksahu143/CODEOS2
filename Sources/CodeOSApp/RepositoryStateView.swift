import AppKit
import CodeOSCore
import SwiftUI

struct RepositoryStateView: View {
    @AppStorage("gitGraphRepository") private var repository = ""
    @State private var findings: [RepositoryFinding] = []
    @State private var note: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Repository state").font(.title3).fontWeight(.semibold)
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    Button {
                        Task { await load() }
                    } label: {
                        Label("Check Again", systemImage: "arrow.clockwise")
                    }
                    .disabled(repository.isEmpty || busy)
                }
                Text("Read-only. Shows what Git is in the middle of, and the command that resolves it. Nothing runs until you run it yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if repository.isEmpty {
                    EmptyStateView(title: "Choose a repository", message: "Use Choose Repository in the Studio header.", systemImage: "folder")
                } else {
                    ForEach(findings) { finding in
                        row(finding)
                    }
                }
                if let note {
                    Text(note).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: repository) { await load() }
    }

    private func row(_ finding: RepositoryFinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol(finding.severity))
                    .foregroundStyle(color(finding.severity))
                Text(finding.title).fontWeight(.medium)
            }
            Text(finding.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let command = finding.suggestedCommand {
                HStack {
                    Text(command)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button("Copy") { copy(command) }
                }
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func symbol(_ severity: FindingSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.circle.fill"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func color(_ severity: FindingSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func load() async {
        guard !repository.isEmpty else { return }
        busy = true
        defer { busy = false }
        let path = repository
        do {
            findings = try await Task.detached(priority: .utility) {
                try RepositoryStateExplainer.explain(repository: path)
            }.value
            note = nil
        } catch {
            findings = []
            note = error.localizedDescription
        }
    }
}

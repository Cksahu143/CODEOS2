import CodeOSCore
import SwiftUI

struct DeveloperToolsView: View {
    @AppStorage("lastRepositoryPath") private var repoPath = ""
    @State private var tools: [ToolStatus] = []
    @State private var isScanningTools = false
    @State private var gitStatus: GitStatus?
    @State private var gitError: String?
    @State private var isLoadingGit = false

    private static let toolNames = ["git", "swift", "node", "npm", "tsc"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                toolchainSection
                repositorySection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Developer Tools")
        .task { await scanTools() }
        .task(id: repoPath) {
            if !repoPath.isEmpty { await loadGitStatus() }
        }
    }

    private var toolchainSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Toolchain").font(.headline)
                Spacer()
                Button { Task { await scanTools() } } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(isScanningTools)
            }
            if tools.isEmpty {
                ProgressView().controlSize(.small)
            }
            ForEach(tools) { tool in
                HStack(spacing: 10) {
                    Image(systemName: tool.isInstalled ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(tool.isInstalled ? Color.green : Color.secondary)
                    Text(tool.name)
                        .fontWeight(.medium)
                        .frame(width: 60, alignment: .leading)
                    Text(toolDescription(tool))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
            }
            Text("Git and Swift can show a prompt to install Command Line Tools if they are not set up yet. CodeOS never installs tools itself.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var repositorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Repository status").font(.headline)
                Spacer()
                Button("Choose Repository…") {
                    if let path = FolderPicker.chooseFolder(prompt: "Choose") { repoPath = path }
                }
                Button("Open in Terminal") { openRepositoryInTerminal() }
                    .disabled(repoPath.isEmpty)
            }

            if repoPath.isEmpty {
                Text("Choose a Git repository to see its branch and changes. CodeOS only reads status and never changes the repository.")
                    .foregroundStyle(.secondary)
            } else {
                Text(repoPath)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
                if isLoadingGit {
                    ProgressView().controlSize(.small)
                }
                if let gitError {
                    Text(gitError).foregroundStyle(.red).font(.callout).textSelection(.enabled)
                }
                if let status = gitStatus {
                    statusView(status)
                }
            }
        }
    }

    private func statusView(_ status: GitStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary)
                Text(status.branch ?? "Detached HEAD").fontWeight(.medium)
                if status.aheadCount > 0 || status.behindCount > 0 {
                    Text("↑\(status.aheadCount) ↓\(status.behindCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(status.isClean
                 ? "Working tree clean"
                 : "\(status.changedCount) changed · \(status.untrackedCount) untracked")
                .font(.callout)
                .foregroundStyle(.secondary)

            let shown = Array(status.entries.prefix(200).enumerated())
            ForEach(shown, id: \.offset) { _, entry in
                HStack(spacing: 10) {
                    Text(String([entry.indexCode, entry.worktreeCode]))
                        .font(.system(.callout, design: .monospaced))
                        .frame(width: 30, alignment: .leading)
                    Text(entry.path)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if status.entries.count > shown.count {
                Text("…and \(status.entries.count - shown.count) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func toolDescription(_ tool: ToolStatus) -> String {
        guard tool.isInstalled else { return "Not installed" }
        return tool.version ?? tool.path ?? "Installed"
    }

    private func scanTools() async {
        isScanningTools = true
        let names = Self.toolNames
        tools = await Task.detached(priority: .utility) {
            names.map { ToolDetector.status(for: $0) }
        }.value
        isScanningTools = false
    }

    private func loadGitStatus() async {
        let path = repoPath
        isLoadingGit = true
        defer { isLoadingGit = false }
        do {
            let result = try await Task.detached(priority: .utility) {
                try ProcessRunner.run(
                    executable: GitTool.resolved ?? "/usr/bin/git",
                    arguments: ["status", "--porcelain=v1", "--branch"],
                    workingDirectory: path
                )
            }.value
            guard result.succeeded else {
                gitStatus = nil
                let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                gitError = detail.isEmpty ? "Git could not read this folder." : detail
                return
            }
            gitStatus = GitStatusParser.parse(result.stdout)
            gitError = nil
        } catch {
            gitStatus = nil
            gitError = error.localizedDescription
        }
    }

    private func openRepositoryInTerminal() {
        let path = repoPath
        Task {
            do {
                _ = try await AppActionExecutor().execute(.openTerminal(path: path))
            } catch {
                gitError = error.localizedDescription
            }
        }
    }
}

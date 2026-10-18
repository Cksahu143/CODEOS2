import CodeOSCore
import SwiftUI

struct GamesView: View {
    @AppStorage("gameProjectFolder") private var folder = ""
    @State private var project: GameProject?
    @State private var output = ""
    @State private var running: String?
    @State private var note: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Game project").font(.title2).fontWeight(.semibold)
                    Spacer()
                    Button("Choose Project Folder…") {
                        if let path = FolderPicker.chooseFolder(prompt: "Choose") { folder = path }
                    }
                    Button {
                        refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(folder.isEmpty)
                }
                if let project {
                    details(project)
                    scripts(project)
                    if !output.isEmpty || running != nil {
                        outputView
                    }
                } else {
                    EmptyStateView(
                        title: "Choose a game project",
                        message: "Pick a folder that contains a package.json. CodeOS reads it and shows the engine, scripts, and any problems. It never changes your files.",
                        systemImage: "gamecontroller")
                        .frame(height: 260)
                }
                if let note {
                    Text(note).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Games")
        .task(id: folder) { refresh() }
    }

    private func details(_ project: GameProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.name).font(.headline)
            Text(project.path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(spacing: 24) {
                info("Engine", project.engines.map { "\($0.name) \($0.version)" }.joined(separator: ", ").ifEmpty("None found"))
                info("TypeScript", project.usesTypeScript ? "Yes" : "No")
                info("Bundler", project.bundler ?? "None found")
                info("index.html", project.hasIndexHTML ? "Found" : "Missing")
                info("Assets", project.assetFolders.isEmpty ? "None found" : project.assetFolders.joined(separator: ", "))
            }
            if !project.issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(project.issues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func info(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout)
        }
    }

    private func scripts(_ project: GameProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scripts").font(.headline)
            let runnable = GameProjectRunner.runnable(project.scripts)
            if runnable.isEmpty {
                Text("No build, test, lint, or check script is defined.").foregroundStyle(.secondary)
            }
            ForEach(runnable, id: \.self) { script in
                HStack {
                    Text(script).font(.system(.body, design: .monospaced))
                    Spacer()
                    Button {
                        run(script, in: project)
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .disabled(running != nil)
                }
            }
            let others = project.scripts.filter { !GameProjectRunner.runnableScripts.contains($0) }
            if !others.isEmpty {
                Text("Not run here (dev servers and long-running scripts): " + others.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outputView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(running.map { "Running “\($0)”…" } ?? "Output").font(.headline)
                if running != nil { ProgressView().controlSize(.small) }
            }
            ScrollView {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 260)
            .padding(8)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
        }
    }

    private func refresh() {
        guard !folder.isEmpty else {
            project = nil
            return
        }
        project = GameProjectDetector.inspect(folder: folder)
    }

    private func run(_ script: String, in project: GameProject) {
        guard let npm = ToolDetector.locate("npm") else {
            note = "npm was not found. Install Node.js from nodejs.org, then try again."
            return
        }
        running = script
        output = ""
        note = nil
        Task {
            do {
                let result = try await Task.detached(priority: .utility) {
                    try GameProjectRunner.run(project: project, script: script, npmPath: npm)
                }.value
                let lines = (result.stdout + result.stderr)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                output = lines.suffix(300).joined(separator: "\n")
                note = result.succeeded
                    ? "“\(script)” finished successfully."
                    : (result.timedOut ? "“\(script)” was stopped after 15 minutes." : "“\(script)” failed with exit code \(result.exitCode).")
            } catch {
                note = error.localizedDescription
            }
            running = nil
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

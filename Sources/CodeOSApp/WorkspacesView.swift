import AppKit
import CodeOSCore
import SwiftUI

struct WorkspacesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedID: UUID?
    @State private var editing: Workspace?
    @State private var confirmingDelete = false
    @State private var terminalNote: String?

    private var selected: Workspace? {
        store.configuration.workspaces.first { $0.id == selectedID }
    }

    var body: some View {
        HSplitView {
            List(selection: $selectedID) {
                ForEach(store.configuration.workspaces) { workspace in
                    Label(workspace.name, systemImage: "rectangle.3.group")
                        .tag(workspace.id)
                }
            }
            .frame(minWidth: 200, idealWidth: 220)

            Group {
                if let workspace = selected {
                    detail(for: workspace)
                } else {
                    EmptyStateView(
                        title: "Choose a workspace",
                        message: "Workspaces open your project folder, editor, documentation, and supporting apps in one step."
                    )
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Workspaces")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = Workspace(name: "", projectPath: "")
                } label: {
                    Label("New Workspace", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { workspace in
            WorkspaceEditor(workspace: workspace) { saved in
                store.upsert(saved)
                selectedID = saved.id
            }
            .environmentObject(store)
        }
        .confirmationDialog("Delete this workspace?", isPresented: $confirmingDelete) {
            Button("Delete Workspace", role: .destructive) {
                if let id = selectedID { store.deleteWorkspace(id: id) }
                selectedID = nil
            }
        } message: {
            Text("Your project folder and its files are not affected.")
        }
    }

    @ViewBuilder
    private func detail(for workspace: Workspace) -> some View {
        let running = store.runningWorkflowID == workspace.id
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(workspace.name).font(.title).fontWeight(.semibold)

                HStack(spacing: 10) {
                    Button {
                        Task { await store.run(WorkspaceLauncher.workflow(for: workspace)) }
                    } label: {
                        Label(running ? "Opening…" : "Open Workspace", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.runningWorkflowID != nil)

                    Button("Edit") { editing = workspace }
                    Button {
                        openITerm(workspace.projectPath)
                    } label: {
                        Label("Open in iTerm2", systemImage: "terminal")
                    }
                    Button("Delete", role: .destructive) { confirmingDelete = true }
                }

                infoRow("Project folder", workspace.projectPath, monospaced: true)
                if let terminalNote {
                    Text(terminalNote).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                infoRow(
                    "Editor",
                    workspace.editorBundleID.map { store.appName(for: $0) } ?? "Default (Finder)"
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Documentation").font(.headline)
                    if workspace.documentationURLs.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    } else {
                        ForEach(workspace.documentationURLs, id: \.self) { link in
                            Text(link).font(.callout).textSelection(.enabled)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Supporting apps").font(.headline)
                    if workspace.supportingAppBundleIDs.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    } else {
                        ForEach(workspace.supportingAppBundleIDs, id: \.self) { bundleID in
                            Text(store.appName(for: bundleID)).font(.callout)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func openITerm(_ path: String) {
        terminalNote = nil
        Task {
            do {
                try await Task.detached(priority: .utility) { try ITermLauncher.open(folder: path) }.value
                terminalNote = "Opened \(path) in iTerm2."
            } catch {
                terminalNote = error.localizedDescription
            }
        }
    }

    private func infoRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}

struct WorkspaceEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Workspace
    @State private var documentationText: String
    @State private var problems: [String] = []
    let onSave: (Workspace) -> Void

    init(workspace: Workspace, onSave: @escaping (Workspace) -> Void) {
        _draft = State(initialValue: workspace)
        _documentationText = State(initialValue: workspace.documentationURLs.joined(separator: "\n"))
        self.onSave = onSave
    }

    private var isNew: Bool {
        !store.configuration.workspaces.contains { $0.id == draft.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New Workspace" : "Edit Workspace").font(.title2)

            Form {
                TextField("Name", text: $draft.name)

                HStack {
                    TextField("Project folder", text: $draft.projectPath)
                        .font(.system(.body, design: .monospaced))
                    Button("Choose…") {
                        if let path = FolderPicker.chooseFolder(prompt: "Choose Project") {
                            draft.projectPath = path
                        }
                    }
                }

                Picker("Editor", selection: $draft.editorBundleID) {
                    Text("Default (Finder)").tag(String?.none)
                    ForEach(store.installedApps) { app in
                        Text(app.name).tag(Optional(app.bundleID))
                    }
                }

                Section("Documentation links (one per line)") {
                    TextEditor(text: $documentationText)
                        .font(.callout)
                        .frame(height: 70)
                }

                Section("Supporting apps") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(store.installedApps) { app in
                                Toggle(app.name, isOn: supportingBinding(for: app.bundleID))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 130)
                }
            }
            .formStyle(.grouped)

            ForEach(problems, id: \.self) { problem in
                Text(problem).foregroundStyle(.red).font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540, height: 620)
    }

    private func supportingBinding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { draft.supportingAppBundleIDs.contains(bundleID) },
            set: { isOn in
                if isOn {
                    if !draft.supportingAppBundleIDs.contains(bundleID) {
                        draft.supportingAppBundleIDs.append(bundleID)
                    }
                } else {
                    draft.supportingAppBundleIDs.removeAll { $0 == bundleID }
                }
            }
        )
    }

    private func save() {
        var workspace = draft
        workspace.name = workspace.name.trimmingCharacters(in: .whitespaces)
        workspace.projectPath = (workspace.projectPath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        workspace.documentationURLs = documentationText
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let issues = Validation.problems(in: workspace)
        guard issues.isEmpty else {
            problems = issues
            return
        }
        onSave(workspace)
        dismiss()
    }
}

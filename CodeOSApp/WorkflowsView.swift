import AppKit
import CodeOSCore
import SwiftUI

struct WorkflowsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: Workflow?
    @State private var pendingCommandRun: Workflow?

    var body: some View {
        Group {
            if store.configuration.workflows.isEmpty {
                EmptyStateView(
                    title: "No workflows yet",
                    message: "A workflow is a list of steps you choose: open folders, links, apps, Git status, appearance changes, or commands. CodeOS runs them in order and reports each result.",
                    systemImage: "bolt.horizontal"
                )
            } else {
                List {
                    ForEach(store.configuration.workflows) { workflow in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workflow.name).fontWeight(.medium)
                                Text("\(workflow.actions.count) step(s)\(workflow.runsCommands ? " · runs commands" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                if workflow.runsCommands {
                                    pendingCommandRun = workflow
                                } else {
                                    Task { await store.run(workflow) }
                                }
                            } label: {
                                Label("Run", systemImage: "play.fill")
                            }
                            .disabled(store.runningWorkflowID != nil)
                            Button { editing = workflow } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .labelStyle(.iconOnly)
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button("Duplicate") {
                                var copy = workflow
                                copy.id = UUID()
                                copy.name = workflow.name + " copy"
                                store.upsert(copy)
                            }
                            Divider()
                            Button("Delete", role: .destructive) { store.deleteWorkflow(id: workflow.id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Workflows")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = Workflow(name: "", actions: [ActionDraft(kind: .openFolder).action])
                } label: {
                    Label("New Workflow", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { workflow in
            WorkflowEditor(workflow: workflow) { store.upsert($0) }
                .environmentObject(store)
        }
        .confirmationDialog(
            "Run this workflow?",
            isPresented: Binding(get: { pendingCommandRun != nil }, set: { if !$0 { pendingCommandRun = nil } }),
            presenting: pendingCommandRun
        ) { workflow in
            Button("Run Workflow") { Task { await store.run(workflow) } }
        } message: { workflow in
            Text("“\(workflow.name)” runs commands on this Mac. Continue only if you wrote or trust those commands.")
        }
    }
}

/// Editable form model for one step. Keeps UI state separate from the stored `WorkflowAction`.
struct ActionDraft: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case openFolder, openFolderInApp, openURL, launchApp, openTerminal, gitStatus, setSystemAppearance, runCommand

        var id: String { rawValue }

        var title: String {
            switch self {
            case .openFolder: return "Open folder"
            case .openFolderInApp: return "Open folder in app"
            case .openURL: return "Open link"
            case .launchApp: return "Launch app"
            case .openTerminal: return "Open Terminal at folder"
            case .gitStatus: return "Check Git status"
            case .setSystemAppearance: return "Set macOS appearance"
            case .runCommand: return "Run a command"
            }
        }

        var needsApp: Bool { self == .openFolderInApp || self == .launchApp }
        var needsLink: Bool { self == .openURL }
        var needsFolder: Bool { self == .openFolder || self == .openTerminal || self == .gitStatus }
        var needsCommand: Bool { self == .runCommand }
        var needsAppearance: Bool { self == .setSystemAppearance }
    }

    let id = UUID()
    var kind: Kind
    var text = ""
    var bundleID = ""
    var arguments = ""
    var workingDirectory = ""
    var darkMode = true

    init(kind: Kind) {
        self.kind = kind
    }

    init(_ action: WorkflowAction) {
        switch action {
        case .openFolder(let path):
            kind = .openFolder; text = path
        case .openFolderInApp(let bundleID, let path):
            kind = .openFolderInApp; text = path; self.bundleID = bundleID
        case .openURL(let link):
            kind = .openURL; text = link
        case .launchApp(let bundleID):
            kind = .launchApp; self.bundleID = bundleID
        case .openTerminal(let path):
            kind = .openTerminal; text = path
        case .gitStatus(let path):
            kind = .gitStatus; text = path
        case .setSystemAppearance(let dark):
            kind = .setSystemAppearance; darkMode = dark
        case .runCommand(let executable, let args, let workingFolder):
            kind = .runCommand
            text = executable
            arguments = args.joined(separator: "\n")
            workingDirectory = workingFolder ?? ""
        }
    }

    var action: WorkflowAction {
        switch kind {
        case .openFolder: return .openFolder(path: text)
        case .openFolderInApp: return .openFolderInApp(bundleID: bundleID, path: text)
        case .openURL: return .openURL(text)
        case .launchApp: return .launchApp(bundleID: bundleID)
        case .openTerminal: return .openTerminal(path: text)
        case .gitStatus: return .gitStatus(repoPath: text)
        case .setSystemAppearance: return .setSystemAppearance(dark: darkMode)
        case .runCommand:
            let args = arguments
                .split(whereSeparator: { $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let folder = workingDirectory.trimmingCharacters(in: .whitespaces)
            return .runCommand(executable: text.trimmingCharacters(in: .whitespaces),
                               arguments: args,
                               workingDirectory: folder.isEmpty ? nil : folder)
        }
    }
}

struct WorkflowEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var steps: [ActionDraft]
    @State private var problems: [String] = []
    private let original: Workflow
    let onSave: (Workflow) -> Void

    init(workflow: Workflow, onSave: @escaping (Workflow) -> Void) {
        original = workflow
        _name = State(initialValue: workflow.name)
        _steps = State(initialValue: workflow.actions.isEmpty
            ? [ActionDraft(kind: .openFolder)]
            : workflow.actions.map { ActionDraft($0) })
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(original.name.isEmpty ? "New Workflow" : "Edit Workflow").font(.title2)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach($steps) { $step in
                        stepRow($step)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Button {
                steps.append(ActionDraft(kind: .openFolder))
            } label: {
                Label("Add Step", systemImage: "plus")
            }

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
        .frame(width: 600, height: 620)
    }

    @ViewBuilder
    private func stepRow(_ step: Binding<ActionDraft>) -> some View {
        let value = step.wrappedValue
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Action", selection: step.kind) {
                    ForEach(ActionDraft.Kind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                Spacer()
                Button(role: .destructive) {
                    steps.removeAll { $0.id == value.id }
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
                .labelStyle(.iconOnly)
                .disabled(steps.count == 1)
            }

            if value.kind.needsApp {
                Picker("Application", selection: step.bundleID) {
                    Text("Choose an application…").tag("")
                    ForEach(store.installedApps) { app in
                        Text(app.name).tag(app.bundleID)
                    }
                }
                .labelsHidden()
            }

            if value.kind.needsFolder || value.kind.needsLink {
                HStack {
                    TextField(value.kind.needsLink ? "https://…" : "/absolute/path", text: step.text)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: value.kind.needsLink ? .default : .monospaced))
                    if value.kind.needsFolder {
                        Button("Choose…") {
                            if let path = FolderPicker.chooseFolder() { step.wrappedValue.text = path }
                        }
                    }
                }
            }

            if value.kind.needsAppearance {
                Toggle("Dark appearance", isOn: step.darkMode)
                Text("Changes the whole Mac. The first time, macOS asks permission for CodeOS to control System Events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if value.kind.needsCommand {
                TextField("Executable, e.g. /usr/bin/swift", text: step.text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Text("Arguments, one per line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: step.arguments)
                    .font(.system(.callout, design: .monospaced))
                    .frame(height: 60)
                HStack {
                    TextField("Working folder (optional)", text: step.workingDirectory)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button("Choose…") {
                        if let path = FolderPicker.chooseFolder() { step.wrappedValue.workingDirectory = path }
                    }
                }
                Button("Choose Executable…") {
                    if let path = chooseExecutable() { step.wrappedValue.text = path }
                }
                .buttonStyle(.link)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func chooseExecutable() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func save() {
        let workflow = Workflow(
            id: original.id,
            name: name.trimmingCharacters(in: .whitespaces),
            actions: steps.map { $0.action }
        )
        let issues = Validation.problems(in: workflow)
        guard issues.isEmpty else {
            problems = issues
            return
        }
        onSave(workflow)
        dismiss()
    }
}

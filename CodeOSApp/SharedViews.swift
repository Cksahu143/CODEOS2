import AppKit
import CodeOSCore
import SwiftUI

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func bytes(_ value: UInt64) -> String {
        bytes(Int64(clamping: value))
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

enum FolderPicker {
    static func chooseFolder(prompt: String = "Choose") -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func chooseApplication() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["app"]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Open With"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Small sheet asking for one name (rename, new folder).
struct NameSheet: View {
    let title: String
    let actionTitle: String
    @State var name: String
    let onConfirm: (String) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(confirm)
            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(actionTitle, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func confirm() {
        if let problem = onConfirm(name.trimmingCharacters(in: .whitespaces)) {
            error = problem
        } else {
            dismiss()
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "tray"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct RunReportView: View {
    let report: WorkflowRunReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.workflowName).font(.title2).fontWeight(.semibold)
            Text(headline)
                .foregroundStyle(report.allSucceeded ? Color.green : Color.orange)
            if !report.problems.isEmpty {
                ForEach(report.problems, id: \.self) { problem in
                    Text(problem).foregroundStyle(.red).font(.callout)
                }
            }
            List(Array(report.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol(for: step))
                        .foregroundStyle(color(for: step))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Step \(index + 1)").fontWeight(.medium)
                        Text(step.text)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 440)
    }

    private var headline: String {
        if !report.problems.isEmpty { return "Not run: the workflow needs changes." }
        if report.allSucceeded { return "All steps completed." }
        return "\(report.failureCount) step(s) failed. The other steps were still attempted."
    }

    private func symbol(for step: StepResult) -> String {
        switch step {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .skipped: return "minus.circle"
        }
    }

    private func color(for step: StepResult) -> Color {
        switch step {
        case .succeeded: return .green
        case .failed: return .red
        case .skipped: return .secondary
        }
    }
}

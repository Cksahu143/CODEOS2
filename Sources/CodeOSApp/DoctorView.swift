import AppKit
import CodeOSCore
import SwiftUI

struct DoctorView: View {
    @State private var findings: [DoctorFinding] = []
    @State private var checking = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Environment Doctor").font(.title2).fontWeight(.semibold)
                    Spacer()
                    if checking { ProgressView().controlSize(.small) }
                    Button("Copy Report") { copyReport() }
                        .disabled(findings.isEmpty)
                    Button {
                        Task { await scan() }
                    } label: {
                        Label("Check Again", systemImage: "arrow.clockwise")
                    }
                    .disabled(checking)
                }
                Text("Read-only. CodeOS checks your Mac and shows the fix. It never runs a fix for you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if copied {
                    Text("Report copied to the clipboard.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(findings) { finding in
                    row(finding)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Doctor")
        .task { await scan() }
    }

    private func row(_ finding: DoctorFinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol(finding.severity))
                    .foregroundStyle(color(finding.severity))
                Text(finding.title).fontWeight(.medium)
                Spacer()
            }
            if !finding.detail.isEmpty {
                Text(finding.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let fix = finding.fix {
                Text(fix)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    private func scan() async {
        checking = true
        defer { checking = false }
        findings = await Task.detached(priority: .utility) {
            EnvironmentDoctor.diagnose(LiveEnvironmentProbe())
        }.value
    }

    private func copyReport() {
        let text = findings.map { finding -> String in
            var lines = "[\(finding.severity)] \(finding.title)"
            if !finding.detail.isEmpty { lines += "\n  \(finding.detail)" }
            if let fix = finding.fix { lines += "\n  Fix: \(fix)" }
            return lines
        }.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }
}

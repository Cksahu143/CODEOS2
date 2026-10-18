import CodeOSCore
import SwiftUI

struct MacTweaksView: View {
    @State private var values: [String: String] = [:]
    @State private var drafts: [String: String] = [:]
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Mac Tweaks").font(.title2).fontWeight(.semibold)
                Text("These change macOS preferences through the standard defaults system. Each one has a reset button that returns it to the macOS default.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(MacTweaks.catalog) { tweak in
                    row(tweak)
                }
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Mac Tweaks")
        .task { await reload() }
    }

    private func row(_ tweak: Tweak) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tweak.title).fontWeight(.medium)
                    Text(tweak.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(currentText(tweak))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 8) {
                editor(tweak)
                Button("Reset to macOS default") { run(tweak, reset: true) }
                    .disabled(busy)
                if let restart = MacTweaks.restartCommand(tweak.restart) {
                    Button("Restart \(restart.arguments.first ?? "")") { restartProcess(restart) }
                        .disabled(busy)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func editor(_ tweak: Tweak) -> some View {
        switch tweak.kind {
        case .bool:
            Toggle("On", isOn: Binding(
                get: { values[tweak.id] == "1" || values[tweak.id] == "true" },
                set: { on in run(tweak, value: on ? "true" : "false") }))
                .toggleStyle(.switch)
                .disabled(busy)
        case .int:
            HStack {
                TextField("Value", text: draftBinding(tweak))
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                Button("Apply") { run(tweak, value: drafts[tweak.id] ?? "") }
                    .disabled(busy)
            }
        case .path:
            HStack {
                TextField("Folder", text: draftBinding(tweak))
                    .frame(width: 260)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") {
                    if let path = FolderPicker.chooseFolder() {
                        drafts[tweak.id] = path
                        run(tweak, value: path)
                    }
                }
                .disabled(busy)
            }
        }
    }

    private func draftBinding(_ tweak: Tweak) -> Binding<String> {
        Binding(
            get: { drafts[tweak.id] ?? values[tweak.id] ?? "" },
            set: { drafts[tweak.id] = $0 })
    }

    private func currentText(_ tweak: Tweak) -> String {
        guard let value = values[tweak.id], !value.isEmpty else { return "macOS default" }
        if case .bool = tweak.kind { return (value == "1" || value == "true") ? "On" : "Off" }
        return value
    }

    private func run(_ tweak: Tweak, value: String) {
        do {
            let command = try MacTweaks.writeCommand(tweak, value: value)
            perform(command, done: "\(tweak.title) updated.", restart: tweak.restart)
        } catch {
            message = error.localizedDescription
        }
    }

    private func run(_ tweak: Tweak, reset: Bool) {
        perform(MacTweaks.resetCommand(tweak), done: "\(tweak.title) reset to the macOS default.", restart: tweak.restart)
    }

    private func restartProcess(_ command: TweakCommand) {
        perform(command, done: "Restarted.", restart: .none)
    }

    private func perform(_ command: TweakCommand, done: String, restart: TweakRestart) {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                _ = try await Task.detached(priority: .utility) { try MacTweaks.execute(command) }.value
                message = done
                if restart != .none, let restartCommand = MacTweaks.restartCommand(restart) {
                    _ = try? await Task.detached(priority: .utility) { try MacTweaks.execute(restartCommand) }.value
                }
                await reload()
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func reload() async {
        let tweaks = MacTweaks.catalog
        let loaded: [String: String] = await Task.detached(priority: .utility) {
            var result: [String: String] = [:]
            for tweak in tweaks {
                if let value = try? MacTweaks.execute(MacTweaks.readCommand(tweak)) {
                    result[tweak.id] = value
                }
            }
            return result
        }.value
        values = loaded
    }
}

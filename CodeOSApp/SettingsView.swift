import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var systemDark = false
    @State private var systemBusy = false

    var body: some View {
        Form {
            Section {
                Picker("CodeOS window", selection: $store.appearance) {
                    ForEach(AppearancePreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                Text("Changes only CodeOS's own windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("CodeOS Appearance")
            }

            Section {
                Toggle("Dark mode for the whole Mac", isOn: Binding(
                    get: { systemDark },
                    set: { setSystemDark($0) }
                ))
                .disabled(systemBusy)
                Text("Changes macOS for every app. The first change asks for permission to control System Events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("macOS Appearance")
            }

            Section {
                Toggle("Open CodeOS at login", isOn: Binding(
                    get: { loginEnabled },
                    set: { setLaunchAtLogin($0) }
                ))
                Text("Works from the installed app. macOS may ask you to approve it in System Settings > General > Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Startup")
            }

            Section("Files") {
                Toggle("Show hidden files", isOn: $store.showHiddenFiles)
            }

            Section("Data") {
                LabeledContent("Configuration file") {
                    Text(store.configStore.fileURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Button("Show in Finder") {
                    _ = NSWorkspace.shared.open(store.configStore.fileURL.deletingLastPathComponent())
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 620)
        .onAppear {
            systemDark = SystemAppearance.isDark()
        }
    }

    private func setSystemDark(_ dark: Bool) {
        systemBusy = true
        Task {
            defer { systemBusy = false }
            do {
                try await SystemAppearance.apply(dark: dark)
                systemDark = dark
            } catch {
                systemDark = SystemAppearance.isDark()
                store.notice = error.localizedDescription
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            store.notice = "Launch at login could not be changed: \(error.localizedDescription)"
        }
        loginEnabled = LoginItem.isEnabled
    }
}

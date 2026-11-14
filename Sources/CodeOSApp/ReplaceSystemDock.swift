import CodeOSCore
import SwiftUI

/// Hides the system Dock with auto-hide and a very long reveal delay. Restore brings back your original settings.
enum SystemDockReplacement {
    static func apply() throws {
        try SystemDock.backupOriginalIfNeeded()
        var settings = try SystemDock.export()
        settings["autohide"] = true
        settings["autohide-delay"] = 1000.0
        try SystemDock.write(settings)
        try SystemDock.restart()
    }
}

struct ReplaceSystemDockSection: View {
    @State private var busy = false
    @State private var note: String?

    var body: some View {
        Section {
            HStack {
                Button("Use CodeOS Dock instead of System Dock") { replace() }
                Button("Restore System Dock") { restore() }
            }
            .disabled(busy)
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        } header: {
            Text("Replace the system Dock")
        } footer: {
            Text("The system Dock slides away and only comes back after a very long delay. macOS doesn't allow removing it fully without disabling System Integrity Protection, which CodeOS won't ask you to do.")
        }
    }

    private func replace() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await Task.detached(priority: .utility) { try SystemDockReplacement.apply() }.value
                FloatingDock.shared.setVisible(true)
                note = "The system Dock is hidden and the CodeOS dock is showing."
            } catch {
                note = error.localizedDescription
            }
        }
    }

    private func restore() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await Task.detached(priority: .utility) { try SystemDock.restoreOriginal() }.value
                note = "Restored your original system Dock."
            } catch {
                note = error.localizedDescription
            }
        }
    }
}

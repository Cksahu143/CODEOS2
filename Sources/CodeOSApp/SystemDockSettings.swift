import AppKit
import CodeOSCore
import SwiftUI

@MainActor
final class SystemDockModel: ObservableObject {
    @Published private(set) var settings: [String: Any] = [:]
    @Published private(set) var tiles: [DockTile] = []
    @Published var note: String?
    @Published var busy = false

    func load() async {
        busy = true
        defer { busy = false }
        do {
            let current = try await Task.detached(priority: .utility) { try SystemDock.export() }.value
            settings = current
            tiles = SystemDock.tiles(in: current, section: SystemDock.appsKey)
                + SystemDock.tiles(in: current, section: SystemDock.foldersKey)
            note = nil
        } catch {
            note = error.localizedDescription
        }
    }

    func set(_ key: String, _ value: Any) {
        apply { current in
            current[key] = value
        }
    }

    func addApp(_ path: String) {
        apply { current in
            var items = current[SystemDock.appsKey] as? [[String: Any]] ?? []
            items.append(SystemDock.tileDictionary(forApp: path))
            current[SystemDock.appsKey] = items
        }
    }

    func addFolder(_ path: String) {
        apply { current in
            var items = current[SystemDock.foldersKey] as? [[String: Any]] ?? []
            items.append(SystemDock.tileDictionary(forFolder: path))
            current[SystemDock.foldersKey] = items
        }
    }

    func remove(_ tile: DockTile) {
        apply { current in
            _ = SystemDock.remove(section: tile.section, index: tile.index, from: &current)
        }
    }

    func restoreOriginal() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await Task.detached(priority: .utility) { try SystemDock.restoreOriginal() }.value
                note = "Restored your original Dock."
                await load()
            } catch {
                note = error.localizedDescription
            }
        }
    }

    /// Backs up once, changes the Dock domain, writes it, and restarts the Dock.
    private func apply(_ change: @escaping (inout [String: Any]) -> Void) {
        busy = true
        let current = settings
        Task {
            defer { busy = false }
            do {
                try await Task.detached(priority: .utility) {
                    try SystemDock.backupOriginalIfNeeded()
                    var updated = current
                    change(&updated)
                    try SystemDock.write(updated)
                    try SystemDock.restart()
                }.value
                note = "Dock updated."
                await load()
            } catch {
                note = error.localizedDescription
            }
        }
    }
}

/// The System Dock section of Settings. Every change is applied to the macOS Dock immediately.
struct SystemDockSettingsSection: View {
    @StateObject private var model = SystemDockModel()
    @State private var tileSize = "48"
    @State private var largeSize = "96"

    var body: some View {
        Section {
            HStack {
                Text("Icon size").frame(width: 130, alignment: .leading)
                TextField("16–128", text: $tileSize).frame(width: 70)
                Button("Set") {
                    do {
                        model.set("tilesize", try SystemDock.validatedNumber("tilesize", tileSize))
                    } catch {
                        model.note = error.localizedDescription
                    }
                }
            }
            Toggle("Magnify icons on hover", isOn: boolBinding("magnification"))
            HStack {
                Text("Largest magnified size").frame(width: 130, alignment: .leading)
                TextField("36–128", text: $largeSize).frame(width: 70)
                Button("Set") {
                    do {
                        model.set("largesize", try SystemDock.validatedNumber("largesize", largeSize))
                    } catch {
                        model.note = error.localizedDescription
                    }
                }
            }
            Picker("Position", selection: stringBinding("orientation", default: "bottom")) {
                ForEach(SystemDock.orientations, id: \.self) { Text($0.capitalized).tag($0) }
            }
            Toggle("Hide the Dock automatically", isOn: boolBinding("autohide"))
            Toggle("Show recent apps", isOn: boolBinding("show-recents"))
            Picker("Minimize effect", selection: stringBinding("mineffect", default: "genie")) {
                ForEach(SystemDock.effects, id: \.self) { Text($0.capitalized).tag($0) }
            }
        } header: {
            Text("System Dock")
        } footer: {
            Text("Colors and transparency are drawn by macOS and can't be changed safely. Your original Dock is backed up the first time CodeOS changes it.")
        }

        Section {
            ForEach(model.tiles) { tile in
                HStack {
                    Image(systemName: tile.section == SystemDock.foldersKey ? "folder" : "app")
                        .foregroundStyle(.secondary)
                    Text(tile.label)
                    Text(tile.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(role: .destructive) { model.remove(tile) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                Button("Add App…") {
                    if let app = FolderPicker.chooseApplication() { model.addApp(app.path) }
                }
                Button("Add Folder…") {
                    if let folder = FolderPicker.chooseFolder(prompt: "Add") { model.addFolder(folder) }
                }
                Spacer()
                Button("Restore Original Dock") { model.restoreOriginal() }
            }
            .disabled(model.busy)
        } header: {
            Text("Apps and folders in the Dock")
        }

        if let note = model.note {
            Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    private func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { (model.settings[key] as? Bool) ?? false },
            set: { model.set(key, $0) })
    }

    private func stringBinding(_ key: String, default fallback: String) -> Binding<String> {
        Binding(
            get: { (model.settings[key] as? String) ?? fallback },
            set: { model.set(key, $0) })
    }
}

import AppKit
import CodeOSCore
import SwiftUI

/// Holds the dock items and saves them whenever they change.
@MainActor
final class DockModel: ObservableObject {
    static let shared = DockModel()
    private static let key = "dockItems"

    @Published var items: [DockItem] {
        didSet {
            UserDefaults.standard.set(DockRules.encode(items), forKey: DockModel.key)
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: DockModel.key), let saved = DockRules.decode(data) {
            items = saved
        } else {
            items = DockRules.defaults
        }
    }

    func add(_ item: DockItem) {
        items.append(item)
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func move(_ id: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard target >= 0, target < items.count else { return }
        items.swapAt(index, target)
    }

    func resetToDefaults() {
        items = DockRules.defaults
    }
}

/// The dock along the bottom of CodeOS. Each button opens a section, app, folder, or link.
struct DockBar: View {
    @Binding var selection: AppSection?
    @ObservedObject private var dock = DockModel.shared
    @State private var editing = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(dock.items) { item in
                Button {
                    activate(item)
                } label: {
                    Label(item.title, systemImage: item.symbol)
                }
                .buttonStyle(.bordered)
                .help(item.target)
            }
            Spacer()
            Button {
                editing = true
            } label: {
                Label("Edit Dock", systemImage: "slider.horizontal.3")
            }
            .labelStyle(.iconOnly)
            .help("Add, remove, or rearrange dock buttons")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .sheet(isPresented: $editing) {
            DockEditor()
        }
    }

    private func activate(_ item: DockItem) {
        switch item.kind {
        case .section:
            if let section = AppSection(rawValue: item.target) {
                selection = section
            }
        case .application:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.target) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        case .folder:
            NSWorkspace.shared.open(URL(fileURLWithPath: item.target))
        case .link:
            if let url = URL(string: item.target) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

/// Edits the dock: names, symbols, targets, order, and removal. Each row shows why it is not valid yet.
struct DockEditor: View {
    @ObservedObject private var dock = DockModel.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Customize Dock").font(.title3).fontWeight(.semibold)
                Spacer()
                Button("Add Section") {
                    dock.add(DockItem(kind: .section, title: "New", symbol: "square", target: "home"))
                }
                Button("Add Link") {
                    dock.add(DockItem(kind: .link, title: "Docs", symbol: "book", target: "https://"))
                }
                Button("Reset to Defaults") { dock.resetToDefaults() }
            }
            List {
                ForEach($dock.items) { $item in
                    row($item)
                }
            }
            HStack {
                Text("Dock buttons open things only. They never run commands.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 720, height: 520)
    }

    private func row(_ item: Binding<DockItem>) -> some View {
        let current = item.wrappedValue
        let problem = DockRules.problem(for: current)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Name", text: item.title)
                    .frame(width: 130)
                TextField("SF Symbol", text: item.symbol)
                    .frame(width: 150)
                Picker("Kind", selection: item.kind) {
                    Text("Section").tag(DockItem.Kind.section)
                    Text("App").tag(DockItem.Kind.application)
                    Text("Folder").tag(DockItem.Kind.folder)
                    Text("Link").tag(DockItem.Kind.link)
                }
                .labelsHidden()
                .frame(width: 110)
                Spacer()
                Button {
                    dock.move(current.id, by: -1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                Button {
                    dock.move(current.id, by: 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                Button(role: .destructive) {
                    dock.remove(current.id)
                } label: {
                    Image(systemName: "trash")
                }
            }
            HStack(spacing: 8) {
                TextField(placeholder(current.kind), text: item.target)
                if current.kind == .folder {
                    Button("Choose…") {
                        if let path = FolderPicker.chooseFolder(prompt: "Choose") { item.wrappedValue.target = path }
                    }
                }
                if current.kind == .application {
                    Button("Choose App…") {
                        if let app = FolderPicker.chooseApplication(),
                           let bundleID = Bundle(url: app)?.bundleIdentifier {
                            item.wrappedValue.target = bundleID
                        }
                    }
                }
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func placeholder(_ kind: DockItem.Kind) -> String {
        switch kind {
        case .section: return "Section: home, studio, files, applications, monitor, doctor"
        case .application: return "Bundle identifier, such as com.apple.Terminal"
        case .folder: return "Absolute folder path"
        case .link: return "https://example.com"
        }
    }
}

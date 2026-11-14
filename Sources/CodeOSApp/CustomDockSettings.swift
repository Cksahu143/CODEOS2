import AppKit
import CodeOSCore
import SwiftUI

/// Settings for the CodeOS dock: its look, its items, and whether it is shown.
struct CustomDockSettingsSection: View {
    @ObservedObject private var model = DockModel.shared
    @ObservedObject private var dock = FloatingDock.shared

    var body: some View {
        Section {
            Toggle("Show CodeOS dock", isOn: Binding(
                get: { model.appearance.isVisible },
                set: { FloatingDock.shared.setVisible($0) }))
            ColorPicker("Background", selection: colorBinding, supportsOpacity: false)
            sliderRow("Transparency", value: \.opacity, range: 0.2...1.0, format: "%.2f")
            sliderRow("Corner radius", value: \.cornerRadius, range: 0...40, format: "%.0f")
            sliderRow("Icon size", value: \.iconSize, range: 24...96, format: "%.0f")
            Picker("Position", selection: Binding(
                get: { model.appearance.position },
                set: { value in update { $0.position = value } })) {
                ForEach(DockAppearance.positions, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("CodeOS Dock")
        } footer: {
            Text("A floating panel above your windows. It can't reserve screen space like the system Dock, and full-screen apps may cover it.")
        }

        Section {
            ForEach($model.items) { $item in
                itemRow($item)
            }
            HStack(spacing: 6) {
                Button("App…") { addApp() }
                Button("Folder…") { addFolder() }
                Button("Section") { model.add(DockItem(kind: .section, title: "New", symbol: "square", target: "home")) }
                Button("Link") { model.add(DockItem(kind: .link, title: "Docs", symbol: "book", target: "https://")) }
                Button("Spacer") { model.add(DockItem(kind: .spacer, title: "", symbol: "", target: "")) }
                Button("Separator") { model.add(DockItem(kind: .separator, title: "", symbol: "", target: "")) }
                Spacer()
                Button("Reset Items") { model.resetToDefaults() }
            }
        } header: {
            Text("Dock items")
        } footer: {
            Text("Dock items open apps, folders, links, and CodeOS sections. Spacers and separators group them. None run commands.")
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: model.appearance.backgroundHex) },
            set: { color in update { $0.backgroundHex = color.hexString } })
    }

    private func sliderRow(_ title: String, value: WritableKeyPath<DockAppearance, Double>,
                           range: ClosedRange<Double>, format: String) -> some View {
        HStack {
            Text(title).frame(width: 130, alignment: .leading)
            Slider(value: Binding(
                get: { model.appearance[keyPath: value] },
                set: { newValue in update { $0[keyPath: value] = newValue } }), in: range)
            Text(String(format: format, model.appearance[keyPath: value]))
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func update(_ change: (inout DockAppearance) -> Void) {
        var appearance = model.appearance
        change(&appearance)
        model.appearance = appearance
    }

    private func itemRow(_ item: Binding<DockItem>) -> some View {
        let current = item.wrappedValue
        let problem = DockRules.problem(for: current)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Name", text: item.title).frame(width: 120)
                TextField("SF Symbol", text: item.symbol).frame(width: 140)
                Picker("Kind", selection: item.kind) {
                    Text("Section").tag(DockItem.Kind.section)
                    Text("App").tag(DockItem.Kind.application)
                    Text("Folder").tag(DockItem.Kind.folder)
                    Text("Link").tag(DockItem.Kind.link)
                    Text("Spacer").tag(DockItem.Kind.spacer)
                    Text("Separator").tag(DockItem.Kind.separator)
                }
                .labelsHidden()
                .frame(width: 110)
                Spacer()
                Button { model.move(current.id, by: -1) } label: { Image(systemName: "arrow.up") }
                Button { model.move(current.id, by: 1) } label: { Image(systemName: "arrow.down") }
                Button(role: .destructive) { model.remove(current.id) } label: { Image(systemName: "trash") }
            }
            if current.kind != .spacer && current.kind != .separator {
                HStack(spacing: 8) {
                    TextField(placeholder(current.kind), text: item.target)
                    if current.kind == .folder {
                        Button("Choose…") {
                            if let path = FolderPicker.chooseFolder(prompt: "Choose") { item.wrappedValue.target = path }
                        }
                    }
                    if current.kind == .application {
                        Button("Choose App…") {
                            if let app = FolderPicker.chooseApplication(), let bundleID = Bundle(url: app)?.bundleIdentifier {
                                item.wrappedValue.target = bundleID
                            }
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

    private func addApp() {
        guard let app = FolderPicker.chooseApplication(), let bundleID = Bundle(url: app)?.bundleIdentifier else { return }
        model.add(DockItem(kind: .application, title: app.deletingPathExtension().lastPathComponent, symbol: "app", target: bundleID))
    }

    private func addFolder() {
        guard let folder = FolderPicker.chooseFolder(prompt: "Add") else { return }
        model.add(DockItem(kind: .folder, title: URL(fileURLWithPath: folder).lastPathComponent, symbol: "folder", target: folder))
    }

    private func placeholder(_ kind: DockItem.Kind) -> String {
        switch kind {
        case .section: return "Section: home, studio, files, applications, monitor, doctor"
        case .application: return "Bundle identifier, such as com.apple.Terminal"
        case .folder: return "Absolute folder path"
        case .link: return "https://example.com"
        case .spacer, .separator: return ""
        }
    }
}

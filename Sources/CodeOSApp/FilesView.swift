import AppKit
import CodeOSCore
import SwiftUI

struct FilesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var currentPath: String = NSHomeDirectory()
    @State private var items: [FileItem] = []
    @State private var selection = Set<String>()
    @State private var sortKey: SortKey = .name
    @State private var ascending = true
    @State private var filter = ""
    @State private var message: String?
    @State private var batchRenaming = false
    @State private var creatingFolder = false
    @State private var newFolderName = "untitled folder"
    @State private var confirmingTrash: [FileItem] = []

    private var visibleItems: [FileItem] {
        let sorted = DirectoryListing.sorted(items, by: sortKey, ascending: ascending)
        guard !filter.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    private var selectedItems: [FileItem] {
        items.filter { selection.contains($0.path) }
    }

    /// Context-menu actions act on the whole selection when the clicked item belongs to it.
    private func targets(for item: FileItem) -> [FileItem] {
        selection.contains(item.path) ? selectedItems : [item]
    }

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            Divider()
            if let message {
                messageBar(message)
            }
            if visibleItems.isEmpty {
                EmptyStateView(
                    title: filter.isEmpty ? "This folder is empty" : "No matches",
                    message: filter.isEmpty
                        ? "Hidden files are shown only when enabled in Settings."
                        : "Nothing in this folder matches “\(filter)”.",
                    systemImage: "folder")
            } else {
                List(visibleItems, selection: $selection) { item in
                    row(item)
                        .tag(item.path)
                        .contextMenu { contextActions(item) }
                }
            }
            Divider()
            statusBar
        }
        .navigationTitle("Files")
        .searchable(text: $filter, prompt: "Filter this folder")
        .toolbar { toolbarContent }
        .onAppear(perform: reload)
        .onChange(of: currentPath) { _ in reload() }
        .onChange(of: store.showHiddenFiles) { _ in reload() }
        .onDeleteCommand { confirmingTrash = selectedItems }
        .sheet(isPresented: $batchRenaming) {
            BatchRenameSheet(
                items: selectedItems,
                existing: existingNamesOutside(selectedItems),
                onApply: { renames in applyRenames(renames) })
        }
        .sheet(isPresented: $creatingFolder) {
            NameSheet(title: "New Folder", actionTitle: "Create", name: newFolderName) { name in
                createFolder(name)
            }
        }
        .confirmationDialog(
            confirmingTrash.count == 1
                ? "Move this item to the Trash?"
                : "Move \(confirmingTrash.count) items to the Trash?",
            isPresented: Binding(get: { !confirmingTrash.isEmpty }, set: { if !$0 { confirmingTrash = [] } })
        ) {
            Button("Move to Trash", role: .destructive) { moveToTrash(confirmingTrash) }
        } message: {
            Text("Items in the Trash can be restored.")
        }
    }

    // MARK: Layout

    private var pathBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text(currentPath)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func messageBar(_ text: String) -> some View {
        HStack {
            Text(text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer()
            Button("Dismiss") { message = nil }
                .buttonStyle(.link)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
    }

    private var statusBar: some View {
        HStack {
            Text("\(visibleItems.count) item\(visibleItems.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !selection.isEmpty {
                Text("· \(selection.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selection.count == 1, let only = selectedItems.first {
                Text(detailText(for: only))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func row(_ item: FileItem) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 18, height: 18)
            Text(item.name).lineLimit(1)
            if item.isSymbolicLink {
                Image(systemName: "link").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.date(item.modified))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
            Text(item.size.map { Format.bytes($0) } ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { activate(item) }
    }

    @ViewBuilder
    private func contextActions(_ item: FileItem) -> some View {
        let picked = targets(for: item)
        Button("Open") { activate(item) }
        Button("Open in VS Code") { openInVSCode(picked) }
        Button("Open With…") { openWith(item) }
            .disabled(item.isDirectory)
        Button("Reveal in Finder") { reveal(picked) }
        Button("Open Terminal Here") { openTerminal(item) }
        Divider()
        Button(picked.count > 1 ? "Rename \(picked.count) Items…" : "Rename…") {
            selection = Set(picked.map(\.path))
            batchRenaming = true
        }
        Button("Duplicate") { duplicate(picked) }
        Button("Move to Folder…") { transfer(picked, move: true) }
        Button("Copy to Folder…") { transfer(picked, move: false) }
        Divider()
        Button("Move to Trash", role: .destructive) { confirmingTrash = picked }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { navigate(to: DirectoryListing.parent(of: currentPath)) } label: {
                Label("Enclosing Folder", systemImage: "chevron.up")
            }
            .disabled(currentPath == "/")
            Button { navigate(to: NSHomeDirectory()) } label: {
                Label("Home", systemImage: "house")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                if let path = FolderPicker.chooseFolder(prompt: "Open") { navigate(to: path) }
            } label: {
                Label("Choose Folder", systemImage: "folder.badge.gearshape")
            }
            Button {
                newFolderName = FileOperationPlanner.uniqueName(
                    for: "untitled folder",
                    existingNames: existingNames(in: currentPath) ?? [])
                creatingFolder = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Button {
                batchRenaming = true
            } label: {
                Label("Batch Rename", systemImage: "character.cursor.ibeam")
            }
            .disabled(selection.isEmpty)
            Button {
                confirmingTrash = selectedItems
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .disabled(selection.isEmpty)
            Menu {
                Picker("Sort By", selection: $sortKey) {
                    Text("Name").tag(SortKey.name)
                    Text("Date Modified").tag(SortKey.modified)
                    Text("Size").tag(SortKey.size)
                }
                Toggle("Ascending", isOn: $ascending)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }
    }

    // MARK: Behavior

    private func reload() {
        do {
            items = try DirectoryListing.list(currentPath, showHidden: store.showHiddenFiles)
        } catch {
            items = []
            message = "This folder cannot be read: \(error.localizedDescription)"
        }
        selection = []
    }

    private func navigate(to path: String) {
        guard path != currentPath else { return }
        currentPath = path
    }

    private func join(_ folder: String, _ name: String) -> String {
        (folder as NSString).appendingPathComponent(name)
    }

    private func activate(_ item: FileItem) {
        if item.isDirectory {
            navigate(to: item.path)
        } else if !NSWorkspace.shared.open(URL(fileURLWithPath: item.path)) {
            message = "macOS could not open “\(item.name)”."
        }
    }

    private func reveal(_ picked: [FileItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(picked.map { URL(fileURLWithPath: $0.path) })
    }

    private func openInVSCode(_ picked: [FileItem]) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") else {
            message = "VS Code is not installed. Get it from code.visualstudio.com."
            return
        }
        let urls = picked.map { URL(fileURLWithPath: $0.path) }
        Task {
            do {
                try await NativeOpen.open(urls, withApplicationAt: app)
            } catch {
                message = "VS Code could not open these items: \(error.localizedDescription)"
            }
        }
    }

    private func openTerminal(_ item: FileItem) {
        let folder = item.isDirectory ? item.path : DirectoryListing.parent(of: item.path)
        Task {
            do {
                _ = try await AppActionExecutor().execute(.openTerminal(path: folder))
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func openWith(_ item: FileItem) {
        guard let app = FolderPicker.chooseApplication() else { return }
        Task {
            do {
                try await NativeOpen.open([URL(fileURLWithPath: item.path)], withApplicationAt: app)
            } catch {
                message = "“\(item.name)” could not be opened with \(app.deletingPathExtension().lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    /// Names in a folder, including hidden ones, so collision checks are complete.
    private func existingNames(in folder: String) -> Set<String>? {
        guard let listed = try? DirectoryListing.list(folder, showHidden: true) else { return nil }
        return Set(listed.map(\.name))
    }

    private func existingNamesOutside(_ batch: [FileItem]) -> Set<String> {
        (existingNames(in: currentPath) ?? []).subtracting(batch.map(\.name))
    }

    /// Renames in two passes through temporary names, so swaps and chains never collide.
    /// If a step fails, the message says which items may still carry a temporary name.
    private func applyRenames(_ renames: [(String, String)]) {
        let changes = renames.filter { $0.0 != $0.1 }
        guard !changes.isEmpty else { return }
        let token = UUID().uuidString
        var parked: [(String, String)] = []
        do {
            for (index, change) in changes.enumerated() {
                let temporary = "\(token)-\(index)"
                try FileManager.default.moveItem(atPath: join(currentPath, change.0), toPath: join(currentPath, temporary))
                parked.append((temporary, change.1))
            }
            for (temporary, finalName) in parked {
                try FileManager.default.moveItem(atPath: join(currentPath, temporary), toPath: join(currentPath, finalName))
            }
            message = "Renamed \(changes.count) item(s)."
        } catch {
            let stuck = parked.map { $0.0 }.joined(separator: ", ")
            message = "Rename stopped: \(error.localizedDescription). Items may still have temporary names (\(stuck)); check this folder."
        }
        reload()
    }

    private func createFolder(_ name: String) -> String? {
        guard let names = existingNames(in: currentPath) else { return "The folder cannot be read." }
        do {
            let destination = try FileOperationPlanner.destination(directory: currentPath, newName: name, existingNames: names)
            try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: false)
            reload()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func duplicate(_ picked: [FileItem]) {
        for item in picked {
            let parent = DirectoryListing.parent(of: item.path)
            guard let names = existingNames(in: parent) else {
                message = "The folder cannot be read."
                return
            }
            let newName = FileOperationPlanner.uniqueName(for: item.name, existingNames: names)
            do {
                try FileManager.default.copyItem(atPath: item.path, toPath: join(parent, newName))
            } catch {
                message = "“\(item.name)” could not be duplicated: \(error.localizedDescription)"
            }
        }
        reload()
    }

    /// Moves or copies several items. Each name is checked against the destination; nothing is overwritten.
    private func transfer(_ picked: [FileItem], move: Bool) {
        guard let folder = FolderPicker.chooseFolder(prompt: move ? "Move Here" : "Copy Here") else { return }
        guard var taken = existingNames(in: folder) else {
            message = "The destination folder cannot be read."
            return
        }
        var done = 0
        for item in picked {
            if item.isDirectory && (folder == item.path || FileOperationPlanner.isInside(folder, root: item.path)) {
                message = "“\(item.name)” cannot go inside itself. It was skipped."
                continue
            }
            do {
                let destination = try FileOperationPlanner.destination(directory: folder, newName: item.name, existingNames: taken)
                if move {
                    try FileManager.default.moveItem(atPath: item.path, toPath: destination)
                } else {
                    try FileManager.default.copyItem(atPath: item.path, toPath: destination)
                }
                taken.insert(item.name)
                done += 1
            } catch {
                message = "“\(item.name)”: \(error.localizedDescription)"
            }
        }
        if done > 0 {
            message = "\(done) item(s) \(move ? "moved" : "copied")."
        }
        reload()
    }

    private func moveToTrash(_ picked: [FileItem]) {
        var trashed = 0
        var failed: [String] = []
        for item in picked {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                trashed += 1
            } catch {
                failed.append(item.name)
            }
        }
        message = failed.isEmpty
            ? "Moved \(trashed) item(s) to the Trash."
            : "Moved \(trashed) item(s). Could not move: \(failed.joined(separator: ", "))."
        reload()
    }

    private func detailText(for item: FileItem) -> String {
        if item.isDirectory { return "Folder · modified \(Format.date(item.modified))" }
        let size = item.size.map { Format.bytes($0) } ?? "unknown size"
        return "\(size) · modified \(Format.date(item.modified))"
    }
}

/// Renames several items at once. Shows every new name before anything changes.
struct BatchRenameSheet: View {
    let items: [FileItem]
    let existing: Set<String>
    let onApply: ([(String, String)]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rule = BatchRenameRule()
    @State private var numbering = false

    private var previews: [BatchRenamePreview] {
        BatchRename.preview(names: items.map(\.name), rule: rule, existing: existing)
    }

    private var canApply: Bool {
        !previews.isEmpty
            && previews.allSatisfy { $0.problem == nil }
            && previews.contains { $0.proposed != $0.original }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename \(items.count) item(s)").font(.title2).fontWeight(.semibold)
            Form {
                TextField("Find", text: $rule.find)
                TextField("Replace with", text: $rule.replaceWith)
                TextField("Add prefix", text: $rule.prefix)
                TextField("Add suffix (before the extension)", text: $rule.suffix)
                Toggle("Number the items", isOn: Binding(
                    get: { numbering },
                    set: { on in
                        numbering = on
                        rule.numberStart = on ? (rule.numberStart ?? 1) : nil
                    }))
                if numbering {
                    Stepper("Start at \(rule.numberStart ?? 1)", value: Binding(
                        get: { rule.numberStart ?? 1 },
                        set: { rule.numberStart = $0 }), in: 0...9999)
                }
            }
            .formStyle(.grouped)

            List(previews, id: \.original) { preview in
                HStack(spacing: 8) {
                    Text(preview.original).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text(preview.proposed).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if let problem = preview.problem {
                        Text(problem).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .frame(height: 200)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    onApply(previews.map { ($0.original, $0.proposed) })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
            }
        }
        .padding(20)
        .frame(width: 580, height: 620)
    }
}

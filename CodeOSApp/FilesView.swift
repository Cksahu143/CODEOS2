import AppKit
import CodeOSCore
import SwiftUI

struct FilesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var currentPath: String = NSHomeDirectory()
    @State private var items: [FileItem] = []
    @State private var selectedPath: String?
    @State private var sortKey: SortKey = .name
    @State private var ascending = true
    @State private var filter = ""
    @State private var message: String?
    @State private var renaming: FileItem?
    @State private var creatingFolder = false
    @State private var newFolderName = "untitled folder"
    @State private var confirmingTrash: FileItem?

    private var visibleItems: [FileItem] {
        let sorted = DirectoryListing.sorted(items, by: sortKey, ascending: ascending)
        guard !filter.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    private var selectedItem: FileItem? {
        items.first { $0.path == selectedPath }
    }

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            Divider()
            if let message {
                HStack {
                    Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { self.message = nil }
                        .buttonStyle(.link)
                }
                .padding(8)
                .background(Color.red.opacity(0.08))
            }
            if visibleItems.isEmpty {
                EmptyStateView(
                    title: filter.isEmpty ? "This folder is empty" : "No matches",
                    message: filter.isEmpty
                        ? "Hidden files are shown only when enabled in Settings."
                        : "Nothing in this folder matches “\(filter)”.",
                    systemImage: "folder"
                )
            } else {
                List(visibleItems, selection: $selectedPath) { item in
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
        .onDeleteCommand {
            if let selectedItem { confirmingTrash = selectedItem }
        }
        .sheet(item: $renaming) { item in
            NameSheet(title: "Rename “\(item.name)”", actionTitle: "Rename", name: item.name) { newName in
                rename(item, to: newName)
            }
        }
        .sheet(isPresented: $creatingFolder) {
            NameSheet(title: "New Folder", actionTitle: "Create", name: newFolderName) { name in
                createFolder(name)
            }
        }
        .confirmationDialog(
            "Move this item to the Trash?",
            isPresented: Binding(get: { confirmingTrash != nil }, set: { if !$0 { confirmingTrash = nil } }),
            presenting: confirmingTrash
        ) { item in
            Button("Move to Trash", role: .destructive) { moveToTrash(item) }
        } message: { item in
            Text("“\(item.name)” can be restored from the Trash.")
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

    private var statusBar: some View {
        HStack {
            Text("\(visibleItems.count) item\(visibleItems.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let selectedItem {
                Text(detailText(for: selectedItem))
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
        Button("Open") { activate(item) }
        Button("Open With…") { openWith(item) }
            .disabled(item.isDirectory)
        Button("Reveal in Finder") { reveal(item) }
        Button("Open Terminal Here") { openTerminal(item) }
        Divider()
        Button("Rename…") { renaming = item }
        Button("Duplicate") { duplicate(item) }
        Button("Move to Folder…") { transfer(item, move: true) }
        Button("Copy to Folder…") { transfer(item, move: false) }
        Divider()
        Button("Move to Trash", role: .destructive) { confirmingTrash = item }
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
                    existingNames: existingNames(in: currentPath) ?? []
                )
                creatingFolder = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
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
            message = nil
        } catch {
            items = []
            message = "This folder cannot be read: \(error.localizedDescription)"
        }
        selectedPath = nil
    }

    private func navigate(to path: String) {
        guard path != currentPath else { return }
        currentPath = path
    }

    private func activate(_ item: FileItem) {
        if item.isDirectory {
            navigate(to: item.path)
        } else if !NSWorkspace.shared.open(URL(fileURLWithPath: item.path)) {
            message = "macOS could not open “\(item.name)”."
        }
    }

    private func reveal(_ item: FileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }

    private func openTerminal(_ item: FileItem) {
        let folder = item.isDirectory ? item.path : DirectoryListing.parent(of: item.path)
        Task { await runSingle(.openTerminal(path: folder)) }
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

    private func runSingle(_ action: WorkflowAction) async {
        do {
            _ = try await AppActionExecutor().execute(action)
        } catch {
            message = error.localizedDescription
        }
    }

    /// Names in a folder, including hidden ones, so collision checks are complete.
    private func existingNames(in folder: String) -> Set<String>? {
        guard let listed = try? DirectoryListing.list(folder, showHidden: true) else { return nil }
        return Set(listed.map(\.name))
    }

    private func rename(_ item: FileItem, to newName: String) -> String? {
        if newName == item.name { return nil }
        let parent = DirectoryListing.parent(of: item.path)
        guard let names = existingNames(in: parent) else {
            return "The folder cannot be read."
        }
        do {
            let destination = try FileOperationPlanner.destination(directory: parent, newName: newName, existingNames: names)
            try FileManager.default.moveItem(atPath: item.path, toPath: destination)
            reload()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func createFolder(_ name: String) -> String? {
        guard let names = existingNames(in: currentPath) else {
            return "The folder cannot be read."
        }
        do {
            let destination = try FileOperationPlanner.destination(directory: currentPath, newName: name, existingNames: names)
            try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: false)
            reload()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func duplicate(_ item: FileItem) {
        let parent = DirectoryListing.parent(of: item.path)
        guard let names = existingNames(in: parent) else {
            message = "The folder cannot be read."
            return
        }
        let newName = FileOperationPlanner.uniqueName(for: item.name, existingNames: names)
        let destination = (parent as NSString).appendingPathComponent(newName)
        do {
            try FileManager.default.copyItem(atPath: item.path, toPath: destination)
            reload()
        } catch {
            message = "“\(item.name)” could not be duplicated: \(error.localizedDescription)"
        }
    }

    private func transfer(_ item: FileItem, move: Bool) {
        guard let folder = FolderPicker.chooseFolder(prompt: move ? "Move Here" : "Copy Here") else { return }
        if item.isDirectory && (folder == item.path || FileOperationPlanner.isInside(folder, root: item.path)) {
            message = "A folder cannot be moved or copied into itself."
            return
        }
        guard let names = existingNames(in: folder) else {
            message = "The destination folder cannot be read."
            return
        }
        do {
            // Throws instead of overwriting when the name already exists in the destination.
            let destination = try FileOperationPlanner.destination(directory: folder, newName: item.name, existingNames: names)
            if move {
                try FileManager.default.moveItem(atPath: item.path, toPath: destination)
            } else {
                try FileManager.default.copyItem(atPath: item.path, toPath: destination)
            }
            reload()
        } catch {
            message = error.localizedDescription
        }
    }

    private func moveToTrash(_ item: FileItem) {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
            reload()
        } catch {
            message = "“\(item.name)” could not be moved to the Trash: \(error.localizedDescription)"
        }
    }

    private func detailText(for item: FileItem) -> String {
        if item.isDirectory { return "Folder · modified \(Format.date(item.modified))" }
        let size = item.size.map { Format.bytes($0) } ?? "unknown size"
        return "\(size) · modified \(Format.date(item.modified))"
    }
}

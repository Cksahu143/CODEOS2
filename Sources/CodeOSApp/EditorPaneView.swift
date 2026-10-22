import CodeOSCore
import SwiftUI

struct EditorPaneView: View {
    @AppStorage("gitGraphRepository") private var repository = ""
    @State private var files: [String] = []
    @State private var search = ""
    @State private var openPath: String?
    @State private var text = ""
    @State private var language = "plaintext"
    @State private var documentID = ""
    @State private var dirty = false
    @State private var saveTick = 0
    @State private var note: String?
    @State private var pendingOpen: String?

    private var shown: [String] {
        search.isEmpty ? files : files.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Filter files", text: $search)
                    .textFieldStyle(.roundedBorder)
                List(shown, id: \.self) { file in
                    Text(file)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture { requestOpen(absolute(file)) }
                        .background(absolute(file) == openPath ? Color.accentColor.opacity(0.2) : Color.clear)
                }
            }
            .padding(8)
            .frame(minWidth: 220, idealWidth: 260)

            VStack(alignment: .leading, spacing: 0) {
                toolbar
                Divider()
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .padding(6)
                }
                MonacoEditor(
                    documentID: documentID,
                    text: text,
                    language: language,
                    saveTick: saveTick,
                    onDirty: { dirty = $0 },
                    onSave: { save($0) })
                    .frame(minHeight: 300)
                Text("The editor engine is Monaco, the same editor used in VS Code. It loads once per launch from jsDelivr.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .frame(minWidth: 480)
        }
        .task(id: repository) { await reloadFiles() }
        .confirmationDialog(
            "Discard unsaved changes?",
            isPresented: Binding(get: { pendingOpen != nil }, set: { if !$0 { pendingOpen = nil } }),
            presenting: pendingOpen
        ) { path in
            Button("Discard and Open", role: .destructive) { open(path) }
        } message: { _ in
            Text("The file you are editing has changes that are not saved yet.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(openPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No file open")
                .font(.headline)
                .lineLimit(1)
            if dirty {
                Circle().fill(Color.orange).frame(width: 8, height: 8).help("Unsaved changes")
            }
            Spacer()
            Button("Open File…") {
                if let url = FilePicker.chooseFile() { requestOpen(url.path) }
            }
            Button {
                saveTick += 1
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(openPath == nil)
        }
        .padding(8)
    }

    private func absolute(_ relative: String) -> String {
        (repository as NSString).appendingPathComponent(relative)
    }

    private func requestOpen(_ path: String) {
        if dirty {
            pendingOpen = path
        } else {
            open(path)
        }
    }

    private func open(_ path: String) {
        do {
            text = try EditorFile.read(path)
            language = EditorFile.language(for: path)
            openPath = path
            documentID = path + "|" + UUID().uuidString
            dirty = false
            note = nil
        } catch {
            note = error.localizedDescription
        }
    }

    /// Returns an error message to show, or nil when the save succeeded.
    private func save(_ newText: String) -> String? {
        guard let openPath else { return "Open a file before saving." }
        do {
            try EditorFile.write(newText, to: openPath)
            text = newText
            dirty = false
            note = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func reloadFiles() async {
        guard !repository.isEmpty else {
            files = []
            return
        }
        let path = repository
        do {
            files = try await Task.detached(priority: .utility) {
                try EditorFile.repositoryFiles(path)
            }.value
        } catch {
            files = []
            note = error.localizedDescription
        }
    }
}

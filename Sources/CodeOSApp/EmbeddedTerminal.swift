import AppKit
import CodeOSCore
import SwiftTerm
import SwiftUI

/// A real shell inside CodeOS, using SwiftTerm. The shell is your login shell, so your PATH,
/// aliases, and tools (git, node, python3) behave as they do in Terminal.
struct EmbeddedTerminal: NSViewRepresentable {
    let folder: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        view.startProcess(executable: shell, args: ["-l"])
        if let directory = safeFolder(folder) {
            // Type the cd into the shell the user already has, so every shell feature keeps working.
            let line = "cd \(shellQuote(directory)) && clear\n"
            view.send(source: view, data: ArraySlice(Array(line.utf8)))
        }
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}

    private func safeFolder(_ path: String) -> String? {
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return path
    }

    /// Wraps a path in single quotes for the shell, so spaces and symbols are never read as code.
    private func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}

/// The Terminal section: pick a folder, start a fresh shell there, and keep working.
struct TerminalSectionView: View {
    @AppStorage("terminalFolder") private var folder = NSHomeDirectory()
    @State private var sessionID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(folder)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
                Spacer()
                Button("Choose Folder…") {
                    if let path = FolderPicker.chooseFolder(prompt: "Open Here") {
                        folder = path
                        sessionID = UUID()
                    }
                }
                Button {
                    sessionID = UUID()
                } label: {
                    Label("New Shell", systemImage: "arrow.clockwise")
                }
            }
            .padding(10)
            Divider()
            EmbeddedTerminal(folder: folder)
                .id(sessionID)
        }
        .navigationTitle("Terminal")
    }
}

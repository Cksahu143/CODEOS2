import AppKit
import CodeOSCore
import SwiftTerm
import SwiftUI

/// A real shell inside CodeOS, using SwiftTerm. The shell is your login shell, so your PATH,
/// aliases, and tools (git, node, python3) behave as they do in Terminal.
struct EmbeddedTerminal: NSViewRepresentable {
    let folder: String
    let onExit: (Int32?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 900, height: 520))
        context.coordinator.onExit = onExit
        view.processDelegate = context.coordinator
        // Start the shell once the view is on screen, so it gets a real size.
        DispatchQueue.main.async {
            start(view)
        }
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}

    private func start(_ view: LocalProcessTerminalView) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        view.startProcess(executable: shell, args: ["-l"])
        view.window?.makeFirstResponder(view)
        guard let directory = safeFolder(folder) else { return }
        let line = "cd \(shellQuote(directory)) && clear\n"
        // Give the shell a moment to print its prompt before typing into it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            view.send(source: view, data: ArraySlice(Array(line.utf8)))
        }
    }

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
        var onExit: ((Int32?) -> Void)?

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            let handler = onExit
            DispatchQueue.main.async {
                handler?(exitCode)
            }
        }
    }
}

/// The Terminal section: pick a folder, start a fresh shell there, and see why a shell ended.
struct TerminalSectionView: View {
    @AppStorage("terminalFolder") private var folder = NSHomeDirectory()
    @State private var sessionID = UUID()
    @State private var endedMessage: String?

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
                        restart()
                    }
                }
                Button {
                    restart()
                } label: {
                    Label("New Shell", systemImage: "arrow.clockwise")
                }
            }
            .padding(10)
            if let endedMessage {
                Text(endedMessage)
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.15))
            }
            Divider()
            EmbeddedTerminal(folder: folder, onExit: { code in
                let detail = code.map { "exit code \($0)" } ?? "an unknown error"
                endedMessage = "The shell ended with \(detail). Press New Shell to start another."
            })
            .id(sessionID)
        }
        .navigationTitle("Terminal")
    }

    private func restart() {
        endedMessage = nil
        sessionID = UUID()
    }
}

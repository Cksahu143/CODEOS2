import AppKit
import CodeOSCore
import SwiftTerm
import SwiftUI

/// A real shell inside CodeOS, using SwiftTerm. The shell is your login shell, so your PATH,
/// aliases, and tools (git, node, python3) behave as they do in Terminal.
///
/// SwiftTerm must not be added to the view hierarchy during SwiftUI's layout pass: on macOS 13 that
/// raises an NSException and quits the app. So this returns a plain container, and the terminal is
/// added to it on the next run-loop turn.
struct EmbeddedTerminal: NSViewRepresentable {
    let folder: String
    let onExit: (Int32?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.autoresizesSubviews = true
        let coordinator = context.coordinator
        coordinator.folder = folder
        coordinator.onExit = onExit
        DispatchQueue.main.async { [weak container] in
            guard let container else { return }
            let terminal = LocalProcessTerminalView(frame: container.bounds)
            terminal.autoresizingMask = [.width, .height]
            terminal.processDelegate = coordinator
            container.addSubview(terminal)
            coordinator.terminal = terminal
            coordinator.start()
        }
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {}

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var folder = NSHomeDirectory()
        var onExit: ((Int32?) -> Void)?
        weak var terminal: LocalProcessTerminalView?

        func start() {
            guard let terminal else { return }
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            terminal.startProcess(executable: shell, args: ["-l"])
            terminal.window?.makeFirstResponder(terminal)
            guard let directory = safeFolder(folder) else { return }
            let line = "cd \(shellQuote(directory)) && clear\n"
            // Give the shell a moment to print its prompt before typing into it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, let terminal = self.terminal else { return }
                terminal.send(source: terminal, data: ArraySlice(Array(line.utf8)))
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

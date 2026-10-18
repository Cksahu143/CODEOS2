import CodeOSCore
import SwiftUI

/// Cmd-K: type part of a section's name and press Return to go there.
struct CommandPalette: View {
    @Binding var selection: AppSection?
    @Binding var isPresented: Bool
    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: [AppSection] {
        PaletteMatcher.filter(AppSection.allCases, query: query) { $0.title }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Go to…", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { open(results.first) }
            List(results) { section in
                Button {
                    open(section)
                } label: {
                    Label(section.title, systemImage: section.icon)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 260)
            HStack {
                Text("Return opens the top match. Escape closes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear { focused = true }
    }

    private func open(_ section: AppSection?) {
        guard let section else { return }
        selection = section
        isPresented = false
    }
}

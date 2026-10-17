import CodeOSCore
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    let open: (AppSection) -> Void
    @State private var snapshot: SystemSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CodeOS").font(.largeTitle).fontWeight(.semibold)
                    Text("Your coding command center").foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    quickAction("Files", icon: "folder", section: .files)
                    quickAction("Applications", icon: "square.grid.2x2", section: .applications)
                    quickAction("Workspaces", icon: "rectangle.3.group", section: .workspaces)
                    quickAction("Developer Tools", icon: "hammer", section: .developer)
                }

                workspacesSection

                if let snapshot {
                    systemSection(snapshot)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Home")
        .onAppear { snapshot = SystemInfo.snapshot() }
    }

    private func quickAction(_ title: String, icon: String, section: AppSection) -> some View {
        Button { open(section) } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    @ViewBuilder
    private var workspacesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workspaces").font(.headline)
            if store.configuration.workspaces.isEmpty {
                EmptyStateView(
                    title: "No workspaces yet",
                    message: "A workspace links a project folder with your editor, documentation, and supporting apps. Open one with a single click.",
                    systemImage: "rectangle.3.group"
                )
                .frame(height: 180)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                Button("Create a Workspace") { open(.workspaces) }
            } else {
                ForEach(store.configuration.workspaces.prefix(6)) { workspace in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workspace.name).fontWeight(.medium)
                            Text(workspace.projectPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Open") {
                            Task { await store.run(WorkspaceLauncher.workflow(for: workspace)) }
                        }
                        .disabled(store.runningWorkflowID != nil)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func systemSection(_ info: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This Mac").font(.headline)
            Text("\(info.osVersion) · \(Format.bytes(info.physicalMemoryBytes)) memory · app built for \(info.appArchitecture)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

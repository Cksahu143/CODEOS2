import CodeOSCore
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case home, workspaces, workflows, files, applications, developer, monitor, storage, devices, tweaks, preview, gitGraph, games, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .workspaces: return "Workspaces"
        case .workflows: return "Workflows"
        case .files: return "Files"
        case .applications: return "Applications"
        case .developer: return "Developer Tools"
        case .monitor: return "Monitor"
        case .storage: return "Storage"
        case .devices: return "Devices"
        case .tweaks: return "Mac Tweaks"
        case .preview: return "Preview"
        case .gitGraph: return "Git Graph"
        case .games: return "Games"
        case .system: return "System"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .workspaces: return "rectangle.3.group"
        case .workflows: return "bolt.horizontal"
        case .files: return "folder"
        case .applications: return "square.grid.2x2"
        case .developer: return "hammer"
        case .monitor: return "waveform.path.ecg"
        case .storage: return "internaldrive"
        case .devices: return "externaldrive"
        case .tweaks: return "slider.horizontal.3"
        case .preview: return "eye"
        case .gitGraph: return "arrow.triangle.branch"
        case .games: return "gamecontroller"
        case .system: return "cpu"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: AppSection? = .home

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .navigationTitle("CodeOS")
        } detail: {
            detail(for: selection ?? .home)
        }
        .alert("CodeOS", isPresented: Binding(
            get: { store.notice != nil },
            set: { if !$0 { store.notice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.notice ?? "")
        }
        .sheet(isPresented: Binding(
            get: { store.lastReport != nil },
            set: { if !$0 { store.lastReport = nil } }
        )) {
            if let report = store.lastReport {
                RunReportView(report: report)
            }
        }
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .home: HomeView(open: { selection = $0 })
        case .workspaces: WorkspacesView()
        case .workflows: WorkflowsView()
        case .files: FilesView()
        case .applications: ApplicationsView()
        case .developer: DeveloperToolsView()
        case .monitor: MonitorView()
        case .storage: StorageView()
        case .devices: DevicesView()
        case .tweaks: MacTweaksView()
        case .preview: PreviewView()
        case .gitGraph: GitGraphView()
        case .games: GamesView()
        case .system: SystemView()
        }
    }
}

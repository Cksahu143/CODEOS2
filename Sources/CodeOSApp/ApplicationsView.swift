import AppKit
import CodeOSCore
import SwiftUI

struct ApplicationsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var errorMessage: String?

    private var apps: [InstalledApp] {
        let matching = store.installedApps.filter {
            query.isEmpty
                || $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleID.localizedCaseInsensitiveContains(query)
        }
        return matching.sorted { lhs, rhs in
            let lhsFavorite = store.favoriteAppIDs.contains(lhs.bundleID)
            let rhsFavorite = store.favoriteAppIDs.contains(rhs.bundleID)
            if lhsFavorite != rhsFavorite { return lhsFavorite }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if store.installedApps.isEmpty {
                EmptyStateView(
                    title: "No applications found",
                    message: "CodeOS looks in /Applications, /System/Applications, and your Applications folder.",
                    systemImage: "square.grid.2x2"
                )
            } else if apps.isEmpty {
                EmptyStateView(title: "No matches", message: "No application matches “\(query)”.", systemImage: "magnifyingglass")
            } else {
                List(apps) { app in
                    row(app)
                        .contextMenu {
                            Button("Open") { launch(app) }
                            Button("Show in Finder") { reveal(app) }
                            Divider()
                            Button(store.favoriteAppIDs.contains(app.bundleID) ? "Remove from Favorites" : "Add to Favorites") {
                                toggleFavorite(app.bundleID)
                            }
                        }
                }
            }
        }
        .navigationTitle("Applications")
        .searchable(text: $query, prompt: "Search applications")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.refreshApps() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .alert("Could not open application", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(_ app: InstalledApp) -> some View {
        let isFavorite = store.favoriteAppIDs.contains(app.bundleID)
        return HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).fontWeight(.medium)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button { toggleFavorite(app.bundleID) } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            Button("Open") { launch(app) }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { launch(app) }
    }

    private func launch(_ app: InstalledApp) {
        Task {
            do {
                try await NativeOpen.launch(URL(fileURLWithPath: app.path))
            } catch {
                errorMessage = "\(app.name): \(error.localizedDescription)"
            }
        }
    }

    private func reveal(_ app: InstalledApp) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }

    private func toggleFavorite(_ bundleID: String) {
        if store.favoriteAppIDs.contains(bundleID) {
            store.favoriteAppIDs.remove(bundleID)
        } else {
            store.favoriteAppIDs.insert(bundleID)
        }
    }
}

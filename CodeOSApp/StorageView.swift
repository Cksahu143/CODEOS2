import AppKit
import CodeOSCore
import SwiftUI

/// Shows developer caches and build artifacts with their sizes. Nothing is deleted
/// without confirmation, and removal goes to the Trash so it can be undone.
struct StorageView: View {
    @State private var caches: [CacheLocation] = StorageAdvisor.knownCaches()
    @State private var cacheSizes: [String: Int64] = [:]
    @State private var scanRoot: String?
    @State private var artifacts: [String] = []
    @State private var artifactSizes: [String: Int64] = [:]
    @State private var isScanning = false
    @State private var pendingTrash: [String] = []
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                cacheSection
                artifactSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Storage")
        .task { await measureCaches() }
        .confirmationDialog(
            "Move \(pendingTrash.count) item(s) to the Trash?",
            isPresented: Binding(get: { !pendingTrash.isEmpty }, set: { if !$0 { pendingTrash = [] } })
        ) {
            Button("Move to Trash", role: .destructive) { moveToTrash(pendingTrash) }
        } message: {
            Text("You can restore these from the Trash. Rebuilt or downloaded data will return when needed.")
        }
        .alert("Storage", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Developer caches").font(.headline)
                Spacer()
                Button { Task { await measureCaches() } } label: {
                    Label("Measure", systemImage: "arrow.clockwise")
                }
                .disabled(isScanning)
            }
            ForEach(caches) { cache in
                let size = cacheSizes[cache.path]
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cache.name).fontWeight(.medium)
                        Text(cache.note).font(.caption).foregroundStyle(.secondary)
                        Text(cache.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(sizeText(size, exists: FileManager.default.fileExists(atPath: cache.path)))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button("Move to Trash") { pendingTrash = [cache.path] }
                        .disabled((size ?? 0) == 0)
                }
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var artifactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Project build artifacts").font(.headline)
                Spacer()
                Button("Scan a Folder…") { chooseAndScan() }
                    .disabled(isScanning)
            }
            Text("Finds node_modules, .build, and build folders inside a folder you choose. Source files are never touched.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isScanning {
                ProgressView().controlSize(.small)
            }
            if let scanRoot, !isScanning {
                Text("\(artifacts.count) item(s) in \(scanRoot)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !artifacts.isEmpty {
                    Button("Move All \(artifacts.count) to Trash") { pendingTrash = artifacts }
                        .disabled(artifacts.isEmpty)
                }
                ForEach(artifacts, id: \.self) { path in
                    HStack {
                        Text(relative(path, to: scanRoot))
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(sizeText(artifactSizes[path], exists: true))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button("Trash") { pendingTrash = [path] }
                            .buttonStyle(.link)
                    }
                }
            }
        }
    }

    private func sizeText(_ size: Int64?, exists: Bool) -> String {
        guard exists else { return "Not present" }
        guard let size else { return "Measuring…" }
        return size == 0 ? "Empty" : Format.bytes(size)
    }

    private func relative(_ path: String, to root: String) -> String {
        path.hasPrefix(root) ? String(path.dropFirst(root.count).drop(while: { $0 == "/" })) : path
    }

    private func measureCaches() async {
        isScanning = true
        let locations = caches
        let sizes = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: locations.map { ($0.path, StorageAdvisor.size(of: $0.path)) })
        }.value
        cacheSizes = sizes
        isScanning = false
    }

    private func chooseAndScan() {
        guard let folder = FolderPicker.chooseFolder(prompt: "Scan") else { return }
        scanRoot = folder
        Task {
            isScanning = true
            let found = await Task.detached(priority: .utility) {
                StorageAdvisor.findArtifacts(in: folder, named: ["node_modules", ".build", "build"])
            }.value
            let sizes = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: found.map { ($0, StorageAdvisor.size(of: $0)) })
            }.value
            artifacts = found
            artifactSizes = sizes
            isScanning = false
        }
    }

    private func moveToTrash(_ paths: [String]) {
        var failures: [String] = []
        for path in paths {
            do {
                try StorageAdvisor.moveToTrash(path)
            } catch {
                failures.append("\((path as NSString).lastPathComponent): \(error.localizedDescription)")
            }
        }
        pendingTrash = []
        artifacts.removeAll { !FileManager.default.fileExists(atPath: $0) }
        Task { await measureCaches() }
        if !failures.isEmpty {
            message = "Some items could not be moved:\n" + failures.joined(separator: "\n")
        }
    }
}

import CodeOSCore
import SwiftUI

struct SystemView: View {
    @State private var snapshot: SystemSnapshot?

    var body: some View {
        Form {
            if let info = snapshot {
                Section("macOS") {
                    LabeledContent("Version", value: info.osVersion)
                }
                Section("Hardware") {
                    LabeledContent("Model", value: info.hardwareModel ?? "Unavailable")
                    LabeledContent("Processor", value: info.cpuBrand ?? "Unavailable")
                    LabeledContent("Architecture", value: info.machineArchitecture ?? "Unavailable")
                    LabeledContent("Memory", value: Format.bytes(info.physicalMemoryBytes))
                }
                Section("Storage · \(info.volumePath)") {
                    LabeledContent("Total", value: info.volumeTotalBytes.map { Format.bytes($0) } ?? "Unavailable")
                    LabeledContent("Available", value: info.volumeAvailableBytes.map { Format.bytes($0) } ?? "Unavailable")
                }
                Section("CodeOS") {
                    LabeledContent("Built for", value: info.appArchitecture)
                }
                Section {
                    Text("Figures are read from macOS when this view appears. Use Refresh to update them. This version does not monitor running processes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("System")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { snapshot = SystemInfo.snapshot() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { snapshot = SystemInfo.snapshot() }
    }
}

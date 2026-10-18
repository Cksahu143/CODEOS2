import CodeOSCore
import SwiftUI

/// Connected USB devices, shown as the tree macOS reports (controllers, hubs, devices).
struct DevicesView: View {
    @State private var devices: [USBDevice] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("USB devices").font(.title2).fontWeight(.semibold)
                Spacer()
                Button { Task { await refresh() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(loading)
            }
            if loading {
                ProgressView().controlSize(.small)
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            if devices.isEmpty && !loading && error == nil {
                EmptyStateView(
                    title: "No USB devices found",
                    message: "Plug a device in, then press Refresh.",
                    systemImage: "externaldrive")
            } else {
                List(devices) { device in
                    HStack(spacing: 10) {
                        Image(systemName: device.isHub ? "square.stack.3d.up" : "externaldrive")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).fontWeight(device.depth == 0 ? .semibold : .regular)
                            Text(details(device))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                    }
                    .padding(.leading, CGFloat(device.depth) * 18)
                }
            }
            Text("Read-only. Ejecting and power control are not included yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .navigationTitle("Devices")
        .task { await refresh() }
    }

    private func details(_ device: USBDevice) -> String {
        var parts: [String] = []
        if let manufacturer = device.manufacturer { parts.append(manufacturer) }
        if let serial = device.serial { parts.append("serial \(serial)") }
        if let speed = device.speed { parts.append(speed.replacingOccurrences(of: "_", with: " ")) }
        return parts.isEmpty ? "No details reported" : parts.joined(separator: " · ")
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            devices = try await Task.detached(priority: .utility) { try USBMonitor.list() }.value
            error = nil
        } catch {
            devices = []
            self.error = error.localizedDescription
        }
    }
}

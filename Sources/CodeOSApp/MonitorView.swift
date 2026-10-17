import CodeOSCore
import SwiftUI

/// Live view of memory, the busiest processes, and TCP ports that are listening.
struct MonitorView: View {
    @State private var memory: MemoryBreakdown?
    @State private var processes: [ProcessSample] = []
    @State private var ports: [ListeningPort] = []
    @State private var lastUpdated: Date?
    @State private var refreshInterval = 5
    @State private var paused = false
    @State private var thermal: ThermalSnapshot?
    @AppStorage("fanControlEnabled") private var fanControlEnabled = false
    @State private var fanTarget: Double = 2000
    @State private var fanBusy = false
    @State private var fanStatus: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                memorySection
                sensorSection
                fanControlSection
                HStack(alignment: .top, spacing: 24) {
                    processSection
                    portSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Monitor")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Refresh", selection: $refreshInterval) {
                    Text("Every 2 s").tag(2)
                    Text("Every 5 s").tag(5)
                    Text("Every 10 s").tag(10)
                }
                .frame(width: 130)
                Button { paused.toggle() } label: {
                    Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
                }
            }
        }
        .task(id: "\(refreshInterval)-\(paused)") {
            guard !paused else { return }
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: UInt64(refreshInterval) * 1_000_000_000)
            }
        }
    }

    private var sensorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Temperature and fans").font(.headline)
            if let thermal, thermal.sensorsAvailable, !(thermal.temperatures.isEmpty && thermal.fans.isEmpty) {
                HStack(alignment: .top, spacing: 36) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(thermal.temperatures, id: \.name) { reading in
                            stat(reading.name, String(format: "%.0f °C", reading.celsius))
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(thermal.fans, id: \.name) { fan in
                            stat(fan.name, "\(fan.rpm) RPM" + range(fan))
                        }
                    }
                }
            } else {
                Text(thermal?.note ?? "Reading sensors…").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    private func range(_ fan: FanReading) -> String {
        guard let minRPM = fan.minRPM, let maxRPM = fan.maxRPM else { return "" }
        var text = "  (\(minRPM)–\(maxRPM))"
        if let mode = fan.mode { text += mode == 0 ? "  · auto" : "  · manual" }
        if let target = fan.target { text += "  · target \(target)" }
        return text
    }

    private var fanControlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fan control").font(.headline)
            Toggle("Allow CodeOS to set fan speed (asks for your administrator password each time)", isOn: $fanControlEnabled)
            if fanControlEnabled, let fan = thermal?.fans.first, let low = fan.minRPM, let high = fan.maxRPM, high > low {
                HStack {
                    Slider(value: $fanTarget, in: Double(low)...Double(high), step: 100)
                    Text("\(Int(fanTarget)) RPM")
                        .font(.callout.monospacedDigit())
                        .frame(width: 90, alignment: .trailing)
                }
                HStack(spacing: 10) {
                    Button("Set speed") { Task { @MainActor in apply { try FanControl.setManual(fan: 0, rpm: Int(fanTarget)) } } }
                        .disabled(fanBusy)
                    Button("Return to automatic") { Task { @MainActor in apply { try FanControl.restoreAutomatic() } } }
                        .disabled(fanBusy)
                    if fanBusy { ProgressView().controlSize(.small) }
                }
                Text("Speeds stay within this fan's range (\(low)–\(high) RPM). Fans return to automatic when CodeOS quits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let fanStatus {
                Text(fanStatus).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func apply(_ change: @MainActor @escaping () throws -> Void) {
        fanBusy = true
        Task { @MainActor in
            defer { fanBusy = false }
            do {
                try change()
                fanStatus = FanControl.isManualActive
                    ? "Fan 1 is under manual control. It returns to automatic when CodeOS quits."
                    : "Fans are under automatic control."
            } catch {
                fanStatus = error.localizedDescription
            }
        }
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Memory").font(.headline)
            if let memory {
                ProgressView(value: memory.usageFraction)
                    .tint(memory.usageFraction > 0.85 ? .red : .accentColor)
                HStack(spacing: 18) {
                    stat("Used", Format.bytes(memory.usedBytes))
                    stat("App & system", Format.bytes(memory.activeBytes + memory.wiredBytes))
                    stat("Compressed", Format.bytes(memory.compressedBytes))
                    stat("Inactive", Format.bytes(memory.inactiveBytes))
                    stat("Free", Format.bytes(memory.freeBytes))
                    stat("Total", Format.bytes(memory.totalBytes))
                }
            } else {
                Text("Memory statistics are unavailable.").foregroundStyle(.secondary)
            }
            if let lastUpdated {
                Text("Updated \(Format.date(lastUpdated))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Busiest processes").font(.headline)
            if processes.isEmpty {
                Text("No process data yet.").foregroundStyle(.secondary)
            }
            ForEach(processes) { process in
                HStack(spacing: 10) {
                    Text(process.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(String(format: "%.1f%% CPU", process.cpuPercent))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .trailing)
                    Text(Format.bytes(process.residentBytes))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .help(process.command)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var portSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Listening ports").font(.headline)
            if ports.isEmpty {
                Text("No listening TCP ports found.").foregroundStyle(.secondary)
            }
            ForEach(ports) { port in
                HStack(spacing: 10) {
                    Text(":\(port.port)")
                        .font(.callout.monospacedDigit())
                        .fontWeight(.medium)
                        .frame(width: 70, alignment: .leading)
                    Text(port.processName).lineLimit(1)
                    Spacer()
                    Text(port.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit())
        }
    }

    private func refresh() async {
        memory = await Task.detached(priority: .utility) { MemoryMonitor.breakdown() }.value
        processes = await Task.detached(priority: .utility) { (try? ProcessMonitor.sample(limit: 15)) ?? [] }.value
        ports = await Task.detached(priority: .utility) { (try? PortScanner.listening()) ?? [] }.value
        thermal = await Task.detached(priority: .utility) { ThermalMonitor.read() }.value
        lastUpdated = Date()
    }
}

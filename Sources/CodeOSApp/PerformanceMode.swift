import CodeOSCore
import Foundation

/// One switch for performance: Low Power Mode off, and the Mac kept awake. Everything it changes is restored
/// on toggle-off or quit. Its keep-awake process exits by itself if CodeOS crashes.
@MainActor
final class PerformanceMode: ObservableObject {
    static let shared = PerformanceMode()

    private static let onKey = "performanceModeOn"
    private static let changedKey = "performanceModeChangedLowPower"

    @Published private(set) var isOn: Bool
    @Published private(set) var status: String?
    private var keepAwake: Process?

    private init() {
        isOn = false
        // A previous run that left the switch on means CodeOS quit or crashed while it was on.
        if UserDefaults.standard.bool(forKey: PerformanceMode.onKey) {
            UserDefaults.standard.set(false, forKey: PerformanceMode.onKey)
            status = "Performance mode was on when CodeOS last quit. Low Power Mode was not changed back automatically."
        }
    }

    func toggle() async {
        if isOn {
            await turnOff()
        } else {
            await turnOn()
        }
    }

    private func turnOn() async {
        do {
            let current = try lowPowerState()
            var changed = false
            if current == true {
                try setLowPower(false)
                changed = true
            }
            startKeepAwake()
            UserDefaults.standard.set(changed, forKey: PerformanceMode.changedKey)
            UserDefaults.standard.set(true, forKey: PerformanceMode.onKey)
            isOn = true
            status = current == nil
                ? "On. This Mac does not report Low Power Mode, so only keep-awake was applied."
                : "On. Low Power Mode is off and the Mac stays awake until you turn this off."
        } catch {
            status = "Could not turn performance mode on: " + error.localizedDescription
        }
    }

    private func turnOff() async {
        stopKeepAwake()
        UserDefaults.standard.set(false, forKey: PerformanceMode.onKey)
        isOn = false
        do {
            if UserDefaults.standard.bool(forKey: PerformanceMode.changedKey) {
                try setLowPower(true)
            }
            UserDefaults.standard.set(false, forKey: PerformanceMode.changedKey)
            status = "Off. Your previous power settings are restored."
        } catch {
            status = "Off, but Low Power Mode could not be restored: " + error.localizedDescription
        }
    }

    /// Called when CodeOS quits. Restores Low Power Mode if this session turned it off.
    func restoreOnQuit() {
        stopKeepAwake()
        guard UserDefaults.standard.bool(forKey: PerformanceMode.changedKey) else { return }
        try? setLowPower(true)
        UserDefaults.standard.set(false, forKey: PerformanceMode.changedKey)
        UserDefaults.standard.set(false, forKey: PerformanceMode.onKey)
    }

    private func lowPowerState() throws -> Bool? {
        let result = try ProcessRunner.run(executable: "/usr/bin/pmset", arguments: ["-g"], timeout: 5)
        guard result.succeeded else { return nil }
        return PowerModeParser.lowPowerMode(fromPmsetOutput: result.stdout)
    }

    /// pmset needs administrator rights. The value is a fixed 0 or 1, never typed text.
    private func setLowPower(_ on: Bool) throws {
        let value = on ? "1" : "0"
        let result = try ProcessRunner.run(
            executable: "/usr/bin/osascript",
            arguments: ["-e", "do shell script \"/usr/bin/pmset -a lowpowermode " + value + "\" with administrator privileges"],
            timeout: 120)
        guard result.succeeded else {
            if result.stderr.contains("-128") { throw PerformanceError.cancelled }
            throw PerformanceError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func startKeepAwake() {
        stopKeepAwake()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -w exits caffeinate when this CodeOS process exits, so a crash cannot leave the Mac awake.
        process.arguments = ["-dims", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        try? process.run()
        keepAwake = process
    }

    private func stopKeepAwake() {
        keepAwake?.terminate()
        keepAwake = nil
    }
}

enum PerformanceError: LocalizedError {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Cancelled. Your admin password was not entered."
        case .failed(let message): return message.isEmpty ? "macOS refused the power change." : message
        }
    }
}

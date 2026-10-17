import AppKit
import CodeOSCore
import Foundation

enum FanAppError: LocalizedError {
    case helperMissing
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing: return "The fan helper is missing from the app. Rebuild CodeOS."
        case .cancelled: return "Cancelled. The fan speed was not changed."
        case .failed(let message): return message
        }
    }
}

/// Runs the fan helper as root through macOS's administrator prompt.
/// Only validated numbers and fixed words are ever passed to it.
@MainActor
enum FanControl {
    private static let manualKey = "fanManualActive"

    static var isManualActive: Bool { UserDefaults.standard.bool(forKey: manualKey) }

    static func setManual(fan: Int, rpm: Int) throws {
        try runHelper(["set", String(fan), String(rpm)])
        UserDefaults.standard.set(true, forKey: manualKey)
    }

    static func restoreAutomatic() throws {
        try runHelper(["auto"])
        UserDefaults.standard.set(false, forKey: manualKey)
    }

    /// Restores automatic control when a manual speed was set and not yet returned.
    /// Called at launch (after a crash) and at quit.
    static func restoreIfNeeded() {
        guard isManualActive else { return }
        try? restoreAutomatic()
    }

    @discardableResult
    private static func runHelper(_ arguments: [String]) throws -> String {
        guard let helper = Bundle.main.url(forAuxiliaryExecutable: "codeos-fanctl")?.path else {
            throw FanAppError.helperMissing
        }
        let all = [helper] + arguments
        guard all.allSatisfy({ !$0.contains("'") && !$0.contains("\"") && !$0.contains("\\") }) else {
            throw FanAppError.helperMissing
        }
        let command = all.map { "'\($0)'" }.joined(separator: " ")
        let source = "do shell script \"\(command)\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            throw FanAppError.failed("The request could not be prepared.")
        }
        var info: NSDictionary?
        let result = script.executeAndReturnError(&info)
        if let info {
            if (info[NSAppleScript.errorNumber] as? Int) == -128 { throw FanAppError.cancelled }
            throw FanAppError.failed((info[NSAppleScript.errorMessage] as? String) ?? "The fan helper failed.")
        }
        return result.stringValue ?? ""
    }
}

/// Makes sure the fans go back to automatic when CodeOS starts after a crash, and when it quits.
@MainActor
final class FanSafetyDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FanControl.restoreIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        FanControl.restoreIfNeeded()
    }
}

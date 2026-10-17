import CodeOSCore
import Foundation

/// Reads and changes the system-wide light/dark appearance.
/// Setting it uses Apple's scripting bridge to System Events, which macOS gates behind
/// a one-time Automation permission. The result is verified by reading it back.
@MainActor
enum SystemAppearance {
    static func isDark() -> Bool {
        guard let result = try? ProcessRunner.run(
            executable: "/usr/bin/defaults",
            arguments: ["read", "-g", "AppleInterfaceStyle"],
            timeout: 3
        ) else { return false }
        // The key is absent in light mode, so a failed read means light.
        return result.succeeded && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "Dark"
    }

    static func setDark(_ dark: Bool) throws {
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark ? "true" : "false")"
        guard let script = NSAppleScript(source: source) else {
            throw AppActionError.appearanceChangeFailed("The appearance script could not be created.")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return }

        let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
        if code == -1743 {
            throw AppActionError.appearanceChangeFailed(
                "macOS did not allow CodeOS to control System Events. Allow it in System Settings > Privacy & Security > Automation, then try again."
            )
        }
        let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown error \(code)."
        throw AppActionError.appearanceChangeFailed(message)
    }

    /// Changes the appearance and waits until macOS reports the new value.
    static func apply(dark: Bool) async throws {
        try setDark(dark)
        for _ in 0..<15 {
            if isDark() == dark { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw AppActionError.appearanceChangeFailed("macOS did not report the new appearance. Check System Settings > Appearance.")
    }
}

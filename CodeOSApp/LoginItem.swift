import Foundation
import ServiceManagement

/// Launch at login through the modern Service Management API (macOS 13+).
/// It works from an installed app bundle, so a build folder may report an error.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

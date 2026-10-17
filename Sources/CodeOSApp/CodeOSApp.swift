import AppKit
import SwiftUI

@main
struct CodeOSApp: App {
    @NSApplicationDelegateAdaptor(FanSafetyDelegate.self) private var fanSafety
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("CodeOS") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 960, minHeight: 620)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

import AppKit
import CodeOSCore
import Foundation

/// CodeOS's own window appearance. This never changes the system-wide appearance.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Single source of truth for the UI. Persists configuration through ConfigStore
/// and interface preferences through UserDefaults.
@MainActor
final class AppStore: ObservableObject {
    @Published var configuration: AppConfiguration
    @Published var notice: String?
    @Published private(set) var installedApps: [InstalledApp] = []
    @Published var lastReport: WorkflowRunReport?
    @Published private(set) var runningWorkflowID: UUID?

    @Published var appearance: AppearancePreference {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance()
        }
    }

    @Published var showHiddenFiles: Bool {
        didSet { UserDefaults.standard.set(showHiddenFiles, forKey: Keys.showHidden) }
    }

    @Published var favoriteAppIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(favoriteAppIDs).sorted(), forKey: Keys.favorites) }
    }

    let configStore: ConfigStore

    private enum Keys {
        static let appearance = "appearance"
        static let showHidden = "showHiddenFiles"
        static let favorites = "favoriteAppBundleIDs"
    }

    init(configStore: ConfigStore? = nil) {
        self.configStore = configStore ?? AppStore.defaultConfigStore()
        let defaults = UserDefaults.standard
        appearance = AppearancePreference(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        showHiddenFiles = defaults.bool(forKey: Keys.showHidden)
        favoriteAppIDs = Set(defaults.stringArray(forKey: Keys.favorites) ?? [])

        do {
            let result = try configStore.load()
            configuration = result.configuration
            if case let .recoveredFromCorruptFile(backup) = result.outcome {
                notice = "Your configuration file could not be read and was moved to “\(backup.lastPathComponent)”. CodeOS started with empty settings."
            }
        } catch {
            configuration = AppConfiguration()
            notice = "CodeOS could not load its configuration: \(error.localizedDescription)"
        }
        applyAppearance()
        refreshApps()
    }

    static func defaultConfigStore() -> ConfigStore {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return ConfigStore(fileURL: base.appendingPathComponent("CodeOS/config.json"))
    }

    func applyAppearance() {
        NSApplication.shared.appearance = appearance.nsAppearance
    }

    func refreshApps() {
        installedApps = AppDiscovery.scan()
    }

    func appName(for bundleID: String) -> String {
        installedApps.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    // MARK: Workspaces and workflows

    func upsert(_ workspace: Workspace) {
        if let index = configuration.workspaces.firstIndex(where: { $0.id == workspace.id }) {
            configuration.workspaces[index] = workspace
        } else {
            configuration.workspaces.append(workspace)
        }
        persist()
    }

    func deleteWorkspace(id: UUID) {
        configuration.workspaces.removeAll { $0.id == id }
        persist()
    }

    func upsert(_ workflow: Workflow) {
        if let index = configuration.workflows.firstIndex(where: { $0.id == workflow.id }) {
            configuration.workflows[index] = workflow
        } else {
            configuration.workflows.append(workflow)
        }
        persist()
    }

    func deleteWorkflow(id: UUID) {
        configuration.workflows.removeAll { $0.id == id }
        persist()
    }

    /// Runs a workflow once at a time. A second request while one is running is ignored.
    func run(_ workflow: Workflow) async {
        guard runningWorkflowID == nil else { return }
        runningWorkflowID = workflow.id
        let report = await WorkflowRunner.run(workflow, using: AppActionExecutor())
        runningWorkflowID = nil
        lastReport = report
    }

    private func persist() {
        do {
            try configStore.save(configuration)
        } catch {
            notice = "Your changes could not be saved: \(error.localizedDescription)"
        }
    }
}

import Foundation

/// A project and the environment needed to work on it.
public struct Workspace: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    /// Absolute path to the project root chosen by the user.
    public var projectPath: String
    /// Bundle identifier of the preferred editor. `nil` opens the folder with the default handler.
    public var editorBundleID: String?
    public var documentationURLs: [String]
    public var supportingAppBundleIDs: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        projectPath: String,
        editorBundleID: String? = nil,
        documentationURLs: [String] = [],
        supportingAppBundleIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.projectPath = projectPath
        self.editorBundleID = editorBundleID
        self.documentationURLs = documentationURLs
        self.supportingAppBundleIDs = supportingAppBundleIDs
    }
}

/// One explicitly configured step. Workflows store typed actions, never shell strings.
public enum WorkflowAction: Codable, Equatable {
    case openFolder(path: String)
    case openFolderInApp(bundleID: String, path: String)
    case openURL(String)
    case launchApp(bundleID: String)
    case openTerminal(path: String)
    case gitStatus(repoPath: String)
    /// Switches the whole Mac between light and dark appearance.
    case setSystemAppearance(dark: Bool)
    /// Runs an executable with an explicit argument list. No shell is involved.
    case runCommand(executable: String, arguments: [String], workingDirectory: String?)

    /// Human-readable description for previews and reports.
    public var title: String {
        switch self {
        case .openFolder(let path): return "Open folder \(path)"
        case .openFolderInApp(let bundleID, let path): return "Open \(path) in \(bundleID)"
        case .openURL(let url): return "Open link \(url)"
        case .launchApp(let bundleID): return "Launch \(bundleID)"
        case .openTerminal(let path): return "Open Terminal at \(path)"
        case .gitStatus(let repoPath): return "Check Git status of \(repoPath)"
        case .setSystemAppearance(let dark): return dark ? "Switch macOS to Dark appearance" : "Switch macOS to Light appearance"
        case .runCommand(let executable, let arguments, _):
            return (["Run", executable] + arguments).joined(separator: " ")
        }
    }
}

public struct Workflow: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var actions: [WorkflowAction]

    public init(id: UUID = UUID(), name: String, actions: [WorkflowAction]) {
        self.id = id
        self.name = name
        self.actions = actions
    }

    /// True when any step runs a command, so the UI can ask for confirmation first.
    public var runsCommands: Bool {
        actions.contains { action in
            if case .runCommand = action { return true }
            return false
        }
    }
}

/// Top-level persisted configuration. `schemaVersion` allows future migrations.
public struct AppConfiguration: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var workspaces: [Workspace]
    public var workflows: [Workflow]

    public init(
        schemaVersion: Int = AppConfiguration.currentSchemaVersion,
        workspaces: [Workspace] = [],
        workflows: [Workflow] = []
    ) {
        self.schemaVersion = schemaVersion
        self.workspaces = workspaces
        self.workflows = workflows
    }
}

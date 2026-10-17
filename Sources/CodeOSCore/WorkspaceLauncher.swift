import Foundation

/// Turns a workspace into an ordinary workflow, so it runs through the same reporting path.
public enum WorkspaceLauncher {
    public static func workflow(for workspace: Workspace) -> Workflow {
        var actions: [WorkflowAction] = []
        if let editor = workspace.editorBundleID, !editor.isEmpty {
            actions.append(.openFolderInApp(bundleID: editor, path: workspace.projectPath))
        } else {
            actions.append(.openFolder(path: workspace.projectPath))
        }
        actions.append(.openTerminal(path: workspace.projectPath))
        actions.append(contentsOf: workspace.documentationURLs.map { WorkflowAction.openURL($0) })
        actions.append(contentsOf: workspace.supportingAppBundleIDs.map { WorkflowAction.launchApp(bundleID: $0) })
        // Same id as the workspace, so the UI can show "running" for the right row.
        return Workflow(id: workspace.id, name: "Open \(workspace.name)", actions: actions)
    }
}

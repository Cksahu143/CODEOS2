import Foundation

public enum Validation {
    /// Human-readable problems. An empty array means the workspace is valid.
    public static func problems(in workspace: Workspace) -> [String] {
        var issues: [String] = []
        if workspace.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("The workspace needs a name.")
        }
        if !workspace.projectPath.hasPrefix("/") {
            issues.append("The project folder must be an absolute path.")
        }
        for url in workspace.documentationURLs where !isWebURL(url) {
            issues.append("Documentation link is not a valid http(s) URL: \(url)")
        }
        if Set(workspace.supportingAppBundleIDs).count != workspace.supportingAppBundleIDs.count {
            issues.append("Supporting applications contain duplicates.")
        }
        return issues
    }

    /// Human-readable problems. An empty array means the workflow is valid.
    public static func problems(in workflow: Workflow) -> [String] {
        var issues: [String] = []
        if workflow.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("The workflow needs a name.")
        }
        if workflow.actions.isEmpty {
            issues.append("The workflow has no steps.")
        }
        for (index, action) in workflow.actions.enumerated() {
            let step = index + 1
            switch action {
            case .openFolder(let path), .openTerminal(let path), .gitStatus(let path):
                if !path.hasPrefix("/") { issues.append("Step \(step): the folder must be an absolute path.") }
            case .openFolderInApp(let bundleID, let path):
                if !path.hasPrefix("/") { issues.append("Step \(step): the folder must be an absolute path.") }
                if bundleID.trimmingCharacters(in: .whitespaces).isEmpty {
                    issues.append("Step \(step): choose an application.")
                }
            case .openURL(let url):
                if !isWebURL(url) { issues.append("Step \(step): the link must start with http:// or https://.") }
            case .launchApp(let bundleID):
                if bundleID.trimmingCharacters(in: .whitespaces).isEmpty {
                    issues.append("Step \(step): choose an application.")
                }
            case .setSystemAppearance:
                break
            case .runCommand(let executable, _, let workingDirectory):
                if !executable.hasPrefix("/") {
                    issues.append("Step \(step): the command must be an absolute path to an executable file.")
                }
                if let workingDirectory, !workingDirectory.hasPrefix("/") {
                    issues.append("Step \(step): the working folder must be an absolute path.")
                }
            }
        }
        return issues
    }

    public static func isWebURL(_ string: String) -> Bool {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && !(url.host ?? "").isEmpty
    }
}

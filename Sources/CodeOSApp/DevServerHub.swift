import CodeOSCore
import Foundation

enum DevServerHubError: LocalizedError {
    case notAPreviewScript(String)

    var errorDescription: String? {
        switch self {
        case .notAPreviewScript(let script):
            return "“\(script)” is not a preview script. CodeOS starts dev, start, or serve scripts."
        }
    }
}

/// Owns the preview servers CodeOS starts, so they survive navigation and stop on quit.
@MainActor
final class DevServerHub: ObservableObject {
    static let shared = DevServerHub()
    static let previewScripts = ["dev", "start", "serve"]

    /// Changes whenever a server starts, stops, or prints output.
    @Published private(set) var revision = 0
    private var servers: [String: DevServerProcess] = [:]

    func server(for path: String) -> DevServerProcess? {
        servers[path]
    }

    func start(project: GameProject, script: String, npmPath: String) throws {
        guard DevServerHub.previewScripts.contains(script), project.scripts.contains(script) else {
            throw DevServerHubError.notAPreviewScript(script)
        }
        if servers[project.path]?.isRunning == true { return }
        let server = DevServerProcess()
        server.onChange = {
            Task { @MainActor [weak self] in self?.revision += 1 }
        }
        try server.start(
            executable: "/usr/bin/env",
            arguments: ["PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", npmPath, "run", script],
            workingDirectory: project.path)
        servers[project.path] = server
        revision += 1
    }

    func stop(path: String) {
        servers[path]?.stop()
        revision += 1
    }

    func stopAll() {
        for server in servers.values {
            server.stop()
        }
    }
}

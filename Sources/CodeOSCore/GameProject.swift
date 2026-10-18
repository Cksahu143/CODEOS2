import Foundation

public struct GameProject: Equatable {
    public let name: String
    public let path: String
    /// Engine dependencies with their version ranges, such as ("phaser", "^3.80.1").
    public let engines: [(name: String, version: String)]
    public let usesTypeScript: Bool
    public let bundler: String?
    public let scripts: [String]
    public let hasIndexHTML: Bool
    public let assetFolders: [String]
    public let hasNodeModules: Bool
    /// Plain-language problems that would stop the project from running.
    public let issues: [String]

    public static func == (lhs: GameProject, rhs: GameProject) -> Bool {
        lhs.name == rhs.name && lhs.path == rhs.path && lhs.scripts == rhs.scripts
            && lhs.issues == rhs.issues && lhs.hasIndexHTML == rhs.hasIndexHTML
            && lhs.assetFolders == rhs.assetFolders && lhs.bundler == rhs.bundler
            && lhs.usesTypeScript == rhs.usesTypeScript && lhs.hasNodeModules == rhs.hasNodeModules
            && lhs.engines.map(\.name) == rhs.engines.map(\.name)
    }
}

public enum GameError: Error, LocalizedError, Equatable {
    case notRunnable(String)

    public var errorDescription: String? {
        switch self {
        case .notRunnable(let script):
            return "“\(script)” is not a script CodeOS runs. Use Terminal for dev servers and other long-running scripts."
        }
    }
}

/// Reads a project folder and reports what it is. It never writes to the folder.
public enum GameProjectDetector {
    static let engineNames = ["phaser", "phaser3", "pixi.js", "kaboom", "three"]
    static let bundlers = ["vite", "webpack", "parcel", "esbuild"]

    public static func inspect(folder: String) -> GameProject {
        let fm = FileManager.default
        let fallbackName = (folder as NSString).lastPathComponent
        var issues: [String] = []
        let packageURL = URL(fileURLWithPath: folder).appendingPathComponent("package.json")

        var object: [String: Any] = [:]
        if let data = try? Data(contentsOf: packageURL) {
            if let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                object = parsed
            } else {
                issues.append("package.json is not valid JSON.")
            }
        } else {
            issues.append("No package.json found in this folder.")
        }

        let dependencies = (object["dependencies"] as? [String: String]) ?? [:]
        let devDependencies = (object["devDependencies"] as? [String: String]) ?? [:]
        let all = dependencies.merging(devDependencies) { first, _ in first }

        let engines = engineNames.compactMap { name -> (name: String, version: String)? in
            guard let version = all[name] else { return nil }
            return (name, version)
        }
        if engines.isEmpty && !object.isEmpty {
            issues.append("No game engine (such as Phaser) is listed in the dependencies.")
        }
        let bundler = bundlers.first { all[$0] != nil }
        let scripts = ((object["scripts"] as? [String: String]) ?? [:]).keys.sorted()
        if scripts.isEmpty && !object.isEmpty {
            issues.append("No npm scripts are defined, so there is nothing to build or test.")
        }

        let hasIndex = fm.fileExists(atPath: (folder as NSString).appendingPathComponent("index.html"))
            || fm.fileExists(atPath: (folder as NSString).appendingPathComponent("public/index.html"))
        if !hasIndex {
            issues.append("No index.html found. A browser preview needs one.")
        }
        let hasModules = fm.fileExists(atPath: (folder as NSString).appendingPathComponent("node_modules"))
        if !object.isEmpty && !hasModules {
            issues.append("Dependencies are not installed. Run npm install in Terminal first.")
        }

        let assets = ["assets", "public/assets", "src/assets"].filter { relative in
            var isDirectory: ObjCBool = false
            let full = (folder as NSString).appendingPathComponent(relative)
            return fm.fileExists(atPath: full, isDirectory: &isDirectory) && isDirectory.boolValue
        }

        return GameProject(
            name: (object["name"] as? String) ?? fallbackName,
            path: folder,
            engines: engines,
            usesTypeScript: all["typescript"] != nil,
            bundler: bundler,
            scripts: scripts,
            hasIndexHTML: hasIndex,
            assetFolders: assets,
            hasNodeModules: hasModules,
            issues: issues)
    }
}

/// Runs only the checks CodeOS allows: build, test, lint, typecheck, and check.
/// Dev servers and other scripts that run until stopped stay in Terminal.
public enum GameProjectRunner {
    public static let runnableScripts = ["build", "test", "lint", "typecheck", "check"]

    public static func runnable(_ scripts: [String]) -> [String] {
        scripts.filter { runnableScripts.contains($0) }
    }

    /// Runs `npm run <script>` with an argument list. The PATH is set so Homebrew's Node is found.
    public static func run(project: GameProject, script: String, npmPath: String) throws -> ProcessResult {
        guard project.scripts.contains(script), runnableScripts.contains(script) else {
            throw GameError.notRunnable(script)
        }
        return try ProcessRunner.run(
            executable: "/usr/bin/env",
            arguments: ["PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", npmPath, "run", script],
            workingDirectory: project.path,
            timeout: 900)
    }
}

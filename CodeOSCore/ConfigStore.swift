import Foundation

public enum ConfigStoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case writeFailed(String)
}

/// Loads and saves `AppConfiguration` as JSON.
/// - Missing file: returns defaults.
/// - Corrupt file: moved aside to a timestamped backup, never deleted.
/// - Newer schema: refused, so a newer file is never overwritten by an older app.
public struct ConfigStore {
    public enum LoadOutcome: Equatable {
        case loaded
        case createdDefault
        case recoveredFromCorruptFile(backup: URL)
    }

    public struct LoadResult: Equatable {
        public let configuration: AppConfiguration
        public let outcome: LoadOutcome
    }

    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> LoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return LoadResult(configuration: AppConfiguration(), outcome: .createdDefault)
        }
        let data = try Data(contentsOf: fileURL)
        let config: AppConfiguration
        do {
            config = try JSONDecoder().decode(AppConfiguration.self, from: data)
        } catch {
            let backup = backupURL()
            try fileManager.moveItem(at: fileURL, to: backup)
            return LoadResult(configuration: AppConfiguration(), outcome: .recoveredFromCorruptFile(backup: backup))
        }
        guard config.schemaVersion <= AppConfiguration.currentSchemaVersion else {
            throw ConfigStoreError.unsupportedSchemaVersion(config.schemaVersion)
        }
        return LoadResult(configuration: config, outcome: .loaded)
    }

    public func save(_ configuration: AppConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            // Atomic write: temporary file then rename, so a crash cannot leave a half-written config.
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ConfigStoreError.writeFailed(error.localizedDescription)
        }
    }

    private func backupURL() -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let name = "\(fileURL.deletingPathExtension().lastPathComponent).corrupt-\(stamp).json"
        return fileURL.deletingLastPathComponent().appendingPathComponent(name)
    }
}

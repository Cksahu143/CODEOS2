import Foundation

/// Creates a unique temporary directory and removes it after the test.
final class TempDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func file(_ name: String, contents: String = "") throws -> URL {
        let target = url.appendingPathComponent(name)
        try Data(contents.utf8).write(to: target)
        return target
    }
}

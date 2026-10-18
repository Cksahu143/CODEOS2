import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum DevServerParser {
    private static let pattern = try! NSRegularExpression(
        pattern: #"https?://(?:localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0):\d{2,5}[^\s'"]*"#)

    /// The first local address a dev server prints, such as http://localhost:5173/.
    public static func url(in text: String) -> URL? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              let found = Range(match.range, in: text) else { return nil }
        let raw = String(text[found]).replacingOccurrences(of: "0.0.0.0", with: "localhost")
        return URL(string: raw)
    }

    public static func looksLikePortInUse(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("eaddrinuse")
            || lower.contains("address already in use")
            || (lower.contains("port") && lower.contains("is in use"))
    }
}

/// Runs a dev server and keeps its output. Stop ends the server and everything it started.
public final class DevServerProcess {
    private var process: Process?
    private var running = false
    private var foundURL: URL?
    private var lines: [String] = []
    private let lock = NSLock()
    private static let maxLines = 400

    /// Called on a background thread whenever output or state changes.
    public var onChange: (() -> Void)?

    public init() {}

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    public var url: URL? {
        lock.lock(); defer { lock.unlock() }
        return foundURL
    }

    public var outputText: String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    public var portInUse: Bool {
        DevServerParser.looksLikePortInUse(outputText)
    }

    public func start(executable: String, arguments: [String], workingDirectory: String) throws {
        guard !isRunning else { return }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = arguments
        child.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            self?.append(String(decoding: data, as: UTF8.self))
        }
        child.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            self?.finish()
        }
        lock.lock()
        lines = []
        foundURL = nil
        running = true
        process = child
        lock.unlock()
        do {
            try child.run()
        } catch {
            lock.lock()
            running = false
            process = nil
            lock.unlock()
            throw error
        }
        onChange?()
    }

    /// Stops the server, its child processes, and anything else in its process tree.
    public func stop() {
        lock.lock()
        let root = process
        lock.unlock()
        guard let root, root.isRunning else { return }
        let rootPID = root.processIdentifier
        let victims = DevServerProcess.descendants(of: rootPID, table: DevServerProcess.processTable()) + [rootPID]
        for pid in victims {
            _ = kill(pid, SIGTERM)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
            for pid in victims where kill(pid, 0) == 0 {
                _ = kill(pid, SIGKILL)
            }
        }
    }

    private func append(_ text: String) {
        lock.lock()
        lines += text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count > DevServerProcess.maxLines {
            lines.removeFirst(lines.count - DevServerProcess.maxLines)
        }
        if foundURL == nil {
            foundURL = DevServerParser.url(in: lines.joined(separator: "\n"))
        }
        lock.unlock()
        onChange?()
    }

    private func finish() {
        lock.lock()
        running = false
        process = nil
        lock.unlock()
        onChange?()
    }

    public static func processTable() -> [(pid: Int32, ppid: Int32)] {
        guard let result = try? ProcessRunner.run(executable: "/bin/ps", arguments: ["-axo", "pid=,ppid="], timeout: 5),
              result.succeeded else { return [] }
        return parsePidTable(result.stdout)
    }

    public static func parsePidTable(_ text: String) -> [(pid: Int32, ppid: Int32)] {
        var table: [(pid: Int32, ppid: Int32)] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count == 2, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }
            table.append((pid: pid, ppid: ppid))
        }
        return table
    }

    /// Every process started, directly or indirectly, by `root`.
    public static func descendants(of root: Int32, table: [(pid: Int32, ppid: Int32)]) -> [Int32] {
        var result: [Int32] = []
        var queue: [Int32] = [root]
        while let parent = queue.popLast() {
            for entry in table where entry.ppid == parent && entry.pid != root && !result.contains(entry.pid) {
                result.append(entry.pid)
                queue.append(entry.pid)
            }
        }
        return result
    }
}

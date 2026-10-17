import Foundation

public enum ProcessRunError: Error, Equatable, LocalizedError {
    case executableNotFound(String)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let path): return "Command not found: \(path)"
        case .launchFailed(let reason): return "Could not start the command: \(reason)"
        }
    }
}

public struct ProcessResult: Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public var succeeded: Bool { exitCode == 0 && !timedOut }
}

/// Runs an executable with an explicit argument array. No shell is involved,
/// so arguments are never interpreted as shell syntax.
public enum ProcessRunner {
    public static func run(
        executable: String,
        arguments: [String],
        workingDirectory: String? = nil,
        timeout: TimeInterval = 10
    ) throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ProcessRunError.executableNotFound(executable)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        // Drain both pipes concurrently so a chatty process cannot deadlock on a full pipe buffer.
        var stdoutData = Data()
        var stderrData = Data()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }

        do {
            try process.run()
        } catch {
            throw ProcessRunError.launchFailed(error.localizedDescription)
        }

        let timedOut = exited.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            _ = exited.wait(timeout: .now() + 2)
        }
        readers.wait()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            timedOut: timedOut
        )
    }
}

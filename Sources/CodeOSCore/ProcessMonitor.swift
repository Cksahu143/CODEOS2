import Foundation

public struct ProcessSample: Identifiable, Equatable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let cpuPercent: Double
    public let residentBytes: UInt64
    public let command: String

    public var name: String { (command as NSString).lastPathComponent }
}

/// Reads per-process CPU and memory from `ps`, using an explicit argument list.
public enum ProcessMonitor {
    public static func sample(limit: Int = 20) throws -> [ProcessSample] {
        let result = try ProcessRunner.run(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,pcpu=,rss=,comm="],
            timeout: 5
        )
        guard result.succeeded else {
            throw ProcessRunError.launchFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parse(result.stdout, limit: limit)
    }

    /// Parses `ps -axo pid=,pcpu=,rss=,comm=`. `rss` is reported in kilobytes.
    public static func parse(_ output: String, limit: Int = 20) -> [ProcessSample] {
        var samples: [ProcessSample] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let kilobytes = UInt64(parts[2]) else { continue }
            samples.append(ProcessSample(pid: pid, cpuPercent: cpu, residentBytes: kilobytes * 1024, command: String(parts[3])))
        }
        let ranked = samples.sorted { lhs, rhs in
            if lhs.cpuPercent != rhs.cpuPercent { return lhs.cpuPercent > rhs.cpuPercent }
            return lhs.residentBytes > rhs.residentBytes
        }
        return Array(ranked.prefix(limit))
    }
}

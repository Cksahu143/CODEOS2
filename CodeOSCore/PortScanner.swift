import Foundation

public struct ListeningPort: Identifiable, Equatable {
    public var id: String { "\(address):\(port):\(pid)" }
    public let port: Int
    public let pid: Int32
    public let processName: String
    public let address: String
}

/// Lists TCP ports in the LISTEN state using lsof's machine-readable output.
public enum PortScanner {
    public static func listening() throws -> [ListeningPort] {
        let result = try ProcessRunner.run(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"],
            timeout: 8
        )
        // lsof exits with status 1 when nothing matches, so judge by output instead.
        return parse(result.stdout)
    }

    /// Parses lsof field output: `p` process id, `c` command, `n` name (address:port).
    public static func parse(_ output: String) -> [ListeningPort] {
        var results: [ListeningPort] = []
        var pid: Int32?
        var command = ""
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value)
                command = ""
            case "c":
                command = value
            case "n":
                guard let owner = pid,
                      let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]) else { continue }
                let address = String(value[..<colon])
                results.append(ListeningPort(port: port, pid: owner, processName: command, address: address))
            default:
                continue
            }
        }
        var seen = Set<String>()
        return results
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.port < $1.port }
    }
}

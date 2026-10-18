import Foundation

public struct USBDevice: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let manufacturer: String?
    public let serial: String?
    public let speed: String?
    /// 0 for a controller, 1 for a device on it, and so on down through hubs.
    public let depth: Int
    public let isHub: Bool
}

/// Lists connected USB devices and their hubs. Read-only: it does not eject or power devices.
public enum USBMonitor {
    public static func list() throws -> [USBDevice] {
        let result = try ProcessRunner.run(
            executable: "/usr/sbin/system_profiler",
            arguments: ["SPUSBDataType", "-json"],
            timeout: 30)
        guard result.succeeded else {
            throw ProcessRunError.launchFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parse(Data(result.stdout.utf8))
    }

    /// Parses `system_profiler SPUSBDataType -json`, walking the nested device tree in order.
    public static func parse(_ data: Data) -> [USBDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buses = root["SPUSBDataType"] as? [[String: Any]] else {
            return []
        }
        var devices: [USBDevice] = []
        var counter = 0
        func walk(_ items: [[String: Any]], depth: Int) {
            for item in items {
                counter += 1
                let name = (item["_name"] as? String) ?? "Unknown device"
                let children = (item["_items"] as? [[String: Any]]) ?? []
                devices.append(USBDevice(
                    id: "\(counter)-\(name)",
                    name: name,
                    manufacturer: item["manufacturer"] as? String,
                    serial: item["serial_num"] as? String,
                    speed: item["device_speed"] as? String,
                    depth: depth,
                    isHub: !children.isEmpty))
                walk(children, depth: depth + 1)
            }
        }
        walk(buses, depth: 0)
        return devices
    }
}

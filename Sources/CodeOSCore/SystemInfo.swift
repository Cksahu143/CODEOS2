import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct SystemSnapshot: Equatable {
    public let osVersion: String
    public let hardwareModel: String?
    public let machineArchitecture: String?
    public let cpuBrand: String?
    public let appArchitecture: String
    public let physicalMemoryBytes: UInt64
    public let volumePath: String
    public let volumeTotalBytes: Int64?
    public let volumeAvailableBytes: Int64?
}

/// Reads system facts from documented sources. Anything unavailable is returned as nil.
public enum SystemInfo {
    public static func snapshot(volumePath: String = "/") -> SystemSnapshot {
        let info = ProcessInfo.processInfo
        let values = try? URL(fileURLWithPath: volumePath).resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ])
        let total: Int64? = values?.volumeTotalCapacity.map { Int64($0) }
        let available: Int64? = values?.volumeAvailableCapacityForImportantUsage
        return SystemSnapshot(
            osVersion: info.operatingSystemVersionString,
            hardwareModel: sysctlString("hw.model"),
            machineArchitecture: sysctlString("hw.machine"),
            cpuBrand: sysctlString("machdep.cpu.brand_string"),
            appArchitecture: appArchitecture,
            physicalMemoryBytes: info.physicalMemory,
            volumePath: volumePath,
            volumeTotalBytes: total,
            volumeAvailableBytes: available
        )
    }

    /// The architecture this CodeOS binary was compiled for.
    public static var appArchitecture: String {
        #if arch(x86_64)
        return "x86_64"
        #elseif arch(arm64)
        return "arm64"
        #else
        return "unknown"
        #endif
    }

    public static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

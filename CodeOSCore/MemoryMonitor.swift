import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct MemoryBreakdown: Equatable {
    public let totalBytes: UInt64
    public let freeBytes: UInt64
    public let activeBytes: UInt64
    public let inactiveBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64

    /// Memory in use by apps and the system. Inactive and free memory are excluded.
    public var usedBytes: UInt64 { activeBytes + wiredBytes + compressedBytes }

    public var usageFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(usedBytes) / Double(totalBytes))
    }
}

/// Reads virtual memory statistics with the documented Mach host call.
public enum MemoryMonitor {
    public static func breakdown() -> MemoryBreakdown? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }

        let page = UInt64(sysconf(_SC_PAGESIZE))
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &total, &size, nil, 0) == 0 else { return nil }

        return MemoryBreakdown(
            totalBytes: total,
            freeBytes: UInt64(stats.free_count) * page,
            activeBytes: UInt64(stats.active_count) * page,
            inactiveBytes: UInt64(stats.inactive_count) * page,
            wiredBytes: UInt64(stats.wire_count) * page,
            compressedBytes: UInt64(stats.compressor_page_count) * page
        )
    }
}

import Foundation
import IOKit

public struct TemperatureReading: Equatable {
    public let name: String
    public let celsius: Double

}

public struct FanReading: Equatable {
    public let name: String
    public let rpm: Int
    public let minRPM: Int?
    public let maxRPM: Int?
    /// 0 = automatic (macOS controls the fan), 1 = manual. Read-only.
    public var mode: Int? = nil
    /// The speed the controller is aiming for, in RPM. Read-only.
    public var target: Int? = nil
}

public struct ThermalSnapshot: Equatable {
    public let sensorsAvailable: Bool
    public let temperatures: [TemperatureReading]
    public let fans: [FanReading]
    public let note: String?
}

/// Read-only temperatures and fan speeds from the Intel SMC (System Management Controller).
/// It never writes to the SMC. The key names are the publicly documented ones used by open-source
/// fan and sensor tools. Apple Silicon Macs use a different interface, so there nothing is read.
public enum ThermalMonitor {
    static let temperatureKeys: [(String, String)] = [
        ("CPU proximity", "TC0P"),
        ("CPU die", "TC0D"),
        ("GPU proximity", "TG0P"),
    ]

    public static func read() -> ThermalSnapshot {
        guard let smc = SMC() else {
            return ThermalSnapshot(
                sensorsAvailable: false, temperatures: [], fans: [],
                note: "This Mac's sensor interface (AppleSMC) is not available.")
        }

        let temperatures: [TemperatureReading] = temperatureKeys.compactMap { entry -> TemperatureReading? in
            let (name, key) = entry
            guard let value = smc.value(key), value > 0, value < 150 else { return nil }
            return TemperatureReading(name: name, celsius: value)
        }
        var fans: [FanReading] = []
        if let countValue = smc.value("FNum") {
            let count = max(0, min(Int(countValue), 8))
            for index in 0..<count {
                guard let rpm = smc.value("F\(index)Ac") else { continue }
                fans.append(FanReading(
                    name: "Fan \(index + 1)",
                    rpm: Int(rpm),
                    minRPM: smc.value("F\(index)Mn").map { Int($0) },
                    maxRPM: smc.value("F\(index)Mx").map { Int($0) },
                    mode: smc.value("F\(index)Md").map { Int($0) },
                    target: smc.value("F\(index)Tg").map { Int($0) }))
            }
        }
        let note: String? = (temperatures.isEmpty && fans.isEmpty)
            ? "No temperature or fan sensors were read. This Mac may use a sensor layout CodeOS doesn't support yet."
            : nil
        return ThermalSnapshot(sensorsAvailable: true, temperatures: temperatures, fans: fans, note: note)
    }
}

/// Raw SMC access. The struct is 80 bytes; offsets below match the kernel's layout.
final class SMC {
    private var connection: io_connect_t = 0
    private static let structSize = 80
    private static let kernelIndexSMC: UInt32 = 2
    private static let commandReadKeyInfo: UInt8 = 9
    private static let commandReadBytes: UInt8 = 5


    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    /// Reads one key and decodes it. Returns nil when the key is missing or unsupported.
    func value(_ key: String) -> Double? {
        guard let result = read(key) else { return nil }
        return SMC.decode(type: result.0, bytes: result.1)
    }

    private func read(_ key: String) -> (String, [UInt8])? {
        guard key.utf8.count == 4 else { return nil }
        let code = SMC.fourCC(key)

        var request = [UInt8](repeating: 0, count: SMC.structSize)
        SMC.put32(&request, 0, code)
        request[42] = SMC.commandReadKeyInfo
        guard let info = call(request), info[40] == 0 else { return nil }
        let size = SMC.get32(info, 28)
        let type = SMC.fourCCString(SMC.get32(info, 32))
        guard size > 0, size <= 32 else { return nil }

        var request2 = [UInt8](repeating: 0, count: SMC.structSize)
        SMC.put32(&request2, 0, code)
        SMC.put32(&request2, 28, size)

        request2[42] = SMC.commandReadBytes
        guard let data = call(request2), data[40] == 0 else { return nil }
        return (type, Array(data[48..<(48 + Int(size))]))
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: SMC.structSize)
        var outputSize = SMC.structSize
        let result = input.withUnsafeBytes { inBuffer in
            output.withUnsafeMutableBytes { outBuffer in
                IOConnectCallStructMethod(connection, SMC.kernelIndexSMC,
                                          inBuffer.baseAddress, SMC.structSize,
                                          outBuffer.baseAddress, &outputSize)
            }
        }
        return result == KERN_SUCCESS ? output : nil
    }

    /// Decodes the value formats the Intel SMC uses for temperatures, fans, and counts.
    static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: raw))

        case "ui8 ":
            return bytes.first.map { Double($0) }
        default:
            return nil
        }
    }

    static func fourCC(_ text: String) -> UInt32 {
        text.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    static func fourCCString(_ code: UInt32) -> String {
        String(bytes: [UInt8(code >> 24 & 0xff), UInt8(code >> 16 & 0xff),
                       UInt8(code >> 8 & 0xff), UInt8(code & 0xff)], encoding: .ascii) ?? ""
    }

    /// The kernel reads these fields in native (little-endian on Intel and Apple Silicon) order.
    static func put32(_ buffer: inout [UInt8], _ offset: Int, _ value: UInt32) {
        buffer[offset] = UInt8(value & 0xff)
        buffer[offset + 1] = UInt8(value >> 8 & 0xff)
        buffer[offset + 2] = UInt8(value >> 16 & 0xff)
        buffer[offset + 3] = UInt8(value >> 24 & 0xff)
    }

    static func get32(_ buffer: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(buffer[offset]) | UInt32(buffer[offset + 1]) << 8
            | UInt32(buffer[offset + 2]) << 16 | UInt32(buffer[offset + 3]) << 24
    }
}

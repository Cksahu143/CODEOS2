import Foundation

public enum FanControlError: Error, LocalizedError, Equatable {
    case sensorsUnavailable
    case unknownFan(Int)
    case outOfRange(min: Int, max: Int)
    case writeRejected(String)
    case verificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sensorsUnavailable:
            return "This Mac's fan interface (AppleSMC) is not available."
        case .unknownFan(let index):
            return "Fan \(index + 1) was not found."
        case .outOfRange(let min, let max):
            return "The speed must be between \(min) and \(max) RPM, the range this fan supports."
        case .writeRejected(let reason):
            return "The change was not made: \(reason)."
        case .verificationFailed(let reason):
            return "The change could not be confirmed: \(reason)."
        }
    }
}

/// Changes fan speed through the SMC. Only the privileged helper (which runs as root) calls this.
/// Every change is read back. If the SMC does not confirm it, the fan goes back to automatic.
public enum FanController {
    /// Sets one fan to a fixed speed. Refuses any speed outside the fan's hardware range.
    public static func setManual(fan: Int, rpm: Int) throws {
        guard let smc = SMC() else { throw FanControlError.sensorsUnavailable }
        guard let minValue = smc.value("F\(fan)Mn"), let maxValue = smc.value("F\(fan)Mx") else {
            throw FanControlError.unknownFan(fan)
        }
        let low = Int(minValue.rounded(.up))
        let high = Int(maxValue.rounded(.down))
        guard rpm >= low, rpm <= high else { throw FanControlError.outOfRange(min: low, max: high) }

        let modeKey = "F\(fan)Md"
        let targetKey = "F\(fan)Tg"
        guard smc.writeUInt8(modeKey, 1) else {
            _ = smc.writeUInt8(modeKey, 0)
            throw FanControlError.writeRejected("the SMC refused manual mode (\(smc.describe(modeKey)))")
        }
        guard smc.writeRPM(targetKey, rpm) else {
            _ = smc.writeUInt8(modeKey, 0)
            throw FanControlError.writeRejected("the SMC refused \(rpm) RPM (\(smc.describe(targetKey)))")
        }
        guard smc.value(modeKey) == 1, let target = smc.value(targetKey), abs(target - Double(rpm)) < 50 else {
            _ = smc.writeUInt8(modeKey, 0)
            throw FanControlError.verificationFailed("the SMC did not confirm the speed, so the fan was returned to automatic")
        }
    }

    /// Returns every fan to automatic control and confirms it.
    public static func restoreAutomatic() throws {
        guard let smc = SMC() else { throw FanControlError.sensorsUnavailable }
        let count = max(0, min(Int(smc.value("FNum") ?? 0), 8))
        for fan in 0..<count {
            guard smc.writeUInt8("F\(fan)Md", 0), smc.value("F\(fan)Md") == 0 else {
                throw FanControlError.verificationFailed("fan \(fan + 1) did not return to automatic")
            }
        }
    }

    /// A read-only report of the keys a fan change uses. Writes nothing.
    public static func inspect(fan: Int) -> String {
        guard let smc = SMC() else { return "AppleSMC is not available." }
        var lines: [String] = []
        for key in ["F\(fan)Md", "F\(fan)Tg", "F\(fan)Mn", "F\(fan)Mx", "F\(fan)Ac"] {
            let value = smc.value(key).map { String($0) } ?? "unreadable"
            lines.append(smc.describe(key) + ", value " + value)
        }
        return lines.joined(separator: "\n")
    }
}

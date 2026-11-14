import Foundation

public enum PowerModeParser {
    /// Reads the lowpowermode line from `pmset -g` output. Nil when the Mac does not report it.
    public static func lowPowerMode(fromPmsetOutput output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, parts[0] == "lowpowermode" else { continue }
            switch parts[1] {
            case "1": return true
            case "0": return false
            default: return nil
            }
        }
        return nil
    }
}

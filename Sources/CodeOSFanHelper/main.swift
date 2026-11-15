import CodeOSCore
import Foundation

// Runs as root, started by the app through macOS's administrator prompt. It accepts only:
//   codeos-fanctl set <fan-index> <rpm>
//   codeos-fanctl auto
//   codeos-fanctl inspect <fan-index>      (read-only)
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "set":
    guard arguments.count == 3,
          let fan = Int(arguments[1]), fan >= 0, fan < 8,
          let rpm = Int(arguments[2]), rpm > 0 else {
        fail("usage: codeos-fanctl set <fan-index> <rpm>")
    }
    do {
        try FanController.setManual(fan: fan, rpm: rpm)
        print("ok")
    } catch {
        fail(error.localizedDescription)
    }
case "auto":
    do {
        try FanController.restoreAutomatic()
        print("ok")
    } catch {
        fail(error.localizedDescription)
    }
case "inspect":
    guard arguments.count == 2, let fan = Int(arguments[1]), fan >= 0, fan < 8 else {
        fail("usage: codeos-fanctl inspect <fan-index>")
    }
    print(FanController.inspect(fan: fan))
default:
    fail("usage: codeos-fanctl set <fan-index> <rpm> | auto | inspect <fan-index>")
}

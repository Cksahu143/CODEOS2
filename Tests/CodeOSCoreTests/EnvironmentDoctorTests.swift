import XCTest
@testable import CodeOSCore

/// A fake machine. Anything not listed does not exist or does not run.
struct FakeProbe: EnvironmentProbe {
    var existing: Set<String> = []
    var versions: [String: String] = [:]
    var path: [String] = []
    var clt: String? = "/Library/Developer/CommandLineTools"
    var sdk: String? = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"

    func exists(_ path: String) -> Bool { existing.contains(path) }
    func isExecutable(_ path: String) -> Bool { existing.contains(path) }
    func version(of executable: String, arguments: [String]) -> String? { versions[executable] }
    func pathEntries() -> [String] { path }
    func environmentValue(_ name: String) -> String? { name == "SHELL" ? "/bin/zsh" : nil }
    func commandLineToolsPath() -> String? { clt }
    func sdkPath() -> String? { sdk }
}

final class EnvironmentDoctorTests: XCTestCase {
    private let healthy = FakeProbe(
        existing: ["/opt/local/bin/git", "/opt/local/bin", "/usr/bin", "/Library/Developer/CommandLineTools",\n                   "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
                   "/opt/homebrew/bin/node", "/opt/local/bin/port"],
        versions: ["/opt/local/bin/git": "git version 2.45.0",
                   "/Library/Frameworks/Python.framework/Versions/Current/bin/python3": "Python 3.12.3",
                   "/opt/homebrew/bin/node": "v22.1.0"],
        path: ["/opt/local/bin", "/usr/bin"])

    private func severities(_ findings: [DoctorFinding]) -> [FindingSeverity] {
        findings.map(\.severity)
    }

    func testHealthyMachineHasNoErrorsOrWarnings() {
        let findings = EnvironmentDoctor.diagnose(healthy)
        XCTAssertFalse(severities(findings).contains(.error))
        XCTAssertFalse(severities(findings).contains(.warning))
        XCTAssertTrue(findings.contains { $0.title == "Git works" })
    }

    func testMissingCommandLineToolsIsAnError() {
        var probe = healthy
        probe.clt = nil
        let findings = EnvironmentDoctor.diagnose(probe)
        XCTAssertTrue(findings.contains { $0.severity == .error && $0.title.contains("Command Line Tools") })
    }

    func testDamagedCommandLineToolsIsAnError() {
        var probe = healthy
        probe.sdk = nil
        let findings = EnvironmentDoctor.diagnose(probe)
        XCTAssertTrue(findings.contains { $0.title == "Command Line Tools are damaged" })
    }

    func testNoWorkingGitIsAnError() {
        var probe = healthy
        probe.existing.remove("/opt/local/bin/git")
        probe.versions["/opt/local/bin/git"] = nil
        let findings = EnvironmentDoctor.diagnose(probe)
        XCTAssertTrue(findings.contains { $0.title == "No working Git" })
    }

    func testPythonStubIsNotCountedAsPython() {
        var probe = healthy
        probe.existing = probe.existing.subtracting(["/Library/Frameworks/Python.framework/Versions/Current/bin/python3"])
        probe.existing.insert("/usr/bin/python3")
        let findings = EnvironmentDoctor.diagnose(probe)
        XCTAssertTrue(findings.contains { $0.title == "No Python 3.8 or newer outside macOS's stub" })
        XCTAssertTrue(findings.contains { $0.title == "/usr/bin/python3 is a stub" })
    }

    func testMissingPathFoldersAreWarned() {
        var probe = healthy
        probe.path = ["/opt/local/bin", "/nonexistent/one", "/nonexistent/two"]
        let findings = EnvironmentDoctor.diagnose(probe)
        XCTAssertTrue(findings.contains { $0.severity == .warning && $0.title.hasPrefix("2 PATH") })
    }

    func testHomebrewAndMacPortsTogetherAreWarned() {
        var probe = healthy
        probe.existing.insert("/opt/homebrew/bin/brew")
        let findings = EnvironmentDoctor.diagnose(probe)
        XCTAssertTrue(findings.contains { $0.title == "Homebrew and MacPorts are both installed" })
    }

    func testFindingsAreSortedWorstFirst() {
        var probe = healthy
        probe.clt = nil
        let findings = EnvironmentDoctor.diagnose(probe)
        XCTAssertEqual(findings.first?.severity, .error)
    }

    func testPythonVersionParsing() {
        XCTAssertEqual(EnvironmentDoctor.pythonMinor("Python 3.12.3"), 12)
        XCTAssertNil(EnvironmentDoctor.pythonMinor("Python 2.7.18"))
        XCTAssertNil(EnvironmentDoctor.pythonMinor("not python"))
    }
}

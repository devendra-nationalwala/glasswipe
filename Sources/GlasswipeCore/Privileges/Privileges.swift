import AppKit
import Foundation

/// Runs a command-line tool and captures its output.
public enum Shell {
    public struct Result: Sendable {
        public let status: Int32
        public let stdout: String
        public let stderr: String
    }

    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 600) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        // Read while running so large outputs cannot fill the pipe and block the tool.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        let collector = DataCollector()
        group.enter()
        DispatchQueue.global().async { collector.setOut(out.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        group.enter()
        DispatchQueue.global().async { collector.setErr(err.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        group.wait()
        outData = collector.out
        errData = collector.err
        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    /// Single-quotes a string for /bin/sh.
    public static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

private final class DataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _out = Data(), _err = Data()
    var out: Data { lock.withLock { _out } }
    var err: Data { lock.withLock { _err } }
    func setOut(_ d: Data) { lock.withLock { _out = d } }
    func setErr(_ d: Data) { lock.withLock { _err = d } }
}

/// Runs one shell command with administrator privileges via the standard macOS password prompt.
/// v1 has no privileged helper; this asks once per Cleanup.
public enum AdminRunner {
    public static func run(command: String) throws {
        let script = "do shell script \(appleScriptString(command)) with administrator privileges"
        let result = try Shell.run("/usr/bin/osascript", ["-e", script])
        guard result.status == 0 else {
            throw CleanupError.commandFailed(result.stderr.contains("-128") ? "Cancelled" : result.stderr)
        }
    }

    static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Full Disk Access cannot be queried; it is inferred by reading a protected location.
public enum FullDiskAccess {
    public static func isGranted(home: String = NSHomeDirectory()) -> Bool {
        let probes = [
            home + "/Library/Safari",
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Containers/com.apple.stocks",
            home + "/.Trash",
        ]
        for probe in probes where FileManager.default.fileExists(atPath: probe) {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: probe, isDirectory: &isDir)
            if isDir.boolValue {
                if (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil { return true }
            } else if FileManager.default.isReadableFile(atPath: probe), let handle = FileHandle(forReadingAtPath: probe) {
                try? handle.close()
                return true
            }
        }
        return false
    }

    @MainActor
    public static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}

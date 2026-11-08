import AppKit
import Foundation

/// Facts about the machine a Scan needs. Injected so tests can fake them.
public struct ScanEnvironment: Sendable {
    public var home: String
    public var tmpDir: String
    public var runningBundleIDs: Set<String>
    public var runningProcessNames: Set<String>
    public var toolSearchPaths: [String]
    public var now: Date

    public init(
        home: String,
        tmpDir: String,
        runningBundleIDs: Set<String> = [],
        runningProcessNames: Set<String> = [],
        toolSearchPaths: [String] = [],
        now: Date = Date()
    ) {
        self.home = home
        self.tmpDir = tmpDir
        self.runningBundleIDs = runningBundleIDs
        self.runningProcessNames = runningProcessNames
        self.toolSearchPaths = toolSearchPaths
        self.now = now
    }

    /// The real machine.
    @MainActor
    public static func current() -> ScanEnvironment {
        let home = NSHomeDirectory()
        let bundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let names = Set(ProcessList.all().map { $0.name.lowercased() })
        return ScanEnvironment(
            home: home,
            tmpDir: (NSTemporaryDirectory() as NSString).standardizingPath,
            runningBundleIDs: bundleIDs,
            runningProcessNames: names,
            toolSearchPaths: [
                "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                home + "/.local/bin", home + "/.cargo/bin", home + "/.bun/bin", home + "/go/bin",
                "/usr/local/go/bin", home + "/.volta/bin", "/Applications/Docker.app/Contents/Resources/bin",
            ],
            now: Date()
        )
    }

    public func expand(_ pattern: String) -> String {
        var p = pattern
        if p.hasPrefix("~") { p = home + p.dropFirst() }
        p = p.replacingOccurrences(of: "$TMPDIR", with: tmpDir)
        return p
    }

    /// Absolute path of an installed tool, if any.
    public func locateTool(_ name: String) -> String? {
        for dir in toolSearchPaths {
            let path = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        // nvm installs node tools per version.
        let nvm = home + "/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm).sorted().reversed() {
            for v in versions {
                let path = "\(nvm)/\(v)/bin/\(name)"
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
        }
        return nil
    }
}

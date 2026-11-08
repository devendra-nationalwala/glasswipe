import Foundation

/// A launch agent or daemon that starts automatically.
public struct StartupItem: Identifiable, Sendable, Hashable {
    public enum Scope: String, Sendable, CaseIterable {
        case user = "Your account"
        case allUsers = "All users"
        case system = "System daemon"

        var domain: String { self == .system ? "system" : "gui/\(getuid())" }
        public var needsAdmin: Bool { self != .user }
    }

    public var id: String { plist.path }
    public let label: String
    public let plist: URL
    public let scope: Scope
    public let program: String?
    public let runAtLoad: Bool
    public let keepAlive: Bool
    public let isEnabled: Bool
    public let isLoaded: Bool
    public init(label: String, plist: URL, scope: Scope, program: String?, runAtLoad: Bool, keepAlive: Bool,
                isEnabled: Bool, isLoaded: Bool) {
        self.label = label
        self.plist = plist
        self.scope = scope
        self.program = program
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.isEnabled = isEnabled
        self.isLoaded = isLoaded
    }

    /// The program it launches no longer exists.
    public var isBroken: Bool { program.map { !FileManager.default.fileExists(atPath: $0) } ?? false }
}

public enum StartupItems {
    static func directories(home: String) -> [(String, StartupItem.Scope)] {
        [(home + "/Library/LaunchAgents", .user), ("/Library/LaunchAgents", .allUsers), ("/Library/LaunchDaemons", .system)]
    }

    public static func scan(home: String = NSHomeDirectory()) -> [StartupItem] {
        let userDisabled = disabledLabels(domain: "gui/\(getuid())")
        let systemDisabled = disabledLabels(domain: "system")
        let loaded = loadedLabels()
        var items: [StartupItem] = []
        for (dir, scope) in directories(home: home) {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".plist") {
                let url = URL(fileURLWithPath: dir + "/" + name)
                guard let data = try? Data(contentsOf: url),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                else { continue }
                let label = plist["Label"] as? String ?? String(name.dropLast(6))
                let program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
                let disabledInPlist = plist["Disabled"] as? Bool ?? false
                let overrides = scope == .system ? systemDisabled : userDisabled
                let enabled = overrides[label].map { !$0 } ?? !disabledInPlist
                items.append(StartupItem(
                    label: label, plist: url, scope: scope, program: program,
                    runAtLoad: plist["RunAtLoad"] as? Bool ?? false,
                    keepAlive: (plist["KeepAlive"] as? Bool) ?? (plist["KeepAlive"] != nil),
                    isEnabled: enabled,
                    isLoaded: scope == .user ? loaded.contains(label) : enabled
                ))
            }
        }
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Parses `launchctl print-disabled <domain>`: label => true when disabled.
    static func disabledLabels(domain: String) -> [String: Bool] {
        guard let out = try? Shell.run("/bin/launchctl", ["print-disabled", domain]).stdout else { return [:] }
        return parseDisabled(out)
    }

    static func parseDisabled(_ text: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=>").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            result[label] = parts[1].hasPrefix("disabled") || parts[1].hasPrefix("true")
        }
        return result
    }

    static func loadedLabels() -> Set<String> {
        guard let out = try? Shell.run("/bin/launchctl", ["list"]).stdout else { return [] }
        return Set(out.split(separator: "\n").dropFirst().compactMap { $0.split(separator: "\t").last.map(String.init) })
    }

    /// Enables or disables an item persistently. System-wide items ask for the admin password.
    public static func setEnabled(_ enabled: Bool, for item: StartupItem) throws {
        let target = "\(item.scope.domain)/\(item.label)"
        let commands: [[String]] = enabled
            ? [["enable", target], ["bootstrap", item.scope.domain, item.plist.path]]
            : [["bootout", target], ["disable", target]]
        if item.scope.needsAdmin {
            let script = commands.map { (["/bin/launchctl"] + $0).map(Shell.quote).joined(separator: " ") + " || true" }
                .joined(separator: "; ")
            try AdminRunner.run(command: script)
        } else {
            for args in commands { _ = try Shell.run("/bin/launchctl", args) }
        }
    }

    /// Unloads the item and moves its plist to the Trash.
    public static func remove(_ item: StartupItem) throws {
        let target = "\(item.scope.domain)/\(item.label)"
        if item.scope.needsAdmin {
            try AdminRunner.run(command: "/bin/launchctl bootout \(Shell.quote(target)) || true; /bin/mv \(Shell.quote(item.plist.path)) \(Shell.quote(NSHomeDirectory() + "/.Trash/"))")
        } else {
            _ = try? Shell.run("/bin/launchctl", ["bootout", target])
            try FileManager.default.trashItem(at: item.plist, resultingItemURL: nil)
        }
    }
}

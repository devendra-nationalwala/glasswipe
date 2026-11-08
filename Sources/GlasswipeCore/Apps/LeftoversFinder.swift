import AppKit
import Foundation

/// Finds App Footprints whose app is no longer installed.
public struct LeftoversFinder: Sendable {
    public let home: String
    /// Returns true if some installed app owns this bundle ID.
    public let isInstalled: @Sendable (String) -> Bool

    public init(home: String = NSHomeDirectory(), isInstalled: @escaping @Sendable (String) -> Bool) {
        self.home = home
        self.isInstalled = isInstalled
    }

    /// Uses the inventory plus LaunchServices, which also knows apps outside /Applications.
    public static func live(installed: [InstalledApp]) -> LeftoversFinder {
        let ids = Set(installed.flatMap(\.allBundleIDs).map { $0.lowercased() })
        let groups = Set(installed.flatMap(\.appGroups).map { $0.lowercased() })
        let teams = Set(installed.compactMap(\.teamID))
        let vendors = Set(installed.flatMap(\.allBundleIDs).compactMap(LeftoversFinder.vendor))
        let running = Set(ProcessList.all().map(\.path))
        return LeftoversFinder { id in
            let lower = id.lowercased()
            if ids.contains(lower) || groups.contains(lower) { return true }
            // A helper or sub-identifier of an installed app (com.vendor.App.helper).
            if ids.contains(where: { lower.hasPrefix($0 + ".") || $0.hasPrefix(lower + ".") }) { return true }
            // Group containers named <TeamID>.<suffix> belong to that team's installed apps.
            if let team = id.split(separator: ".").first, teams.contains(String(team)) { return true }
            // Anything from a vendor that still has an app installed is kept (shared frameworks, updaters, suites).
            if let vendor = LeftoversFinder.vendor(of: id), vendors.contains(vendor) { return true }
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil { return true }
            // Command-line tools and agents that are running right now.
            if running.contains(where: { $0.lowercased().contains(lower) }) { return true }
            return false
        }
    }

    static let locations: [(String, String)] = [
        ("Library/Application Support", "Support files"),
        ("Library/Caches", "Cache"),
        ("Library/Preferences", "Preferences"),
        ("Library/Containers", "Container"),
        ("Library/Group Containers", "Shared container"),
        ("Library/Saved Application State", "Saved state"),
        ("Library/HTTPStorages", "Web data"),
        ("Library/WebKit", "Web data"),
        ("Library/Application Scripts", "Scripts"),
        ("Library/LaunchAgents", "Startup Item"),
        ("Library/Logs", "Logs"),
    ]

    /// First label of a reverse-DNS identifier must look like a domain suffix (or a Team ID), so log files
    /// such as `warp.log.old.0` are not mistaken for identifiers.
    static let domainSuffixes: Set<String> = [
        "com", "org", "net", "io", "ai", "app", "dev", "co", "me", "tv", "us", "ca", "uk", "de", "fr", "jp", "cn", "ru",
        "nl", "se", "no", "fi", "dk", "ch", "at", "be", "es", "it", "pl", "au", "nz", "in", "br", "kr", "il", "sh", "so",
        "xyz", "info", "biz", "edu", "gov", "cc", "is", "ly", "to", "fm", "gg", "video", "studio", "tech", "cloud",
        "design", "software", "systems", "group", "homebrew", "eu", "re", "lu", "pt", "cz", "hu", "ro", "tw", "hk", "sg",
    ]

    /// `com.vendor` from `com.vendor.App` (ignoring a leading `group.`); nil for Team-ID-prefixed groups.
    public static func vendor(of id: String) -> String? {
        var labels = id.lowercased().split(separator: ".").map(String.init)
        if labels.first == "group" { labels.removeFirst() }
        guard labels.count >= 2, domainSuffixes.contains(labels[0]) else { return nil }
        return labels[0] + "." + labels[1]
    }

    static func isTeamID(_ s: Substring) -> Bool {
        s.count == 10 && s.allSatisfy { $0.isUppercase || $0.isNumber }
    }

    /// Reverse-DNS identifier (three or more labels), or a Team-ID-prefixed group container.
    static func identifier(from name: String) -> String? {
        var base = name
        for suffix in [".plist", ".savedState", ".binarycookies"] where base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        let labels = base.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 3, labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } })
        else { return nil }
        if UUID(uuidString: base) != nil { return nil }
        guard domainSuffixes.contains(labels[0].lowercased()) || isTeamID(labels[0]) else { return nil }
        if base.lowercased().contains(".log") { return nil }
        return base
    }

    static func isApple(_ id: String) -> Bool {
        let lower = id.lowercased()
        if lower.contains("com.apple") { return true }
        // Apple services that use other prefixes, and system components that are not apps.
        let systemPrefixes = ["apple.", "systemgroup.", "group.is.workflow", "is.workflow", "group.tvappservices",
                              "org.cups.", "org.swift.", "com.openssh.", "org.python.", "org.openssh."]
        // Apple's own group containers use Apple team IDs.
        let appleTeams = ["2bul2wpyrq.", "k36bkf7t3d.", "8w2fzd3e4m.", "hu6vw6l64w.", "243lu875e5."]
        return systemPrefixes.contains { lower.hasPrefix($0) } || appleTeams.contains { lower.hasPrefix($0) }
    }

    public static let category = "Leftovers"

    static func launchAgentIsBroken(_ plist: URL) -> Bool {
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let program = dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first
        else { return false }
        return !FileManager.default.fileExists(atPath: program)
    }

    public func scan() -> [ScanItem] {
        var items: [ScanItem] = []
        for (relative, kind) in Self.locations {
            let dir = home + "/" + relative
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for name in names {
                guard let id = Self.identifier(from: name), !Self.isApple(id), !isInstalled(id) else { continue }
                let url = URL(fileURLWithPath: dir + "/" + name)
                // A launch agent whose program still exists is a working Startup Item (often a command-line tool).
                if relative == "Library/LaunchAgents", !Self.launchAgentIsBroken(url) { continue }
                let size = FileSize.allocatedSize(of: url)
                items.append(ScanItem(
                    url: url,
                    title: name,
                    category: id,
                    tier: .caution,
                    method: .trash,
                    size: size,
                    note: kind,
                    modified: FileSize.modificationDate(of: url)
                ))
            }
        }
        return items.sorted { $0.size > $1.size }
    }
}

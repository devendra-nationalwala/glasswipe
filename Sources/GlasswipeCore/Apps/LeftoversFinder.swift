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
        let running = Set(ProcessList.all().map(\.path))
        return LeftoversFinder { id in
            let lower = id.lowercased()
            if ids.contains(lower) || groups.contains(lower) { return true }
            // A helper or sub-identifier of an installed app (com.vendor.App.helper).
            if ids.contains(where: { lower.hasPrefix($0 + ".") || $0.hasPrefix(lower + ".") }) { return true }
            // Group containers named <TeamID>.<suffix> belong to that team's installed apps.
            if let team = id.split(separator: ".").first, teams.contains(String(team)) { return true }
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
        return base
    }

    static func isApple(_ id: String) -> Bool {
        let lower = id.lowercased()
        let applePrefixes = ["com.apple.", "group.com.apple.", "systemgroup.com.apple.", "apple.", "com.apple"]
        // Apple's own group containers use Apple team IDs.
        let appleTeams = ["2bul2wpyrq.", "k36bkf7t3d.", "8w2fzd3e4m.", "hu6vw6l64w."]
        return applePrefixes.contains { lower.hasPrefix($0) } || appleTeams.contains { lower.hasPrefix($0) }
    }

    public static let category = "Leftovers"

    public func scan() -> [ScanItem] {
        var items: [ScanItem] = []
        for (relative, kind) in Self.locations {
            let dir = home + "/" + relative
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for name in names {
                guard let id = Self.identifier(from: name), !Self.isApple(id), !isInstalled(id) else { continue }
                let url = URL(fileURLWithPath: dir + "/" + name)
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

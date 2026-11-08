import AppKit
import GlasswipeCore

/// `--demo` fills every screen with sample data, so screenshots show nothing from the real machine.
/// Nothing in demo mode can be removed: the sample paths live in a temporary folder.
@MainActor
enum Demo {
    static let isOn = CommandLine.arguments.contains("--demo")

    static let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("GlasswipeDemo")

    /// Names (comma-separated, case-insensitive) to keep out of public screenshots, from `GLASSWIPE_DEMO_HIDE`.
    static let hidden: [String] = (ProcessInfo.processInfo.environment["GLASSWIPE_DEMO_HIDE"] ?? "")
        .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }

    static func hides(_ name: String) -> Bool {
        isOn && hidden.contains { name.lowercased().contains($0) }
    }

    private static func url(_ name: String, file: Bool = false) -> URL {
        let url = root.appendingPathComponent(name)
        if file {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        } else {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private static let GB: Int64 = 1_073_741_824
    private static let MB: Int64 = 1_048_576

    private static func item(_ title: String, _ category: String, _ size: Int64, tier: Tier = .safe,
                             method: RemovalMethod = .delete, note: String? = nil, inUse: String? = nil,
                             file: String? = nil) -> ScanItem {
        ScanItem(url: url(file ?? title.replacingOccurrences(of: "/", with: "-"), file: file != nil), title: title,
                 category: category, tier: tier, method: method, size: size, note: note, inUseBy: inUse,
                 contentsOnly: file == nil && method == .delete)
    }

    static var storage: [ScanItem] {
        [
            item("Google Chrome cache", "Browser Caches", 2 * GB + 310 * MB, note: "Only while Chrome is closed", inUse: "com.google.Chrome"),
            item("Safari cache", "Browser Caches", 640 * MB),
            item("Firefox cache", "Browser Caches", 410 * MB),
            item("Spotify", "System Junk", 1 * GB + 820 * MB, note: "Apps recreate their caches as needed."),
            item("Slack", "System Junk", 940 * MB, note: "Apps recreate their caches as needed."),
            item("Microsoft Teams", "System Junk", 720 * MB, note: "Apps recreate their caches as needed."),
            item("Figma", "System Junk", 515 * MB, note: "Apps recreate their caches as needed."),
            item("App logs", "System Junk", 212 * MB),
            item("Crash reports older than 30 days", "System Junk", 96 * MB),
            item("Temporary files older than 3 days", "System Junk", 1 * GB + 120 * MB, tier: .caution,
                 note: "Running apps keep files here; only old items are offered."),
            item("Trash", "System Junk", 3 * GB + 400 * MB, tier: .caution, note: "Emptying the Trash cannot be undone."),
            item("models--whisper-large-v3", "Large Downloads", 2 * GB + 900 * MB, tier: .caution, method: .trash,
                 note: "Can be downloaded again, but they are large and slow to fetch."),
        ]
    }

    static var developer: [ScanItem] {
        [
            item("Xcode DerivedData", "Developer Junk", 18 * GB + 400 * MB, note: "Rebuilt on the next build."),
            item("Homebrew downloads and old versions", "Developer Junk", 3 * GB + 200 * MB,
                 method: .toolCommand(executable: "/opt/homebrew/bin/brew", arguments: ["cleanup", "--prune=all"])),
            item("npm cache", "Developer Junk", 4 * GB + 300 * MB,
                 method: .toolCommand(executable: "/opt/homebrew/bin/npm", arguments: ["cache", "clean", "--force"])),
            item("pip cache", "Developer Junk", 1 * GB + 700 * MB,
                 method: .toolCommand(executable: "/usr/bin/pip3", arguments: ["cache", "purge"])),
            item("~/Projects/website", "Developer Junk", 1 * GB + 150 * MB, note: "node_modules · restored by npm install"),
            item("~/Projects/dashboard", "Developer Junk", 870 * MB, note: "node_modules · restored by npm install"),
            item("~/Projects/mobile-app", "Developer Junk", 640 * MB, note: "node_modules · restored by npm install"),
            item("Simulator caches", "Developer Junk", 2 * GB + 100 * MB),
            item("Test browser downloads", "Developer Junk", 1 * GB + 600 * MB, note: "Downloaded again on the next test run."),
            item("Docker images and build cache", "Developer Junk", 12 * GB, tier: .caution,
                 method: .toolCommand(executable: "/usr/local/bin/docker", arguments: ["system", "prune", "--all", "--force"]),
                 note: "Removes unused images and build cache; volumes are kept."),
            item("Xcode archives", "Developer Junk", 6 * GB + 200 * MB, tier: .caution, method: .trash,
                 note: "Archives hold the dSYMs needed to symbolicate shipped builds."),
        ]
    }

    static var leftovers: [ScanItem] {
        [
            item("com.example.photoeditor", "com.example.photoeditor", 1 * GB + 240 * MB, tier: .caution, method: .trash, note: "Support files"),
            item("com.example.photoeditor.plist", "com.example.photoeditor", 12 * 1024, tier: .caution, method: .trash, note: "Preferences", file: "com.example.photoeditor.plist"),
            item("com.example.vpnclient", "com.example.vpnclient", 380 * MB, tier: .caution, method: .trash, note: "Container"),
            item("com.example.vpnclient.helper.plist", "com.example.vpnclient", 4 * 1024, tier: .caution, method: .trash, note: "Startup Item", file: "com.example.vpnclient.helper.plist"),
            item("com.example.notes.savedState", "com.example.notes", 2 * MB, tier: .caution, method: .trash, note: "Saved state"),
        ]
    }

    static var largeFiles: [ScanItem] {
        [
            item("macOS-Installer.dmg", "Large", 14 * GB, tier: .caution, method: .trash, note: "~/Downloads", file: "macOS-Installer.dmg"),
            item("Vacation 2024.mov", "Large", 6 * GB + 300 * MB, tier: .caution, method: .trash, note: "~/Movies", file: "Vacation 2024.mov"),
            item("ubuntu-24.04-desktop.iso", "Large", 5 * GB + 800 * MB, tier: .caution, method: .trash, note: "~/Downloads", file: "ubuntu-24.04-desktop.iso"),
            item("project-backup-2023.zip", "Old", 2 * GB + 100 * MB, tier: .caution, method: .trash, note: "~/Documents · not opened for 2 years", file: "project-backup-2023.zip"),
            item("Screen Recording 2023-04-12.mov", "Old", 870 * MB, tier: .caution, method: .trash, note: "~/Desktop · not opened for 1 year", file: "Screen Recording 2023-04-12.mov"),
        ]
    }

    static var spaceNodes: [SpaceNode] {
        let entries: [(String, Int64, Bool)] = [
            ("Library", 96 * GB, true), ("Movies", 48 * GB, true), ("Projects", 37 * GB, true), ("Pictures", 31 * GB, true),
            ("Downloads", 22 * GB, true), ("Documents", 14 * GB, true), ("macOS-Installer.dmg", 14 * GB, false),
            ("Music", 9 * GB, true), (".docker", 8 * GB, true), ("Desktop", 4 * GB, true), (".npm", 4 * GB, true),
            ("Vacation 2024.mov", 6 * GB, false), (".cache", 3 * GB, true), ("Applications", 2 * GB, true),
            (".vscode", 900 * MB, true), ("Public", 120 * MB, true),
        ]
        return entries.map { name, size, dir in
            SpaceNode(url: url("home/" + name, file: !dir), name: name, size: size, isDirectory: dir)
        }.sorted { $0.size > $1.size }
    }

    static var startupItems: [StartupItem] {
        func agent(_ label: String, _ scope: StartupItem.Scope, enabled: Bool = true, program: String) -> StartupItem {
            StartupItem(label: label, plist: url("LaunchAgents/\(label).plist", file: true), scope: scope, program: program,
                        runAtLoad: true, keepAlive: false, isEnabled: enabled, isLoaded: enabled)
        }
        return [
            agent("com.google.keystone.agent", .user, program: "/bin/sh"),
            agent("com.spotify.webhelper", .user, enabled: false, program: "/bin/sh"),
            agent("homebrew.mxcl.postgresql", .user, program: "/bin/sh"),
            agent("com.example.oldapp.updater", .user, program: "/Applications/Old App.app/Contents/MacOS/updater"),
            agent("com.adobe.ccxprocess", .allUsers, program: "/bin/sh"),
            agent("com.docker.vmnetd", .system, program: "/bin/sh"),
        ]
    }

    static var history: [CleanupResult] {
        let now = Date()
        func r(_ title: String, _ size: Int64, _ ago: Double, _ method: String = "Delete") -> CleanupResult {
            CleanupResult(date: now.addingTimeInterval(-ago), title: title, path: "", size: size, method: method, succeeded: true, error: nil)
        }
        return [
            r("Xcode DerivedData", 18 * GB, 3600), r("npm cache", 4 * GB, 3600, "npm cache clean --force"),
            r("Spotify", 1 * GB, 3700), r("Trash", 3 * GB, 90_000), r("macOS-Installer.dmg", 14 * GB, 90_200, "Move to Trash"),
            r("Slack", 900 * MB, 200_000),
        ]
    }

    /// Puts sample results into every session.
    static func load(into model: AppModel) {
        try? FileManager.default.removeItem(at: root)
        for (session, items) in [(model.storage, storage), (model.developer, developer),
                                 (model.leftovers, leftovers), (model.largeFiles, largeFiles)] {
            session.items = items.sorted { $0.size > $1.size }
            session.selection = Set(items.filter(\.selectedByDefault).map(\.id))
            session.scannedAt = Date()
            session.phase = .results
        }
    }
}

import AppKit
import GlasswipeCore

/// `--demo` fills every screen with made-up data (apps, files, memory, disk), so screenshots show nothing from the real machine.
/// Nothing in demo mode can be removed: the sample paths live in a temporary folder.
@MainActor
enum Demo {
    static let isOn = CommandLine.arguments.contains("--demo")

    static let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("GlasswipeDemo")


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

    // MARK: Made-up apps, so no real app list appears in screenshots

    private struct FakeApp {
        let name: String, id: String, symbol: String, color: NSColor, size: Int64, daysAgo: Double?, memory: UInt64, processes: Int
    }

    private static let fakeApps: [FakeApp] = [
        FakeApp(name: "Photon Studio", id: "com.example.photonstudio", symbol: "camera.aperture", color: .systemOrange, size: 3 * GB + 400 * MB, daysAgo: 2, memory: 2_900 * 1_048_576, processes: 6),
        FakeApp(name: "Codenest", id: "com.example.codenest", symbol: "chevron.left.forwardslash.chevron.right", color: .systemBlue, size: 1 * GB + 900 * MB, daysAgo: 0.02, memory: 1_850 * 1_048_576, processes: 14),
        FakeApp(name: "Reelbox", id: "com.example.reelbox", symbol: "play.rectangle.fill", color: .systemRed, size: 1 * GB + 300 * MB, daysAgo: 40, memory: 1_200 * 1_048_576, processes: 9),
        FakeApp(name: "Pixelforge", id: "com.example.pixelforge", symbol: "paintbrush.pointed.fill", color: .systemPurple, size: 1 * GB + 100 * MB, daysAgo: 210, memory: 0, processes: 0),
        FakeApp(name: "Chatterly", id: "com.example.chatterly", symbol: "bubble.left.and.bubble.right.fill", color: .systemGreen, size: 780 * MB, daysAgo: 0.1, memory: 640 * 1_048_576, processes: 5),
        FakeApp(name: "Tunewave", id: "com.example.tunewave", symbol: "music.note", color: .systemPink, size: 520 * MB, daysAgo: 1, memory: 380 * 1_048_576, processes: 3),
        FakeApp(name: "Vaultkeeper", id: "com.example.vaultkeeper", symbol: "lock.shield.fill", color: .systemTeal, size: 310 * MB, daysAgo: 5, memory: 0, processes: 0),
        FakeApp(name: "Draftboard", id: "com.example.draftboard", symbol: "pencil.and.ruler.fill", color: .systemIndigo, size: 260 * MB, daysAgo: nil, memory: 0, processes: 0),
        FakeApp(name: "Inkwell Notes", id: "com.example.inkwell", symbol: "note.text", color: .systemYellow, size: 180 * MB, daysAgo: 12, memory: 210 * 1_048_576, processes: 2),
        FakeApp(name: "Skyline Weather", id: "com.example.skyline", symbol: "cloud.sun.fill", color: .systemCyan, size: 95 * MB, daysAgo: 400, memory: 0, processes: 0),
    ]

    /// Creates an empty `.app` folder with a rendered icon, so Finder icons look real.
    private static func bundle(for app: FakeApp) -> URL {
        let url = root.appendingPathComponent("Applications/\(app.name).app")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.setIcon(icon(symbol: app.symbol, color: app.color), forFile: url.path, options: [])
        }
        return url
    }

    private static func icon(symbol: String, color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 22, dy: 22), xRadius: 50, yRadius: 50)
            NSGradient(colors: [color.blended(withFraction: 0.25, of: .white)!, color.blended(withFraction: 0.2, of: .black)!])!
                .draw(in: shape, angle: -90)
            let config = NSImage.SymbolConfiguration(pointSize: 110, weight: .semibold).applying(.init(paletteColors: [.white]))
            if let s = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                s.draw(in: NSRect(x: (256 - s.size.width) / 2, y: (256 - s.size.height) / 2, width: s.size.width, height: s.size.height))
            }
            return true
        }
    }

    static var apps: [InstalledApp] {
        fakeApps.map { a in
            InstalledApp(url: bundle(for: a), name: a.name, bundleID: a.id, version: "2.4.1", nestedBundleIDs: [],
                         teamID: "EXAMPLE123", appGroups: ["EXAMPLE123.\(a.id)"], size: a.size,
                         lastUsed: a.daysAgo.map { Date().addingTimeInterval(-$0 * 86_400) })
        }
    }

    static func footprint(of app: InstalledApp) -> [ScanItem] {
        let c = FootprintFinder.category
        func f(_ title: String, _ size: Int64, _ note: String, exact: Bool = true, file: Bool = false) -> ScanItem {
            ScanItem(url: url("footprint/\(app.bundleID)/\(title)", file: file), title: title, category: c,
                     tier: exact ? .safe : .caution, method: .trash, size: size, note: note)
        }
        return [
            ScanItem(url: app.url, title: app.name, category: c, tier: .safe, method: .trash, size: app.size, note: "Application"),
            f(app.bundleID, 1 * GB + 120 * MB, "Container"),
            f(app.bundleID + ".cache", 420 * MB, "Cache"),
            f("EXAMPLE123.\(app.bundleID)", 36 * MB, "Shared container"),
            f(app.bundleID + ".plist", 24 * 1024, "Preferences", file: true),
            f(app.bundleID + ".savedState", 2 * MB, "Saved state"),
            f(app.bundleID + ".agent.plist", 4 * 1024, "Startup Item", file: true),
            f(app.name, 310 * MB, "Support files (name match)", exact: false),
        ]
    }

    static var memoryApps: [AppMemoryUsage] {
        fakeApps.filter { $0.memory > 0 }.enumerated().map { i, a in
            AppMemoryUsage(pid: pid_t(90_000 + i), name: a.name, bundleID: a.id, bundleURL: bundle(for: a), footprint: a.memory,
                           processCount: a.processes, isActive: i == 1, isBackgroundCandidate: i != 1)
        }
        .sorted { $0.footprint > $1.footprint }
    }

    private static var tick = 0
    static var memory: MemorySnapshot {
        tick += 1
        let wobble = Int(2 * sin(Double(tick) / 3))
        return MemorySnapshot(total: 16 * UInt64(GB), app: 7 * UInt64(GB) + 300 * UInt64(MB), wired: 2 * UInt64(GB) + 600 * UInt64(MB),
                              compressed: 1 * UInt64(GB) + 400 * UInt64(MB), cached: 3 * UInt64(GB) + 100 * UInt64(MB),
                              free: 900 * UInt64(MB), swapUsed: 512 * UInt64(MB), availablePercent: 66 + wobble,
                              level: .normal, date: Date())
    }

    static var stats: SystemStats {
        SystemStats(cpuPercent: 18, diskFree: 214 * GB, diskTotal: 1_000 * GB, batteryPercent: 82, isCharging: false)
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

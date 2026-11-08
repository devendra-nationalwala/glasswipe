import Foundation

/// Finds an app's App Footprint by exact identifier match, never by substring.
public struct FootprintFinder: Sendable {
    public let home: String
    public let systemRoot: String

    public init(home: String = NSHomeDirectory(), systemRoot: String = "") {
        self.home = home
        self.systemRoot = systemRoot
    }

    public static let category = "App Footprint"

    /// The app bundle plus every file that belongs to it.
    /// Exact identifier matches start ticked; name-only matches are shown unticked.
    public func footprint(of app: InstalledApp) -> [ScanItem] {
        var urls: [(URL, Bool, String)] = [] // url, exact, kind

        func add(_ path: String, exact: Bool, kind: String) {
            if FileManager.default.fileExists(atPath: path) { urls.append((URL(fileURLWithPath: path), exact, kind)) }
        }

        let lib = home + "/Library"
        let sys = systemRoot + "/Library"
        for id in app.allBundleIDs {
            add("\(lib)/Application Support/\(id)", exact: true, kind: "Support files")
            add("\(lib)/Caches/\(id)", exact: true, kind: "Cache")
            add("\(lib)/Preferences/\(id).plist", exact: true, kind: "Preferences")
            add("\(lib)/Saved Application State/\(id).savedState", exact: true, kind: "Saved state")
            add("\(lib)/HTTPStorages/\(id)", exact: true, kind: "Web data")
            add("\(lib)/HTTPStorages/\(id).binarycookies", exact: true, kind: "Cookies")
            add("\(lib)/Cookies/\(id).binarycookies", exact: true, kind: "Cookies")
            add("\(lib)/WebKit/\(id)", exact: true, kind: "Web data")
            add("\(lib)/Containers/\(id)", exact: true, kind: "Container")
            add("\(lib)/Application Scripts/\(id)", exact: true, kind: "Scripts")
            add("\(lib)/Logs/\(id)", exact: true, kind: "Logs")
            add("\(sys)/Application Support/\(id)", exact: true, kind: "Support files (system)")
            add("\(sys)/Preferences/\(id).plist", exact: true, kind: "Preferences (system)")
            add("\(sys)/Caches/\(id)", exact: true, kind: "Cache (system)")
            for (dir, kind) in [("\(lib)/Preferences/ByHost", "Preferences"),
                                ("\(lib)/LaunchAgents", "Startup Item"),
                                ("\(sys)/LaunchAgents", "Startup Item (system)"),
                                ("\(sys)/LaunchDaemons", "Startup Item (system)"),
                                ("\(sys)/PrivilegedHelperTools", "Helper tool (system)")] {
                for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
                where name == id || name.hasPrefix(id + ".") {
                    urls.append((URL(fileURLWithPath: dir + "/" + name), true, kind))
                }
            }
        }
        for group in app.appGroups {
            add("\(lib)/Group Containers/\(group)", exact: true, kind: "Shared container")
        }

        // Name matches: shown, but the user must opt in.
        let names = Set([app.name, app.url.deletingPathExtension().lastPathComponent])
        for name in names where name.count >= 3 {
            add("\(lib)/Application Support/\(name)", exact: false, kind: "Support files (name match)")
            add("\(lib)/Caches/\(name)", exact: false, kind: "Cache (name match)")
            add("\(lib)/Logs/\(name)", exact: false, kind: "Logs (name match)")
            let electron = "com.electron." + name.lowercased().replacingOccurrences(of: " ", with: "")
            add("\(lib)/Preferences/\(electron).plist", exact: false, kind: "Preferences (name match)")
            add("\(lib)/Saved Application State/\(electron).savedState", exact: false, kind: "Saved state (name match)")
        }

        var seen: Set<String> = []
        var items = [ScanItem(
            url: app.url, title: app.name, category: Self.category, tier: .safe,
            method: FileManager.default.isDeletableFile(atPath: app.url.path) ? .trash : .adminDelete,
            size: app.size, note: "Application"
        )]
        seen.insert(app.url.path)
        for (url, exact, kind) in urls where !seen.contains(url.path) {
            seen.insert(url.path)
            let isSystem = url.path.hasPrefix(sys + "/")
            items.append(ScanItem(
                url: url,
                title: url.lastPathComponent,
                category: Self.category,
                tier: exact ? .safe : .caution,
                method: isSystem ? .adminDelete : .trash,
                size: FileSize.allocatedSize(of: url),
                note: kind,
                modified: FileSize.modificationDate(of: url)
            ))
        }
        return items
    }
}

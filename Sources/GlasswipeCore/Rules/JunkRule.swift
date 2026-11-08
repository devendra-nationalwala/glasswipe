import Foundation

/// One entry in `junk-rules.json`: where a kind of Junk lives and how to remove it.
public struct JunkRule: Codable, Sendable, Identifiable {
    public enum Group: String, Codable, Sendable, CaseIterable {
        case system, browser, developer, largeDownloads

        public var title: String {
            switch self {
            case .system: "System Junk"
            case .browser: "Browser Caches"
            case .developer: "Developer Junk"
            case .largeDownloads: "Large Downloads"
            }
        }
    }

    public enum Method: String, Codable, Sendable { case delete, trash, admin }

    public struct Tool: Codable, Sendable {
        /// Executable name, looked up on PATH-like locations.
        public let name: String
        public let arguments: [String]
        /// Process name that must not be running while the command runs.
        public let process: String?
    }

    public struct Walk: Codable, Sendable {
        /// Folders to search, e.g. `~/repos`.
        public let roots: [String]
        /// Folder name to find, e.g. `node_modules`.
        public let name: String
        public let maxDepth: Int
        /// A sibling file that must exist for the match to count (e.g. `package.json`).
        public let requiresSibling: String?
    }

    public let id: String
    public let title: String
    public let group: Group
    public let tier: Tier
    public let method: Method
    /// Glob patterns; each match becomes one Scan item. `~` expands to home, `*` matches one path component.
    public let paths: [String]?
    public let walk: Walk?
    public let tool: Tool?
    /// Only ever removed through `tool`; skipped when the tool is not installed.
    public let toolOnly: Bool?
    /// Remove the matched folder's contents but keep the folder.
    public let contentsOnly: Bool?
    /// Only items not modified for this many days.
    public let minAgeDays: Int?
    /// Skip items while this app (bundle id) is running.
    public let skipWhileRunning: String?
    /// Skip a matched folder whose name is the bundle id of a running app.
    public let skipRunningBundleIDs: Bool?
    /// Match names to ignore (exact or `prefix*`).
    public let ignore: [String]?
    public let needsFullDiskAccess: Bool?
    public let note: String?
}

public struct JunkRuleSet: Codable, Sendable {
    public let version: Int
    public let rules: [JunkRule]

    /// Loads the rules bundled with the app. Returns nil if they are missing or invalid,
    /// in which case the Safety Gate refuses every removal.
    public static func bundled() -> JunkRuleSet? {
        guard let url = ResourceLocator.url(forResource: "junk-rules", withExtension: "json") else { return nil }
        return try? load(from: url)
    }

    public static func load(from url: URL) throws -> JunkRuleSet {
        try JSONDecoder().decode(JunkRuleSet.self, from: Data(contentsOf: url))
    }
}

/// Finds GlasswipeCore resources both inside the assembled .app and under `swift run`/`swift test`.
enum ResourceLocator {
    static let bundleName = "Glasswipe_GlasswipeCore.bundle"

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        // Inside Glasswipe.app the build script copies the resource bundle into Contents/Resources.
        if let resources = Bundle.main.resourceURL {
            let candidate = resources.appendingPathComponent(bundleName)
            if let bundle = Bundle(url: candidate), let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        // Next to the executable (swift run / swift test builds).
        let exeDir = Bundle.main.bundleURL
        for dir in [exeDir, exeDir.deletingLastPathComponent()] {
            let candidate = dir.appendingPathComponent(bundleName)
            if let bundle = Bundle(url: candidate), let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        for bundle in Bundle.allBundles where bundle.bundleURL.lastPathComponent == bundleName {
            if let url = bundle.url(forResource: name, withExtension: ext) { return url }
        }
        return nil
    }
}

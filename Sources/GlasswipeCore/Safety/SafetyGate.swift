import Foundation

/// The single check every removal passes through. Fails closed.
public struct SafetyGate: Sendable {
    public enum Refusal: Error, Equatable, CustomStringConvertible, Sendable {
        case protectedLocation(String)
        case notAbsolute(String)
        case symlinkEscapes(String)
        case excludedByUser(String)
        case rulesUnavailable

        public var description: String {
            switch self {
            case .protectedLocation(let p): "Protected location: \(p)"
            case .notAbsolute(let p): "Not an absolute path: \(p)"
            case .symlinkEscapes(let p): "Symlink points outside its folder: \(p)"
            case .excludedByUser(let p): "Excluded in Settings: \(p)"
            case .rulesUnavailable: "Safety rules could not be loaded"
            }
        }
    }

    public let home: String
    public let exclusions: [String]
    public let rulesLoaded: Bool
    /// Uninstall and Leftovers may remove an app's whole container; Junk cleanup may not.
    public let allowWholeContainers: Bool

    public init(home: String = NSHomeDirectory(), exclusions: [String] = [], rulesLoaded: Bool = true,
                allowWholeContainers: Bool = false) {
        self.home = (home as NSString).standardizingPath
        self.exclusions = exclusions.map { ($0 as NSString).expandingTildeInPath }
        self.rulesLoaded = rulesLoaded
        self.allowWholeContainers = allowWholeContainers
    }

    /// The same gate, relaxed for removing whole apps.
    public var forUninstall: SafetyGate {
        SafetyGate(home: home, exclusions: exclusions, rulesLoaded: rulesLoaded, allowWholeContainers: true)
    }

    /// Exact paths that may never be removed.
    var protectedExact: Set<String> {
        var paths: Set<String> = [
            "/", "/Applications", "/Library", "/System", "/Users", "/Volumes", "/private",
            "/private/var", "/private/tmp", "/private/etc", "/tmp", "/var", "/etc", "/opt",
            "/opt/homebrew", "/usr/local", "/Library/Caches", "/Library/Logs",
            "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/Application Support",
        ]
        paths.insert(home)
        let homeChildren = [
            "Library", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures",
            "Public", "Applications", ".Trash", "repos", ".cache", ".npm", ".docker",
            "Library/Caches", "Library/Logs", "Library/Containers", "Library/Group Containers",
            "Library/Application Support", "Library/Preferences", "Library/LaunchAgents",
            "Library/Developer", "Library/Mobile Documents", "Library/Mail", "Library/Messages",
            "Library/Keychains", "Library/Safari",
        ]
        for child in homeChildren { paths.insert(home + "/" + child) }
        return paths
    }

    /// Prefixes under which nothing may be removed.
    var protectedPrefixes: [String] {
        [
            "/System/", "/bin/", "/sbin/", "/usr/bin/", "/usr/sbin/", "/usr/lib/", "/usr/libexec/",
            "/usr/share/", "/private/var/vm/", "/private/var/db/", "/var/vm/", "/var/db/",
            "/Library/Updates/", "/Library/Developer/CommandLineTools/", "/Library/Apple/",
            "/opt/homebrew/Cellar/", "/Library/Keychains/",
            home + "/Library/Keychains/", home + "/Library/Mobile Documents/",
        ]
    }

    /// Path fragments that identify data we never remove, wherever they are.
    var protectedFragments: [String] { ["/Docker.raw", "/.git/", ".sparsebundle", "/Photos Library.photoslibrary"] }

    /// Throws if `url` may not be removed.
    public func check(_ url: URL, scannedRoot: URL? = nil) throws {
        guard rulesLoaded else { throw Refusal.rulesUnavailable }
        let raw = url.path
        guard raw.hasPrefix("/") else { throw Refusal.notAbsolute(raw) }
        let path = (raw as NSString).standardizingPath
        let real = url.resolvingSymlinksInPath().path

        for candidate in Set([path, real]) {
            if protectedExact.contains(candidate) { throw Refusal.protectedLocation(candidate) }
            if protectedPrefixes.contains(where: { candidate.hasPrefix($0) }) {
                throw Refusal.protectedLocation(candidate)
            }
            if protectedFragments.contains(where: { (candidate + "/").contains($0) }) {
                throw Refusal.protectedLocation(candidate)
            }
            // A whole container is an app's home folder, not Junk.
            if !allowWholeContainers && isWholeContainer(candidate) { throw Refusal.protectedLocation(candidate) }
            for exclusion in exclusions where candidate == exclusion || candidate.hasPrefix(exclusion + "/") {
                throw Refusal.excludedByUser(candidate)
            }
        }

        if let root = scannedRoot, isSymlink(url) {
            let rootPath = root.resolvingSymlinksInPath().path
            if !(real == rootPath || real.hasPrefix(rootPath + "/")) {
                throw Refusal.symlinkEscapes(path)
            }
        }
    }

    public func allows(_ url: URL, scannedRoot: URL? = nil) -> Bool {
        (try? check(url, scannedRoot: scannedRoot)) != nil
    }

    private func isWholeContainer(_ path: String) -> Bool {
        for root in [home + "/Library/Containers/", home + "/Library/Group Containers/"] where path.hasPrefix(root) {
            let rest = path.dropFirst(root.count)
            let parts = rest.split(separator: "/")
            // <root>/<id> or <root>/<id>/Data
            if parts.count == 1 || (parts.count == 2 && parts[1] == "Data") { return true }
        }
        return false
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}

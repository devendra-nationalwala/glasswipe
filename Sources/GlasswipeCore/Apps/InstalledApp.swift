import AppKit
import Foundation
import Security

/// An app bundle installed on this Mac.
public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String?
    /// Bundle IDs of nested helpers, login items, extensions and XPC services.
    public let nestedBundleIDs: [String]
    public let teamID: String?
    /// App Group identifiers from the code signature's entitlements.
    public let appGroups: [String]
    public let size: Int64
    public let lastUsed: Date?

    public init(url: URL, name: String, bundleID: String, version: String?, nestedBundleIDs: [String], teamID: String?,
                appGroups: [String], size: Int64, lastUsed: Date?) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.nestedBundleIDs = nestedBundleIDs
        self.teamID = teamID
        self.appGroups = appGroups
        self.size = size
        self.lastUsed = lastUsed
    }

    public var allBundleIDs: [String] { [bundleID] + nestedBundleIDs }
    public var isApple: Bool { bundleID.hasPrefix("com.apple.") }
}

public enum AppInventory {
    public static var searchRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
        ]
    }

    /// Apps that cannot or must not be removed.
    static let pinned: Set<String> = ["com.apple.Safari", "com.apple.finder"]

    /// All apps in the standard locations (and one folder level below, e.g. `/Applications/Setapp`).
    public static func scan(roots: [URL] = searchRoots, measure: Bool = true) async -> [InstalledApp] {
        var bundles: [URL] = []
        for root in roots {
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for child in children {
                if child.pathExtension == "app" { bundles.append(child) }
                else if child.hasDirectoryPath || (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                        child.lastPathComponent != "Utilities",
                        let inner = try? FileManager.default.contentsOfDirectory(at: child, includingPropertiesForKeys: nil) {
                    bundles += inner.filter { $0.pathExtension == "app" }
                }
            }
        }
        let unique = Array(Set(bundles.map { $0.resolvingSymlinksInPath() }))
        return await withTaskGroup(of: InstalledApp?.self) { group in
            for url in unique { group.addTask { describe(url, measure: measure) } }
            var apps: [InstalledApp] = []
            for await app in group { if let app, !pinned.contains(app.bundleID) { apps.append(app) } }
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    public static func describe(_ url: URL, measure: Bool = true) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let signing = CodeSignature.read(url)
        return InstalledApp(
            url: url,
            name: url.deletingPathExtension().lastPathComponent.isEmpty ? name : url.deletingPathExtension().lastPathComponent,
            bundleID: bundleID,
            version: info["CFBundleShortVersionString"] as? String,
            nestedBundleIDs: nestedBundleIDs(in: url).filter { $0 != bundleID },
            teamID: signing.teamID,
            appGroups: signing.appGroups,
            size: measure ? FileSize.allocatedSize(of: url) : 0,
            lastUsed: lastUsedDate(url)
        )
    }

    static func nestedBundleIDs(in app: URL) -> [String] {
        let contents = app.appendingPathComponent("Contents")
        let places = ["Library/LoginItems", "Library/LaunchServices", "XPCServices", "PlugIns", "Helpers", "Library/SystemExtensions", "Frameworks"]
        var ids: Set<String> = []
        for place in places {
            let dir = contents.appendingPathComponent(place)
            guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                let ext = url.pathExtension
                guard ["app", "appex", "xpc", "systemextension"].contains(ext) || (place == "Library/LaunchServices" && ext.isEmpty) else {
                    if enumerator.level > 4 { enumerator.skipDescendants() }
                    continue
                }
                if let id = Bundle(url: url)?.bundleIdentifier { ids.insert(id) }
                else if place == "Library/LaunchServices" { ids.insert(url.lastPathComponent) } // privileged helpers are named by id
                enumerator.skipDescendants()
            }
        }
        return ids.sorted()
    }

    static func lastUsedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}

enum CodeSignature {
    struct Info { var teamID: String?; var appGroups: [String] }

    static func read(_ url: URL) -> Info {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            return Info(teamID: nil, appGroups: [])
        }
        var dict: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &dict) == errSecSuccess,
              let info = dict as? [String: Any] else { return Info(teamID: nil, appGroups: []) }
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        let groups = (entitlements?["com.apple.security.application-groups"] as? [String] ?? []).filter { !$0.isEmpty }
        return Info(teamID: team, appGroups: groups)
    }
}

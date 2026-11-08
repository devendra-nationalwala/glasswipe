import AppKit
import Foundation

/// Human-readable names for bundle identifiers found on disk.
public enum AppNames {
    private static let cache = NameCache()

    public static func name(forBundleID id: String) -> String {
        if let cached = cache.get(id) { return cached }
        var name = id
        if id.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        cache.set(id, name)
        return name
    }

    public static func icon(forBundleID id: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private final class NameCache: @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()
    func get(_ key: String) -> String? { lock.withLock { storage[key] } }
    func set(_ key: String, _ value: String) { lock.withLock { storage[key] = value } }
}

import Foundation

/// A folder or file in Space Lens.
public struct SpaceNode: Identifiable, Sendable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let size: Int64
    public let isDirectory: Bool
}

public enum SpaceLens {
    /// Immediate children of a folder with their allocated sizes, largest first.
    /// Packages (.app, .photoslibrary…) count as single items. `partial` receives each child as soon as it is measured.
    public static func children(of url: URL, partial: (@Sendable (SpaceNode) -> Void)? = nil) async -> [SpaceNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: []) else {
            return []
        }
        let candidates = entries.filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
        return await withTaskGroup(of: SpaceNode?.self) { group in
            for child in candidates {
                group.addTask {
                    let size = await FileSize.parallelAllocatedSize(of: child)
                    guard size > 0 else { return nil }
                    let values = try? child.resourceValues(forKeys: Set(keys))
                    let isDir = values?.isDirectory == true && values?.isPackage != true
                    let node = SpaceNode(url: child, name: FileManager.default.displayName(atPath: child.path), size: size, isDirectory: isDir)
                    partial?(node)
                    return node
                }
            }
            var nodes: [SpaceNode] = []
            for await node in group { if let node { nodes.append(node) } }
            return nodes.sorted { $0.size > $1.size }
        }
    }

    public struct Volume: Sendable {
        public let total: Int64
        public let available: Int64
    }

    public static func volume(for url: URL = URL(fileURLWithPath: "/")) -> Volume? {
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity else { return nil }
        return Volume(total: Int64(total), available: values.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

/// Finds big or long-untouched files in the user's own folders.
public struct LargeFilesFinder: Sendable {
    public let roots: [URL]
    public let minimumSize: Int64
    /// Files not opened for this many days count as old.
    public let oldAfterDays: Int
    public let minimumOldSize: Int64

    public init(roots: [URL] = [FileManager.default.homeDirectoryForCurrentUser],
                minimumSize: Int64 = 100 * 1_048_576, oldAfterDays: Int = 365, minimumOldSize: Int64 = 20 * 1_048_576) {
        self.roots = roots
        self.minimumSize = minimumSize
        self.oldAfterDays = oldAfterDays
        self.minimumOldSize = minimumOldSize
    }

    static let skippedNames: Set<String> = ["Library", ".Trash", "node_modules", ".git", ".cache", ".npm", ".docker", ".cargo", ".gradle", ".m2", ".rustup", ".nvm", ".bun", "go"]

    public static let category = "Large & Old Files"

    public func scan(now: Date = Date()) -> [ScanItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
                                      .contentAccessDateKey, .contentModificationDateKey]
        let cutoff = now.addingTimeInterval(-Double(oldAfterDays) * 86_400)
        var items: [ScanItem] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                                   options: [.skipsPackageDescendants],
                                                                   errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if v.isSymbolicLink == true { continue }
                if v.isDirectory == true && v.isPackage != true {
                    let name = url.lastPathComponent
                    if Self.skippedNames.contains(name) || (name.hasPrefix(".") && enumerator.level == 1) { enumerator.skipDescendants() }
                    continue
                }
                let size = v.isPackage == true ? FileSize.allocatedSize(of: url) : Int64(v.totalFileAllocatedSize ?? 0)
                let lastUse = max(v.contentAccessDate ?? .distantPast, v.contentModificationDate ?? .distantPast)
                let isLarge = size >= minimumSize
                let isOld = size >= minimumOldSize && lastUse < cutoff
                guard isLarge || isOld else { continue }
                items.append(ScanItem(
                    url: url,
                    title: url.lastPathComponent,
                    category: isLarge ? "Large" : "Old",
                    tier: .caution,
                    method: .trash,
                    size: size,
                    note: url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                    modified: lastUse == .distantPast ? nil : lastUse
                ))
            }
        }
        return items.sorted { $0.size > $1.size }
    }
}

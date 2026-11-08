import Foundation

/// How risky it is to remove an item.
public enum Tier: String, Codable, Sendable, CaseIterable, Comparable {
    /// Recreated by its owner; pre-selected.
    case safe
    /// Not recoverable or shared state; shown unticked.
    case caution
    /// Never shown, never removed.
    case protected

    public static func < (lhs: Tier, rhs: Tier) -> Bool {
        let order: [Tier] = [.safe, .caution, .protected]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// How a Cleanup removes an item.
public enum RemovalMethod: Codable, Sendable, Hashable {
    /// Delete outright. Only for Safe Junk that its owner recreates.
    case delete
    /// Move to the Trash so it can be restored.
    case trash
    /// Run the owning tool's own clean command instead of touching files.
    case toolCommand(executable: String, arguments: [String])
    /// Delete with administrator privileges (system locations).
    case adminDelete

    public var label: String {
        switch self {
        case .delete: "Delete"
        case .trash: "Move to Trash"
        case .toolCommand(let executable, let arguments):
            ([URL(fileURLWithPath: executable).lastPathComponent] + arguments).joined(separator: " ")
        case .adminDelete: "Delete (admin)"
        }
    }
}

/// One candidate for removal found by a Scan.
public struct ScanItem: Identifiable, Hashable, Sendable {
    public var id: String { url?.path ?? "\(category)#\(title)" }
    public let url: URL?
    public let title: String
    public let category: String
    public let tier: Tier
    public let method: RemovalMethod
    /// Allocated size on disk, in bytes.
    public let size: Int64
    public let note: String?
    /// Set when the item is in use (e.g. its app is running) and must not be removed now.
    public let inUseBy: String?
    /// Remove the folder's contents but keep the folder itself.
    public let contentsOnly: Bool
    /// Last modification date, when known.
    public let modified: Date?

    public init(
        url: URL?,
        title: String,
        category: String,
        tier: Tier,
        method: RemovalMethod,
        size: Int64,
        note: String? = nil,
        inUseBy: String? = nil,
        contentsOnly: Bool = false,
        modified: Date? = nil
    ) {
        self.url = url
        self.title = title
        self.category = category
        self.tier = tier
        self.method = method
        self.size = size
        self.note = note
        self.inUseBy = inUseBy
        self.contentsOnly = contentsOnly
        self.modified = modified
    }

    /// Whether the item starts ticked in a results list.
    public var selectedByDefault: Bool { tier == .safe && inUseBy == nil }
}

public extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

import Foundation

/// Measures allocated size on disk (not apparent size, which overstates sparse files).
public enum FileSize {
    static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// Allocated size of a file, or the sum over a folder's contents. Does not follow symlinks.
    public static func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        guard values.isDirectory == true else { return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0) }

        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        for case let child as URL in enumerator {
            guard let v = try? child.resourceValues(forKeys: keys), v.isSymbolicLink != true, v.isDirectory != true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Sizes many items concurrently.
    public static func allocatedSizes(of urls: [URL]) async -> [URL: Int64] {
        await withTaskGroup(of: (URL, Int64).self) { group in
            for url in urls { group.addTask { (url, allocatedSize(of: url)) } }
            var result: [URL: Int64] = [:]
            for await (url, size) in group { result[url] = size }
            return result
        }
    }

    public static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

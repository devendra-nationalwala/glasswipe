import Foundation

/// The outcome of removing one item.
public struct CleanupResult: Sendable, Codable, Identifiable {
    public var id: String { path + "@" + String(date.timeIntervalSince1970) }
    public let date: Date
    public let title: String
    public let path: String
    public let size: Int64
    public let method: String
    public let succeeded: Bool
    public let error: String?
}

/// Performs the actual changes on disk. Swappable so tests never touch real files.
public protocol Remover: Sendable {
    func delete(_ url: URL) throws
    func trash(_ url: URL) throws
    func run(_ executable: String, _ arguments: [String]) throws
    /// Deletes all paths in one administrator-authorised call.
    func adminDelete(_ paths: [String]) throws
}

public struct FileSystemRemover: Remover {
    public init() {}

    public func delete(_ url: URL) throws { try FileManager.default.removeItem(at: url) }

    public func trash(_ url: URL) throws { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }

    public func run(_ executable: String, _ arguments: [String]) throws {
        let result = try Shell.run(executable, arguments)
        guard result.status == 0 else {
            throw CleanupError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    public func adminDelete(_ paths: [String]) throws {
        try AdminRunner.run(command: "/bin/rm -rf " + paths.map(Shell.quote).joined(separator: " "))
    }
}

public enum CleanupError: Error, LocalizedError {
    case commandFailed(String)
    case inUse(String)
    public var errorDescription: String? {
        switch self {
        case .commandFailed(let output): "Command failed: \(output.prefix(300))"
        case .inUse(let by): "In use by \(by)"
        }
    }
}

/// Removes approved Scan items. Every path passes the Safety Gate first; every result is logged.
public struct CleanupExecutor: Sendable {
    public let gate: SafetyGate
    public let remover: any Remover
    public let log: CleanupLog?

    public init(gate: SafetyGate, remover: any Remover = FileSystemRemover(), log: CleanupLog? = .standard) {
        self.gate = gate
        self.remover = remover
        self.log = log
    }

    public func clean(_ items: [ScanItem], progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [CleanupResult] {
        var results: [CleanupResult] = []
        var adminBatch: [(ScanItem, [URL])] = []

        for (index, item) in items.enumerated() {
            progress?(index, items.count)
            if item.method == .adminDelete {
                do { adminBatch.append((item, try targets(for: item))) } catch { results.append(result(item, error)) }
                continue
            }
            results.append(perform(item))
        }

        if !adminBatch.isEmpty {
            let paths = adminBatch.flatMap { $0.1.map(\.path) }
            var batchError: Error?
            if !paths.isEmpty {
                do { try remover.adminDelete(paths) } catch { batchError = error }
            }
            for (item, _) in adminBatch { results.append(result(item, batchError)) }
        }
        progress?(items.count, items.count)
        log?.append(results)
        return results
    }

    private func perform(_ item: ScanItem) -> CleanupResult {
        do {
            if let busy = item.inUseBy { throw CleanupError.inUse(busy) }
            switch item.method {
            case .toolCommand(let executable, let arguments):
                try remover.run(executable, arguments)
            case .delete:
                for url in try targets(for: item) { try remover.delete(url) }
            case .trash:
                for url in try targets(for: item) { try remover.trash(url) }
            case .adminDelete:
                break
            }
            return result(item, nil)
        } catch {
            return result(item, error)
        }
    }

    /// The concrete paths to remove, each checked by the Safety Gate.
    func targets(for item: ScanItem) throws -> [URL] {
        guard let url = item.url else { return [] }
        if item.contentsOnly {
            let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            for child in children { try gate.check(child, scannedRoot: url) }
            return children
        }
        try gate.check(url)
        return [url]
    }

    private func result(_ item: ScanItem, _ error: Error?) -> CleanupResult {
        CleanupResult(
            date: Date(),
            title: item.title,
            path: item.url?.path ?? item.method.label,
            size: error == nil ? item.size : 0,
            method: item.method.label,
            succeeded: error == nil,
            error: error.map { ($0 as? LocalizedError)?.errorDescription ?? String(describing: $0) }
        )
    }
}

/// Append-only JSON Lines log of every Cleanup, read by the History view.
public final class CleanupLog: Sendable {
    public let url: URL
    private let lock = NSLock()

    public static let standard = CleanupLog(
        url: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Glasswipe/cleanup.jsonl"))

    public init(url: URL) { self.url = url }

    public func append(_ results: [CleanupResult]) {
        guard !results.isEmpty else { return }
        lock.withLock {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var data = Data()
            for r in results {
                if let line = try? encoder.encode(r) { data.append(line); data.append(0x0A) }
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(data); try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    public func read() -> [CleanupResult] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(CleanupResult.self, from: Data($0.utf8)) }
    }
}

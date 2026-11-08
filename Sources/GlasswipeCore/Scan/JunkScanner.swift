import Foundation

/// Turns Junk rules into Scan items. Read-only: never changes anything on disk.
public struct JunkScanner: Sendable {
    public let rules: [JunkRule]
    public let environment: ScanEnvironment
    public let gate: SafetyGate
    public let hasFullDiskAccess: Bool

    public init(rules: [JunkRule], environment: ScanEnvironment, gate: SafetyGate, hasFullDiskAccess: Bool) {
        self.rules = rules
        self.environment = environment
        self.gate = gate
        self.hasFullDiskAccess = hasFullDiskAccess
    }

    public struct Progress: Sendable {
        public let completed: Int
        public let total: Int
        public let current: String
    }

    /// Scans every rule, reporting progress as each finishes.
    /// `found` is called with each rule's items as soon as that rule finishes, so results can appear progressively.
    public func scan(groups: Set<JunkRule.Group> = Set(JunkRule.Group.allCases),
                     progress: (@Sendable (Progress) -> Void)? = nil,
                     found: (@Sendable ([ScanItem]) -> Void)? = nil) async -> [ScanItem] {
        let selected = rules.filter { groups.contains($0.group) }
        progress?(Progress(completed: 0, total: selected.count, current: selected.first?.title ?? ""))
        return await withTaskGroup(of: (String, [ScanItem]).self) { group in
            for rule in selected { group.addTask { (rule.title, await scan(rule: rule)) } }
            var items: [ScanItem] = []
            var completed = 0
            for await (title, ruleItems) in group {
                completed += 1
                items += ruleItems
                if !ruleItems.isEmpty { found?(ruleItems) }
                progress?(Progress(completed: completed, total: selected.count, current: "Measured \(title)"))
            }
            return items.sorted { $0.size > $1.size }
        }
    }

    public func scan(rule: JunkRule) async -> [ScanItem] {
        if rule.tier == .protected { return [] }
        if rule.needsFullDiskAccess == true && !hasFullDiskAccess { return [] }

        let toolPath = rule.tool.flatMap { environment.locateTool($0.name) }
        if rule.toolOnly == true && toolPath == nil { return [] }

        var matches = rule.paths.map { $0.flatMap { Glob.expand(environment.expand($0)) } } ?? []
        if let walk = rule.walk { matches += ProjectWalker.find(walk, environment: environment) }

        matches = matches.filter { url in
            let name = url.lastPathComponent
            if let ignore = rule.ignore, ignore.contains(where: { Glob.matches(name: name, pattern: $0) }) { return false }
            return gate.allows(url) || rule.contentsOnly == true && gate.allows(url.appendingPathComponent("x"))
        }

        if let days = rule.minAgeDays {
            let cutoff = environment.now.addingTimeInterval(-Double(days) * 86_400)
            matches = matches.filter { (FileSize.modificationDate(of: $0) ?? .distantFuture) < cutoff }
        }

        let sizes = await FileSize.allocatedSizes(of: matches)

        var inUse: String?
        if let bundleID = rule.skipWhileRunning,
           environment.runningBundleIDs.contains(bundleID) || environment.runningProcessNames.contains(bundleID.lowercased()) {
            inUse = bundleID
        }

        // Tool rules collapse into one item: the command cleans everything at once.
        if let tool = rule.tool, let toolPath {
            let total = matches.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) }
            guard total > 0 || rule.toolOnly == true else { return [] }
            if total == 0 { return [] }
            var busy = inUse
            if let process = tool.process, environment.runningProcessNames.contains(process.lowercased()) { busy = process }
            return [ScanItem(
                url: matches.count == 1 ? matches[0] : nil,
                title: rule.title,
                category: rule.group.title,
                tier: rule.tier,
                method: .toolCommand(executable: toolPath, arguments: tool.arguments),
                size: total,
                note: rule.note,
                inUseBy: busy
            )]
        }

        let method: RemovalMethod = switch rule.method {
        case .delete: .delete
        case .trash: .trash
        case .admin: .adminDelete
        }

        return matches.compactMap { url in
            let size = sizes[url] ?? 0
            guard size > 0 else { return nil }
            var busy = inUse
            let folder = url.lastPathComponent
            if rule.skipRunningBundleIDs == true,
               environment.runningBundleIDs.contains(folder) || environment.runningAppNames.contains(folder.lowercased()) {
                busy = folder
            }
            return ScanItem(
                url: url,
                title: displayName(for: url, rule: rule),
                category: rule.group.title,
                tier: rule.tier,
                method: method,
                size: size,
                note: rule.note,
                inUseBy: busy,
                contentsOnly: rule.contentsOnly == true,
                modified: FileSize.modificationDate(of: url)
            )
        }
    }

    private func displayName(for url: URL, rule: JunkRule) -> String {
        let short = url.path.replacingOccurrences(of: environment.home, with: "~")
        if rule.walk != nil {
            return url.deletingLastPathComponent().path.replacingOccurrences(of: environment.home, with: "~")
        }
        let paths = rule.paths ?? []
        let globbed = paths.contains { $0.contains("*") }
        if !globbed {
            return paths.count > 1 ? "\(rule.title) · \(short)" : rule.title
        }
        if rule.id == "sandboxed-caches" {
            return AppNames.name(forBundleID: url.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().lastPathComponent)
        }
        if rule.id.hasPrefix("user-") || rule.id.hasPrefix("system-") {
            return AppNames.name(forBundleID: url.lastPathComponent)
        }
        return url.lastPathComponent
    }
}

/// Minimal glob: `*` matches within one path component.
enum Glob {
    static func expand(_ pattern: String) -> [URL] {
        let components = pattern.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var current = ["/"]
        for component in components {
            var next: [String] = []
            for base in current {
                if component.contains("*") {
                    guard let children = try? FileManager.default.contentsOfDirectory(atPath: base) else { continue }
                    for child in children where matches(name: child, pattern: component) {
                        next.append((base as NSString).appendingPathComponent(child))
                    }
                } else {
                    let path = (base as NSString).appendingPathComponent(component)
                    if FileManager.default.fileExists(atPath: path) { next.append(path) }
                }
            }
            current = next
            if current.isEmpty { break }
        }
        return current.filter { $0 != "/" }.map { URL(fileURLWithPath: $0) }
    }

    static func matches(name: String, pattern: String) -> Bool {
        fnmatch(pattern, name, 0) == 0
    }
}

/// Finds project folders such as `node_modules` under the user's code roots.
enum ProjectWalker {
    static func find(_ walk: JunkRule.Walk, environment: ScanEnvironment) -> [URL] {
        var found: [URL] = []
        for root in walk.roots {
            let rootPath = environment.expand(root)
            guard FileManager.default.fileExists(atPath: rootPath) else { continue }
            search(URL(fileURLWithPath: rootPath), depth: 0, walk: walk, found: &found)
        }
        return found
    }

    private static func search(_ dir: URL, depth: Int, walk: JunkRule.Walk, found: inout [URL]) {
        guard depth <= walk.maxDepth,
              let children = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
        else { return }
        for child in children {
            guard let v = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  v.isDirectory == true, v.isSymbolicLink != true else { continue }
            let name = child.lastPathComponent
            if name == walk.name {
                if let sibling = walk.requiresSibling,
                   !FileManager.default.fileExists(atPath: dir.appendingPathComponent(sibling).path) { continue }
                found.append(child)
                continue // never descend into a match
            }
            if name.hasPrefix(".") || name == "Library" { continue }
            search(child, depth: depth + 1, walk: walk, found: &found)
        }
    }
}

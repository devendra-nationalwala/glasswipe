import GlasswipeCore
import Observation
import SwiftUI

/// The Scan → review → Cleanup flow shared by every module that removes files.
@MainActor
@Observable
final class ScanSession {
    enum Kind {
        case junk(Set<JunkRule.Group>)
        case leftovers
        case largeFiles
        case footprint(InstalledApp)
    }

    enum Phase: Equatable {
        case idle
        case scanning(String, Double)
        case results
        case cleaning(Double)
        case done(freed: Int64, failed: Int)
    }

    let kind: Kind
    weak var model: AppModel?
    var phase: Phase = .idle
    var items: [ScanItem] = []
    var selection: Set<String> = []
    var lastResults: [CleanupResult] = []
    var scannedAt: Date?

    init(kind: Kind) { self.kind = kind }

    var selectedItems: [ScanItem] { items.filter { selection.contains($0.id) && $0.inUseBy == nil } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    /// Items grouped by category, largest group first.
    var groups: [(String, [ScanItem])] {
        Dictionary(grouping: items, by: \.category)
            .map { ($0.key, $0.value.sorted { $0.size > $1.size }) }
            .sorted { $0.1.reduce(0) { $0 + $1.size } > $1.1.reduce(0) { $0 + $1.size } }
    }

    func scan() async {
        guard let model else { return }
        phase = .scanning("Starting…", 0)
        model.refreshAccess()
        let found: [ScanItem]
        switch kind {
        case .junk(let groups):
            let scanner = JunkScanner(
                rules: model.rules?.rules ?? [],
                environment: ScanEnvironment.current(),
                gate: model.gate,
                hasFullDiskAccess: model.hasFullDiskAccess
            )
            found = await scanner.scan(groups: groups) { p in
                Task { @MainActor in
                    if case .scanning = self.phase {
                        self.phase = .scanning(p.current, p.total > 0 ? Double(p.completed) / Double(p.total) : 0)
                    }
                }
            }
        case .leftovers:
            phase = .scanning("Listing installed apps…", 0.2)
            let apps = await AppInventory.scan(measure: false)
            phase = .scanning("Looking for files of deleted apps…", 0.6)
            let finder = LeftoversFinder.live(installed: apps)
            found = await Task.detached { finder.scan() }.value
        case .largeFiles:
            phase = .scanning("Looking through your folders…", 0.3)
            let exclusions = model.exclusions
            found = await Task.detached {
                LargeFilesFinder().scan().filter { item in
                    !exclusions.contains { item.url?.path.hasPrefix(($0 as NSString).expandingTildeInPath) == true }
                }
            }.value
        case .footprint(let app):
            phase = .scanning("Finding \(app.name)'s files…", 0.5)
            found = await Task.detached { FootprintFinder().footprint(of: app) }.value
        }
        items = found
        selection = Set(found.filter(\.selectedByDefault).map(\.id))
        scannedAt = Date()
        phase = .results
    }

    func clean() async {
        guard let model else { return }
        let chosen = selectedItems
        guard !chosen.isEmpty else { return }
        phase = .cleaning(0)
        var gate = model.gate
        if case .footprint = kind { gate = gate.forUninstall }
        if case .leftovers = kind { gate = gate.forUninstall }
        let executor = CleanupExecutor(gate: gate)
        let results = await executor.clean(chosen) { done, total in
            Task { @MainActor in self.phase = .cleaning(total > 0 ? Double(done) / Double(total) : 1) }
        }
        lastResults = results
        let succeeded = Set(results.filter(\.succeeded).map(\.path))
        let freed = results.filter(\.succeeded).reduce(0) { $0 + $1.size }
        items.removeAll { item in succeeded.contains(item.url?.path ?? item.method.label) }
        selection = selection.intersection(Set(items.map(\.id)))
        phase = .done(freed: freed, failed: results.count - succeeded.count)
    }

    func toggle(_ item: ScanItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func setGroup(_ items: [ScanItem], selected: Bool) {
        for item in items where item.inUseBy == nil {
            if selected { selection.insert(item.id) } else { selection.remove(item.id) }
        }
    }

    func reset() {
        phase = .idle
        items = []
        selection = []
    }
}

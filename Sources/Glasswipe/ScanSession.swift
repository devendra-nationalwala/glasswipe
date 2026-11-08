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
    /// Rules still being measured while early results are already shown.
    var stillMeasuring: String?
    /// True when the user stopped the last Scan before it finished.
    var stoppedEarly = false
    /// Bumped by every Scan and by `stopScan()`, so results from an abandoned Scan are ignored.
    private var generation = 0
    private var work: Task<[ScanItem], Never>?

    init(kind: Kind) { self.kind = kind }

    var selectedItems: [ScanItem] { items.filter { selection.contains($0.id) && $0.inUseBy == nil } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    /// Whether this kind of Scan shows results while it runs, so it can be stopped part-way.
    /// An app's footprint is never cut short: uninstalling half of it would leave files behind.
    var canStopEarly: Bool {
        switch kind {
        case .junk, .largeFiles: true
        case .leftovers, .footprint: false
        }
    }

    /// True while a Scan is running and stopping it would keep useful results.
    var isStoppable: Bool {
        guard canStopEarly else { return false }
        if case .scanning = phase { return true }
        return stillMeasuring != nil
    }

    /// Items grouped by category, largest group first.
    var groups: [(String, [ScanItem])] {
        Dictionary(grouping: items, by: \.category)
            .map { ($0.key, $0.value.sorted { $0.size > $1.size }) }
            .sorted { $0.1.reduce(0) { $0 + $1.size } > $1.1.reduce(0) { $0 + $1.size } }
    }

    func scan() async {
        guard let model else { return }
        if Demo.isOn, case .junk = kind { return }
        generation += 1
        let current = generation
        stoppedEarly = false
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
            items = []
            selection = []
            let task = Task { await scanner.scan(groups: groups, progress: { p in
                Task { @MainActor in
                    guard current == self.generation else { return }
                    let remaining = p.total - p.completed
                    if case .scanning = self.phase {
                        self.phase = .scanning(p.current, p.total > 0 ? Double(p.completed) / Double(p.total) : 0)
                    }
                    self.stillMeasuring = remaining > 0 ? "Still measuring \(remaining) more…" : nil
                }
            }, found: { early in
                Task { @MainActor in self.add(early, scan: current) }
            }) }
            work = task
            found = await task.value
        case .leftovers:
            phase = .scanning("Listing installed apps…", 0.2)
            let apps = await AppInventory.scan(measure: false)
            phase = .scanning("Looking for files of deleted apps…", 0.6)
            let finder = LeftoversFinder.live(installed: apps)
            found = await Task.detached { finder.scan() }.value
        case .largeFiles:
            items = []
            selection = []
            phase = .scanning("Looking through your folders…", 0.3)
            let exclusions = model.exclusions
            let isExcluded: @Sendable (ScanItem) -> Bool = { item in
                exclusions.contains { item.url?.path.hasPrefix(($0 as NSString).expandingTildeInPath) == true }
            }
            let task = Task.detached {
                LargeFilesFinder().scan(found: { item in
                    guard !isExcluded(item) else { return }
                    Task { @MainActor in
                        self.add([item], scan: current)
                        if current == self.generation { self.stillMeasuring = "Still looking through your folders…" }
                    }
                }).filter { !isExcluded($0) }
            }
            work = task
            found = await task.value
        case .footprint(let app):
            phase = .scanning("Finding \(app.name)'s files…", 0.5)
            found = await Task.detached { FootprintFinder().footprint(of: app) }.value
        }
        // Stopped early, or replaced by a newer Scan: keep what is on screen.
        guard current == generation else { return }
        work = nil
        // Keep choices the user made on early results.
        let earlier = Set(items.map(\.id))
        let userSelection = selection
        items = found
        selection = Set(found.filter { earlier.contains($0.id) ? userSelection.contains($0.id) : $0.selectedByDefault }.map(\.id))
        stillMeasuring = nil
        scannedAt = Date()
        phase = .results
    }

    /// Adds results that arrived while a Scan is still running, unless that Scan was stopped or replaced.
    private func add(_ early: [ScanItem], scan: Int) {
        guard scan == generation else { return }
        let known = Set(items.map(\.id))
        let fresh = early.filter { !known.contains($0.id) }
        items = (items + fresh).sorted { $0.size > $1.size }
        selection.formUnion(fresh.filter(\.selectedByDefault).map(\.id))
        if case .scanning = phase { phase = .results }
    }

    /// Stops a running Scan and keeps what it has found so far, so the user can clean up without waiting.
    /// Locations that hadn't finished measuring are left out; the next Scan checks them again.
    func stopScan() {
        guard isStoppable else { return }
        generation += 1
        work?.cancel()
        work = nil
        stillMeasuring = nil
        stoppedEarly = true
        scannedAt = Date()
        phase = .results
    }

    func clean() async {
        // Demo mode never removes anything.
        guard let model, !Demo.isOn else { return }
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
        generation += 1
        work?.cancel()
        work = nil
        stillMeasuring = nil
        stoppedEarly = false
        phase = .idle
        items = []
        selection = []
    }
}

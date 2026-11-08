import AppKit
import GlasswipeCore
import Observation
import SwiftUI
import UserNotifications

/// Sidebar destinations.
enum Module: String, CaseIterable, Identifiable, Hashable {
    case overview, storage, developer, memory, uninstaller, leftovers, startup, spaceLens, largeFiles, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .storage: "Storage Cleaner"
        case .developer: "Developer Junk"
        case .memory: "Memory Cleaner"
        case .uninstaller: "Uninstaller"
        case .leftovers: "Leftovers"
        case .startup: "Startup Items"
        case .spaceLens: "Space Lens"
        case .largeFiles: "Large & Old Files"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "sparkles"
        case .storage: "externaldrive.badge.minus"
        case .developer: "hammer"
        case .memory: "memorychip"
        case .uninstaller: "trash.square"
        case .leftovers: "shippingbox"
        case .startup: "power.circle"
        case .spaceLens: "square.grid.3x3.square"
        case .largeFiles: "doc.badge.clock"
        case .history: "clock.arrow.circlepath"
        }
    }

    static let sections: [(String, [Module])] = [
        ("", [.overview]),
        ("Clean", [.storage, .developer, .memory]),
        ("Apps", [.uninstaller, .leftovers, .startup]),
        ("Files", [.spaceLens, .largeFiles]),
        ("", [.history]),
    ]
}

/// App-wide state shared by the main window, menu bar and settings.
@MainActor
@Observable
final class AppModel {
    var selection: Module? = .overview
    var hasFullDiskAccess = FullDiskAccess.isGranted()
    let rules: JunkRuleSet?

    var memory = MemorySampler.sample()
    var memoryHistory: [MemorySnapshot] = []
    var stats: SystemStats?
    private let statsSampler = SystemStatsSampler()
    private var timer: Timer?
    private var lastAlertLevel: MemorySnapshot.PressureLevel = .normal

    /// Paths the user never wants scanned.
    var exclusions: [String] {
        didSet { UserDefaults.standard.set(exclusions, forKey: "exclusions") }
    }

    var alertOnCriticalPressure: Bool {
        didSet { UserDefaults.standard.set(alertOnCriticalPressure, forKey: "alertOnCriticalPressure") }
    }

    let storage: ScanSession
    let developer: ScanSession
    let leftovers: ScanSession
    let largeFiles: ScanSession

    init() {
        rules = JunkRuleSet.bundled()
        exclusions = UserDefaults.standard.stringArray(forKey: "exclusions") ?? []
        alertOnCriticalPressure = UserDefaults.standard.object(forKey: "alertOnCriticalPressure") as? Bool ?? true
        storage = ScanSession(kind: .junk([.system, .browser, .largeDownloads]))
        developer = ScanSession(kind: .junk([.developer]))
        leftovers = ScanSession(kind: .leftovers)
        largeFiles = ScanSession(kind: .largeFiles)
        for session in [storage, developer, leftovers, largeFiles] { session.model = self }
        startMonitoring()
    }

    /// The gate for Junk cleanup: fails closed if the rules did not load.
    var gate: SafetyGate { SafetyGate(exclusions: exclusions, rulesLoaded: rules != nil) }

    func refreshAccess() { hasFullDiskAccess = FullDiskAccess.isGranted() }

    func startMonitoring() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        memory = MemorySampler.sample()
        memoryHistory.append(memory)
        if memoryHistory.count > 90 { memoryHistory.removeFirst(memoryHistory.count - 90) }
        stats = statsSampler.sample()
        if memory.level == .critical, lastAlertLevel != .critical, alertOnCriticalPressure { notifyCriticalPressure() }
        lastAlertLevel = memory.level
    }

    private func notifyCriticalPressure() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Memory pressure is critical"
            content.body = "Open Glasswipe's Memory Cleaner to see which apps are using the most memory."
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pressure", content: content, trigger: nil))
        }
    }

    func open(_ module: Module) {
        selection = module
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true || $0.title == "Glasswipe" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

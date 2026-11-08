import AppKit
import Foundation
import GlasswipeCore

/// `Glasswipe --report <junk|developer|leftovers|apps|large|startup|memory>` prints what a Scan would find
/// and exits. Read-only: nothing is removed.
enum Report {
    static var requested: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--report") else { return nil }
        return i + 1 < args.count ? args[i + 1] : "junk"
    }

    @MainActor
    static func run(_ kind: String) -> Never {
        let rules = JunkRuleSet.bundled()
        let gate = SafetyGate(exclusions: UserDefaults.standard.stringArray(forKey: "exclusions") ?? [], rulesLoaded: rules != nil)
        let environment = ScanEnvironment.current()
        let fda = FullDiskAccess.isGranted()
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached {
            var items: [ScanItem] = []
            var lines: [String] = []
            switch kind {
            case "junk", "developer":
                let groups: Set<JunkRule.Group> = kind == "junk" ? [.system, .browser, .largeDownloads] : [.developer]
                items = await JunkScanner(rules: rules?.rules ?? [], environment: environment, gate: gate, hasFullDiskAccess: fda)
                    .scan(groups: groups)
            case "leftovers":
                let apps = await AppInventory.scan(measure: false)
                items = await MainActor.run { LeftoversFinder.live(installed: apps) }.scan()
            case "large":
                items = LargeFilesFinder().scan()
            case "footprint":
                let args = CommandLine.arguments
                let query = args.count > args.firstIndex(of: "--report")! + 2 ? args[args.firstIndex(of: "--report")! + 2] : ""
                let apps = await AppInventory.scan(measure: false)
                if let app = apps.first(where: { $0.name.localizedCaseInsensitiveCompare(query) == .orderedSame || $0.bundleID == query }),
                   let measured = AppInventory.describe(app.url) {
                    items = FootprintFinder().footprint(of: measured)
                } else {
                    lines.append("No installed app named \(query)")
                }
            case "apps":
                for app in await AppInventory.scan() {
                    lines.append("\(app.size.formattedBytes)\t\(app.name)\t\(app.bundleID)\tteam=\(app.teamID ?? "-")\tgroups=\(app.appGroups.joined(separator: ","))")
                }
            case "startup":
                for item in StartupItems.scan() {
                    lines.append("\(item.isEnabled ? "on " : "off")\t\(item.scope.rawValue)\t\(item.label)\(item.isBroken ? "\tBROKEN" : "")")
                }
            case "memory":
                let m = MemorySampler.sample()
                lines.append("pressure \(m.pressurePercent)% (\(m.level.rawValue)) app \(m.app.formattedBytes) wired \(m.wired.formattedBytes) compressed \(m.compressed.formattedBytes) swap \(m.swapUsed.formattedBytes)")
                for app in await MainActor.run(body: { AppMemory.usage() }).prefix(15) {
                    lines.append("\(app.footprint.formattedBytes)\t\(app.name)\t\(app.processCount) processes")
                }
            default:
                lines.append("Unknown report \(kind). Use junk, developer, leftovers, apps, large, startup, memory or footprint <app>.")
            }
            for item in items {
                let flags = [item.selectedByDefault ? "selected" : "unticked", item.inUseBy.map { "in use: \($0)" }]
                    .compactMap { $0 }.joined(separator: ", ")
                lines.append("\(item.size.formattedBytes)\t\(item.category)\t\(item.title)\t\(item.method.label)\t\(flags)\t\(item.url?.path ?? "")")
            }
            if !items.isEmpty {
                lines.append("Total \(items.reduce(0) { $0 + $1.size }.formattedBytes) in \(items.count) items; selected by default \(items.filter(\.selectedByDefault).reduce(0) { $0 + $1.size }.formattedBytes)")
            }
            box.set(lines)
            semaphore.signal()
        }
        while semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        print(box.get().joined(separator: "\n"))
        if !fda { print("(Full Disk Access is off; some locations were skipped.)") }
        exit(0)
    }
}

private final class ResultBox: @unchecked Sendable {
    private var lines: [String] = []
    private let lock = NSLock()
    func set(_ l: [String]) { lock.withLock { lines = l } }
    func get() -> [String] { lock.withLock { lines } }
}

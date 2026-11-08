import Foundation
import Synchronization
import Testing
@testable import GlasswipeCore

/// A throwaway home folder; removed when the test ends.
final class TempHome {
    let url: URL
    var path: String { url.path }

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("glasswipe-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func file(_ relative: String, bytes: Int = 8192, modified: Date? = nil) throws -> URL {
        let file = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: file)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path) }
        return file
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(relative).path)
    }
}

/// Records what a Cleanup would do without touching anything.
final class RecordingRemover: Remover, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var deleted: [String] = []
    private(set) var trashed: [String] = []
    private(set) var commands: [String] = []
    private(set) var admin: [String] = []

    func delete(_ url: URL) throws { lock.withLock { deleted.append(url.path) } }
    func trash(_ url: URL) throws { lock.withLock { trashed.append(url.path) } }
    func run(_ executable: String, _ arguments: [String]) throws { lock.withLock { commands.append(([executable] + arguments).joined(separator: " ")) } }
    func adminDelete(_ paths: [String]) throws { lock.withLock { admin += paths } }
}

func rulesFromSource() throws -> JunkRuleSet {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/GlasswipeCore/Resources/junk-rules.json")
    return try JunkRuleSet.load(from: url)
}

@Suite("Safety Gate")
struct SafetyGateTests {
    let gate = SafetyGate(home: "/Users/test")

    @Test("refuses protected locations", arguments: [
        "/", "/System/Library/Caches/x", "/usr/bin/ls", "/private/var/vm/swapfile0", "/private/var/db/diagnostics/x",
        "/Users/test", "/Users/test/Library", "/Users/test/Documents", "/Users/test/Library/Caches",
        "/Users/test/Library/Containers/com.foo.app", "/Users/test/Library/Containers/com.foo.app/Data",
        "/Users/test/Library/Group Containers/ABC.group", "/Library/Updates/123",
        "/Users/test/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
        "/Applications", "/opt/homebrew/Cellar/wget/1.0", "/Users/test/repos/app/.git/objects",
    ])
    func refuses(_ path: String) {
        #expect(!gate.allows(URL(fileURLWithPath: path)))
    }

    @Test("allows ordinary Junk", arguments: [
        "/Users/test/Library/Caches/com.foo.app",
        "/Users/test/Library/Caches/com.foo.app/data.db",
        "/Users/test/Library/Containers/com.foo.app/Data/Library/Caches/x",
        "/Users/test/repos/web/node_modules",
        "/Applications/Foo.app",
    ])
    func allows(_ path: String) {
        #expect(gate.allows(URL(fileURLWithPath: path)))
    }

    @Test func failsClosedWithoutRules() {
        let closed = SafetyGate(home: "/Users/test", rulesLoaded: false)
        #expect(throws: SafetyGate.Refusal.rulesUnavailable) {
            try closed.check(URL(fileURLWithPath: "/Users/test/Library/Caches/com.foo.app"))
        }
    }

    @Test func honoursUserExclusions() {
        let g = SafetyGate(home: "/Users/test", exclusions: ["/Users/test/Library/Caches/com.keep"])
        #expect(!g.allows(URL(fileURLWithPath: "/Users/test/Library/Caches/com.keep/file")))
        #expect(g.allows(URL(fileURLWithPath: "/Users/test/Library/Caches/com.other")))
    }

    @Test func uninstallMayRemoveWholeContainers() {
        let container = URL(fileURLWithPath: "/Users/test/Library/Containers/com.foo.app")
        #expect(!gate.allows(container))
        #expect(gate.forUninstall.allows(container))
        #expect(!gate.forUninstall.allows(URL(fileURLWithPath: "/Users/test/Library/Containers")))
    }

    @Test func refusesSymlinksThatEscape() throws {
        let home = try TempHome()
        let outside = try home.file("outside/secret.txt")
        let caches = home.url.appendingPathComponent("Library/Caches/com.foo")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let link = caches.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let g = SafetyGate(home: home.path)
        #expect(throws: SafetyGate.Refusal.self) { try g.check(link, scannedRoot: caches) }
    }
}

@Suite("Junk rules")
struct JunkRuleTests {
    @Test func bundledRulesDecode() throws {
        let set = try rulesFromSource()
        #expect(set.rules.count > 20)
        #expect(Set(set.rules.map(\.id)).count == set.rules.count, "rule ids must be unique")
    }

    @Test func noRuleTargetsAProtectedLocation() throws {
        let gate = SafetyGate(home: "/Users/test")
        for rule in try rulesFromSource().rules {
            for pattern in rule.paths ?? [] {
                let path = pattern.replacingOccurrences(of: "~", with: "/Users/test")
                    .replacingOccurrences(of: "$TMPDIR", with: "/private/var/folders/xx/T")
                    .replacingOccurrences(of: "*", with: "sample")
                let target = rule.contentsOnly == true ? path + "/child" : path
                #expect(gate.allows(URL(fileURLWithPath: target)), "\(rule.id): \(pattern)")
            }
        }
    }

    @Test func dangerousRulesOnlyUseTheirTool() throws {
        let rules = try rulesFromSource().rules
        for id in ["docker", "uv-cache", "unavailable-simulators"] {
            let rule = try #require(rules.first { $0.id == id })
            #expect(rule.toolOnly == true, "\(id) must never fall back to deleting files")
        }
    }

    @Test func globMatchesOneComponent() throws {
        let home = try TempHome()
        try home.file("Library/Caches/com.a/x")
        try home.file("Library/Caches/com.b/y")
        let found = Glob.expand(home.path + "/Library/Caches/*").map(\.lastPathComponent).sorted()
        #expect(found == ["com.a", "com.b"])
    }
}

@Suite("Junk scanner")
struct JunkScannerTests {
    func scanner(_ home: TempHome, rules: [JunkRule], running: Set<String> = []) -> JunkScanner {
        JunkScanner(
            rules: rules,
            environment: ScanEnvironment(home: home.path, tmpDir: home.path + "/tmp", runningBundleIDs: running),
            gate: SafetyGate(home: home.path),
            hasFullDiskAccess: false
        )
    }

    @Test func findsCachesAndPreselectsSafeOnes() async throws {
        let home = try TempHome()
        try home.file("Library/Caches/com.vendor.tool/blob", bytes: 100_000)
        let rules = try rulesFromSource().rules.filter { $0.id == "user-caches" }
        let items = await scanner(home, rules: rules).scan()
        let item = try #require(items.first)
        #expect(item.title == "com.vendor.tool")
        #expect(item.selectedByDefault)
        #expect(item.contentsOnly)
        #expect(item.size >= 100_000)
    }

    @Test func cancelledScanReportsNoPartlyMeasuredItems() async throws {
        let home = try TempHome()
        try home.file("Library/Caches/com.vendor.tool/blob", bytes: 100_000)
        let rules = try rulesFromSource().rules.filter { $0.id == "user-caches" }
        let s = scanner(home, rules: rules)
        let task = Task { await s.scan() }
        task.cancel()
        let items = await task.value
        #expect(items.allSatisfy { $0.size >= 100_000 }, "a stopped Scan keeps only fully measured items")
    }

    @Test func marksCachesOfRunningAppsAsInUse() async throws {
        let home = try TempHome()
        try home.file("Library/Caches/com.vendor.running/blob")
        let rules = try rulesFromSource().rules.filter { $0.id == "user-caches" }
        let items = await scanner(home, rules: rules, running: ["com.vendor.running"]).scan()
        #expect(items.first?.inUseBy == "com.vendor.running")
        #expect(items.first?.selectedByDefault == false)
    }

    @Test func marksCachesNamedAfterRunningAppsAsInUse() async throws {
        let home = try TempHome()
        try home.file("Library/Caches/Comet/blob")
        let rules = try rulesFromSource().rules.filter { $0.id == "user-caches" }
        var env = ScanEnvironment(home: home.path, tmpDir: home.path + "/tmp")
        env.runningAppNames = ["comet"]
        let items = await JunkScanner(rules: rules, environment: env, gate: SafetyGate(home: home.path), hasFullDiskAccess: false).scan()
        #expect(items.first?.inUseBy == "Comet")
    }

    @Test func skipsAppleCaches() async throws {
        let home = try TempHome()
        try home.file("Library/Caches/com.apple.Safari/blob")
        let rules = try rulesFromSource().rules.filter { $0.id == "user-caches" }
        #expect(await scanner(home, rules: rules).scan().isEmpty)
    }

    @Test func respectsMinimumAge() async throws {
        let home = try TempHome()
        try home.file("Library/Logs/DiagnosticReports/old.ips", modified: Date().addingTimeInterval(-60 * 86_400))
        try home.file("Library/Logs/DiagnosticReports/new.ips")
        let rules = try rulesFromSource().rules.filter { $0.id == "crash-reports" }
        let items = await scanner(home, rules: rules).scan()
        #expect(items.map(\.url?.lastPathComponent) == ["old.ips"])
    }

    @Test func findsNodeModulesOnlyBesidePackageJSON() async throws {
        let home = try TempHome()
        try home.file("repos/web/package.json", bytes: 10)
        try home.file("repos/web/node_modules/left-pad/index.js")
        try home.file("repos/notnode/node_modules/x")
        let rules = try rulesFromSource().rules.filter { $0.id == "node-modules" }
        let items = await scanner(home, rules: rules).scan()
        #expect(items.count == 1)
        #expect(items.first?.url?.path.hasSuffix("repos/web/node_modules") == true)
    }

    @Test func toolOnlyRulesNeedTheTool() async throws {
        let home = try TempHome()
        try home.file(".cache/uv/wheels/x", bytes: 50_000)
        let rules = try rulesFromSource().rules.filter { $0.id == "uv-cache" }
        // No tool search paths, so uv is "not installed": nothing is offered.
        #expect(await scanner(home, rules: rules).scan().isEmpty)
    }

    @Test func fullDiskAccessRulesNeedAccess() async throws {
        let home = try TempHome()
        try home.file(".Trash/old.zip")
        let rules = try rulesFromSource().rules.filter { $0.id == "trash" }
        #expect(await scanner(home, rules: rules).scan().isEmpty)
    }
}

@Suite("Cleanup")
struct CleanupTests {
    @Test func deletesContentsButKeepsTheFolder() async throws {
        let home = try TempHome()
        try home.file("Library/Caches/com.vendor.tool/a")
        try home.file("Library/Caches/com.vendor.tool/b/c")
        let folder = home.url.appendingPathComponent("Library/Caches/com.vendor.tool")
        let item = ScanItem(url: folder, title: "tool", category: "System Junk", tier: .safe, method: .delete,
                            size: 1, contentsOnly: true)
        let executor = CleanupExecutor(gate: SafetyGate(home: home.path), log: nil)
        let results = await executor.clean([item])
        #expect(results.allSatisfy { $0.succeeded })
        #expect(home.exists("Library/Caches/com.vendor.tool"))
        #expect(!home.exists("Library/Caches/com.vendor.tool/a"))
        #expect(!home.exists("Library/Caches/com.vendor.tool/b"))
    }

    @Test func refusesProtectedPathsEvenIfAsked() async throws {
        let home = try TempHome()
        try home.file("Documents/thesis.pdf")
        let item = ScanItem(url: home.url.appendingPathComponent("Documents"), title: "Documents", category: "x",
                            tier: .safe, method: .delete, size: 1)
        let remover = RecordingRemover()
        let results = await CleanupExecutor(gate: SafetyGate(home: home.path), remover: remover, log: nil).clean([item])
        #expect(results.first?.succeeded == false)
        #expect(remover.deleted.isEmpty)
        #expect(home.exists("Documents/thesis.pdf"))
    }

    @Test func routesEachMethod() async throws {
        let home = try TempHome()
        let a = try home.file("Library/Caches/com.a/x")
        let b = try home.file("Downloads/big.dmg")
        let c = try home.file("sys/Library/Caches/com.c/x")
        let items = [
            ScanItem(url: a, title: "a", category: "x", tier: .safe, method: .delete, size: 1),
            ScanItem(url: b, title: "b", category: "x", tier: .caution, method: .trash, size: 1),
            ScanItem(url: nil, title: "brew", category: "x", tier: .safe, method: .toolCommand(executable: "/opt/homebrew/bin/brew", arguments: ["cleanup"]), size: 1),
            ScanItem(url: c, title: "c", category: "x", tier: .caution, method: .adminDelete, size: 1),
            ScanItem(url: a, title: "busy", category: "x", tier: .safe, method: .delete, size: 1, inUseBy: "Chrome"),
        ]
        let remover = RecordingRemover()
        let results = await CleanupExecutor(gate: SafetyGate(home: home.path), remover: remover, log: nil).clean(items)
        #expect(remover.deleted == [a.path])
        #expect(remover.trashed == [b.path])
        #expect(remover.commands == ["/opt/homebrew/bin/brew cleanup"])
        #expect(remover.admin == [c.path])
        #expect(results.filter { !$0.succeeded }.map(\.title) == ["busy"])
    }

    @Test func logsEveryResult() async throws {
        let home = try TempHome()
        let file = try home.file("Library/Caches/com.a/x")
        let log = CleanupLog(url: home.url.appendingPathComponent("log.jsonl"))
        let item = ScanItem(url: file, title: "a", category: "x", tier: .safe, method: .delete, size: 42)
        _ = await CleanupExecutor(gate: SafetyGate(home: home.path), remover: RecordingRemover(), log: log).clean([item])
        let entries = log.read()
        #expect(entries.count == 1)
        #expect(entries.first?.size == 42)
    }
}

@Suite("App Footprint and Leftovers")
struct AppFootprintTests {
    func app(_ home: TempHome, id: String, name: String, groups: [String] = []) throws -> InstalledApp {
        let bundle = try home.file("Applications/\(name).app/Contents/MacOS/\(name)")
        return InstalledApp(url: bundle.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
                            name: name, bundleID: id, version: "1.0", nestedBundleIDs: [id + ".helper"],
                            teamID: "TEAM123456", appGroups: groups, size: 1000, lastUsed: nil)
    }

    @Test func matchesExactIdentifiersNotSubstrings() throws {
        let home = try TempHome()
        let code = try app(home, id: "com.microsoft.VSCode", name: "Code", groups: ["UBF8T346G9.com.microsoft.VSCode"])
        try home.file("Library/Application Support/com.microsoft.VSCode/state")
        try home.file("Library/Preferences/com.microsoft.VSCode.plist")
        try home.file("Library/Caches/com.microsoft.VSCode.helper/x")
        try home.file("Library/Group Containers/UBF8T346G9.com.microsoft.VSCode/x")
        try home.file("Library/Application Support/Code/User/settings.json")
        // Must never match: different apps whose names contain "Code".
        try home.file("Library/Application Support/com.openai.codex/x")
        try home.file("Library/Preferences/com.googlecode.iterm2.plist")

        let items = FootprintFinder(home: home.path, systemRoot: home.path + "/sys").footprint(of: code)
        let paths = Set(items.compactMap { $0.url?.lastPathComponent })
        #expect(paths.contains("com.microsoft.VSCode"))
        #expect(paths.contains("com.microsoft.VSCode.plist"))
        #expect(paths.contains("com.microsoft.VSCode.helper"))
        #expect(paths.contains("UBF8T346G9.com.microsoft.VSCode"))
        #expect(!paths.contains("com.openai.codex"))
        #expect(!paths.contains("com.googlecode.iterm2.plist"))

        let nameMatch = try #require(items.first { $0.url?.path.hasSuffix("Application Support/Code") == true })
        #expect(nameMatch.selectedByDefault == false, "name-only matches must be opt-in")
        #expect(items.first?.url == code.url, "the app bundle comes first")
    }

    @Test func identifierParsing() {
        #expect(LeftoversFinder.identifier(from: "com.vendor.App.plist") == "com.vendor.App")
        #expect(LeftoversFinder.identifier(from: "com.vendor.App.savedState") == "com.vendor.App")
        #expect(LeftoversFinder.identifier(from: "Google") == nil)
        #expect(LeftoversFinder.identifier(from: "6A3B1F5E-1111-2222-3333-444455556666") == nil)
        #expect(LeftoversFinder.isApple("com.apple.Safari"))
        #expect(LeftoversFinder.isApple("group.com.apple.notes"))
        #expect(!LeftoversFinder.isApple("com.vendor.App"))
        #expect(LeftoversFinder.identifier(from: "warp.log.old.0") == nil)
        #expect(LeftoversFinder.isApple("group.is.workflow.shortcuts"))
        #expect(LeftoversFinder.isApple("243LU875E5.groups.com.apple.podcasts"))
        #expect(LeftoversFinder.vendor(of: "group.com.vendor.app") == "com.vendor")
        #expect(LeftoversFinder.identifier(from: "ABCDE12345.com.vendor.shared") == "ABCDE12345.com.vendor.shared")
    }

    @Test func workingLaunchAgentsAreNotLeftovers() throws {
        let home = try TempHome()
        let program = try home.file("bin/tool")
        for (name, target) in [("com.tool.working", program.path), ("com.tool.broken", "/nonexistent/tool")] {
            let plist = home.url.appendingPathComponent("Library/LaunchAgents/\(name).plist")
            try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: ["Label": name, "Program": target], format: .xml, options: 0)
            try data.write(to: plist)
        }
        let items = LeftoversFinder(home: home.path) { _ in false }.scan()
        #expect(items.map(\.category) == ["com.tool.broken"])
    }

    @Test func leftoversAreUninstalledAppsOnly() throws {
        let home = try TempHome()
        try home.file("Library/Application Support/com.gone.App/data")
        try home.file("Library/Preferences/com.gone.App.plist")
        try home.file("Library/Preferences/com.here.App.plist")
        try home.file("Library/Preferences/com.apple.dock.plist")
        let finder = LeftoversFinder(home: home.path) { $0.hasPrefix("com.here") }
        let items = finder.scan()
        #expect(Set(items.map(\.category)) == ["com.gone.App"])
        #expect(items.count == 2)
        #expect(items.allSatisfy { !$0.selectedByDefault })
    }
}

@Suite("Startup Items and memory")
struct SystemTests {
    @Test func parsesLaunchctlDisabledList() {
        let text = """
        disabled services = {
            "com.vendor.agent" => disabled
            "com.vendor.other" => enabled
            "com.old.style" => true
        }
        """
        let parsed = StartupItems.parseDisabled(text)
        #expect(parsed["com.vendor.agent"] == true)
        #expect(parsed["com.vendor.other"] == false)
        #expect(parsed["com.old.style"] == true)
    }

    @Test func memorySnapshotIsPlausible() {
        let s = MemorySampler.sample()
        #expect(s.total > 1_000_000_000)
        #expect((0...100).contains(s.pressurePercent))
        #expect(s.used <= s.total)
    }

    @Test func processListSeesItself() {
        let me = ProcessInfo.processInfo.processIdentifier
        #expect(ProcessList.all().contains { $0.pid == me && $0.footprint > 0 })
    }

    @Test func largeFilesFinderFindsBigAndOld() throws {
        let home = try TempHome()
        try home.file("Downloads/big.iso", bytes: 3_000_000)
        try home.file("Documents/old.zip", bytes: 200_000, modified: Date().addingTimeInterval(-400 * 86_400))
        try home.file("Documents/small.txt", bytes: 10)
        try home.file("Library/huge.bin", bytes: 3_000_000)
        let finder = LargeFilesFinder(roots: [home.url], minimumSize: 1_000_000, oldAfterDays: 365, minimumOldSize: 100_000)
        let names = Set(finder.scan().map(\.title))
        #expect(names.contains("big.iso"))
        #expect(!names.contains("small.txt"))
        #expect(!names.contains("huge.bin"), "Library is never scanned")
    }

    @Test func largeFilesFinderReportsEachMatchAsItIsFound() throws {
        let home = try TempHome()
        try home.file("Downloads/a.iso", bytes: 2_000_000)
        try home.file("Downloads/b.iso", bytes: 2_000_000)
        let streamed = Mutex<[String]>([])
        let finder = LargeFilesFinder(roots: [home.url], minimumSize: 1_000_000)
        let items = finder.scan(found: { item in streamed.withLock { $0.append(item.title) } })
        #expect(Set(streamed.withLock { $0 }) == Set(items.map(\.title)))
        #expect(items.count == 2)
    }
}

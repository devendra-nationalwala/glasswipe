import AppKit
import Darwin
import Foundation

/// One reading of system memory. All sizes in bytes.
public struct MemorySnapshot: Sendable, Equatable {
    public enum PressureLevel: String, Sendable { case normal, warning, critical }

    public let total: UInt64
    /// Memory used by apps (anonymous, non-purgeable).
    public let app: UInt64
    public let wired: UInt64
    /// Physical memory occupied by the compressor.
    public let compressed: UInt64
    /// File cache macOS can drop instantly; not a problem.
    public let cached: UInt64
    public let free: UInt64
    public let swapUsed: UInt64
    /// Percentage of memory the kernel considers available (kern.memorystatus_level).
    public let availablePercent: Int
    public let level: PressureLevel
    public let date: Date

    /// 0…100, how much pressure the system is under.
    public var pressurePercent: Int { max(0, min(100, 100 - availablePercent)) }
    public var used: UInt64 { app + wired + compressed }
}

public enum MemorySampler {
    public static func sample() -> MemorySnapshot {
        let pageSize = sysctlUInt64("hw.pagesize") ?? 16_384
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        _ = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = sysctlUInt64("hw.memsize") ?? 0
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (internalPages > purgeable ? internalPages - purgeable : 0) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let cached = (UInt64(stats.external_page_count) + purgeable) * pageSize
        let free = (UInt64(stats.free_count) + UInt64(stats.speculative_count)) * pageSize

        var available = Int(sysctlUInt64("kern.memorystatus_level") ?? 0)
        if available == 0, total > 0 {
            let pages = UInt64(stats.active_count) + UInt64(stats.inactive_count) + UInt64(stats.free_count) + UInt64(stats.speculative_count)
            available = Int(pages * pageSize * 100 / total)
        }
        let rawLevel = sysctlUInt64("kern.memorystatus_vm_pressure_level") ?? 1
        let level: MemorySnapshot.PressureLevel = rawLevel >= 4 ? .critical : rawLevel >= 2 ? .warning : .normal

        return MemorySnapshot(
            total: total, app: app, wired: wired, compressed: compressed, cached: cached, free: free,
            swapUsed: swapUsed(), availablePercent: available, level: level, date: Date()
        )
    }

    static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    static func sysctlUInt64(_ name: String) -> UInt64? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        if size == MemoryLayout<UInt32>.size {
            var value: UInt32 = 0
            guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
            return UInt64(value)
        }
        var value: UInt64 = 0
        size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}

/// A running app together with all of its helper processes.
public struct AppMemoryUsage: Identifiable, Sendable, Hashable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let name: String
    public let bundleID: String?
    public let bundleURL: URL?
    public let footprint: UInt64
    public let processCount: Int
    public let isActive: Bool
    public let isBackgroundCandidate: Bool
}

public enum AppMemory {
    /// Running regular apps, each with helpers rolled up by bundle containment, largest first.
    @MainActor
    public static func usage() -> [AppMemoryUsage] {
        let processes = ProcessList.all()
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        return apps.compactMap { app -> AppMemoryUsage? in
            guard let bundleURL = app.bundleURL else { return nil }
            let prefix = bundleURL.path + "/"
            let members = processes.filter { $0.pid == app.processIdentifier || $0.path.hasPrefix(prefix) }
            let footprint = members.reduce(UInt64(0)) { $0 + $1.footprint }
            let protected = app.processIdentifier == me || app.bundleIdentifier == "com.apple.finder"
            return AppMemoryUsage(
                pid: app.processIdentifier,
                name: app.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent,
                bundleID: app.bundleIdentifier,
                bundleURL: bundleURL,
                footprint: footprint,
                processCount: members.count,
                isActive: app.isActive,
                isBackgroundCandidate: !app.isActive && !protected
            )
        }
        .sorted { $0.footprint > $1.footprint }
    }

    /// Apps "Free Up Memory" pre-selects: in the background and above the threshold.
    @MainActor
    public static func freeUpCandidates(threshold: UInt64 = 500 * 1_048_576) -> [AppMemoryUsage] {
        usage().filter { $0.isBackgroundCandidate && $0.footprint >= threshold }
    }

    public enum Action: Sendable { case quit, forceQuit, relaunch }

    @MainActor
    public static func perform(_ action: Action, on pid: pid_t) async -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        let bundleURL = app.bundleURL
        switch action {
        case .quit:
            return app.terminate()
        case .forceQuit:
            return app.forceTerminate()
        case .relaunch:
            guard app.terminate(), let bundleURL else { return false }
            for _ in 0..<100 where !app.isTerminated { try? await Task.sleep(for: .milliseconds(100)) }
            guard app.isTerminated else { return false }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            return (try? await NSWorkspace.shared.openApplication(at: bundleURL, configuration: config)) != nil
        }
    }
}

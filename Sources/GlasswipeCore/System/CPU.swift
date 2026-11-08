import AppKit
import Darwin
import Foundation

/// The processor this Mac has.
public struct CPUInfo: Sendable {
    public let name: String
    public let logicalCores: Int
    public let performanceCores: Int
    public let efficiencyCores: Int

    public init(name: String, logicalCores: Int, performanceCores: Int, efficiencyCores: Int) {
        self.name = name
        self.logicalCores = logicalCores
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
    }

    public static let current = CPUInfo(
        name: Sysctl.string("machdep.cpu.brand_string") ?? "Unknown processor",
        logicalCores: Sysctl.int("hw.logicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount,
        performanceCores: Sysctl.int("hw.perflevel0.logicalcpu") ?? 0,
        efficiencyCores: Sysctl.int("hw.perflevel1.logicalcpu") ?? 0
    )
}

/// System-wide CPU load at one moment.
public struct CPUSnapshot: Sendable {
    public enum Thermal: String, Sendable {
        case nominal, fair, serious, critical

        init(_ state: ProcessInfo.ThermalState) {
            switch state {
            case .fair: self = .fair
            case .serious: self = .serious
            case .critical: self = .critical
            default: self = .nominal
            }
        }
    }

    /// Percent of all cores, 0–100.
    public let user: Double
    public let system: Double
    /// Busy percent of each core, 0–100, in the order macOS numbers them.
    public let cores: [Double]
    /// Average number of runnable threads over 1, 5 and 15 minutes.
    public let loadAverage: [Double]
    public let thermal: Thermal
    public let uptime: TimeInterval

    public var total: Double { min(100, user + system) }

    public init(user: Double, system: Double, cores: [Double], loadAverage: [Double], thermal: Thermal, uptime: TimeInterval) {
        self.user = user
        self.system = system
        self.cores = cores
        self.loadAverage = loadAverage
        self.thermal = thermal
        self.uptime = uptime
    }
}

/// Keeps the previous per-core tick counts so load can be computed as a delta.
public final class CPUSampler: @unchecked Sendable {
    struct Ticks: Equatable {
        var user: UInt32, system: UInt32, idle: UInt32, nice: UInt32
    }

    private var previous: [Ticks] = []
    private let lock = NSLock()

    public init() {}

    public func sample() -> CPUSnapshot {
        let now = Self.coreTicks()
        let (user, system, cores) = lock.withLock {
            defer { previous = now }
            return Self.load(from: previous, to: now)
        }
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) != 3 { load = [0, 0, 0] }
        return CPUSnapshot(user: user, system: system, cores: cores, loadAverage: load,
                           thermal: .init(ProcessInfo.processInfo.thermalState),
                           uptime: ProcessInfo.processInfo.systemUptime)
    }

    /// Busy percentages between two tick readings. Counters wrap, so differences use wrapping arithmetic.
    static func load(from old: [Ticks], to new: [Ticks]) -> (user: Double, system: Double, cores: [Double]) {
        guard old.count == new.count, !new.isEmpty else { return (0, 0, new.map { _ in 0 }) }
        var user = 0.0, system = 0.0, all = 0.0
        let cores = zip(old, new).map { o, n -> Double in
            let u = Double(n.user &- o.user) + Double(n.nice &- o.nice)
            let s = Double(n.system &- o.system)
            let total = u + s + Double(n.idle &- o.idle)
            user += u
            system += s
            all += total
            return total > 0 ? (u + s) / total * 100 : 0
        }
        guard all > 0 else { return (0, 0, cores) }
        return (user / all * 100, system / all * 100, cores)
    }

    static func coreTicks() -> [Ticks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        return (0..<Int(count)).map { core in
            let base = core * Int(CPU_STATE_MAX)
            func ticks(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[base + Int(state)]) }
            return Ticks(user: ticks(CPU_STATE_USER), system: ticks(CPU_STATE_SYSTEM),
                         idle: ticks(CPU_STATE_IDLE), nice: ticks(CPU_STATE_NICE))
        }
    }
}

/// CPU used by one app (with its helpers) or one other process.
public struct AppCPUUsage: Identifiable, Sendable, Hashable {
    public var id: String { path }
    public let pid: pid_t
    public let name: String
    /// The app bundle, or the executable for a process that isn't part of an app.
    public let path: String
    /// True when `path` is an app bundle (which may be a background app with no Dock icon).
    public let isApp: Bool
    /// Percent of one core, as Activity Monitor shows it: two busy cores read 200%.
    public let percent: Double
    public let processCount: Int
    public let canQuit: Bool

    public init(pid: pid_t, name: String, path: String, isApp: Bool, percent: Double, processCount: Int, canQuit: Bool) {
        self.pid = pid
        self.name = name
        self.path = path
        self.isApp = isApp
        self.percent = percent
        self.processCount = processCount
        self.canQuit = canQuit
    }
}

/// Keeps each process's previous CPU time so usage can be computed as a delta.
@MainActor
public final class AppCPUSampler {
    private var previous: [pid_t: UInt64] = [:]
    private var previousTime: UInt64?

    public init() {}

    /// Apps (helpers rolled up by bundle containment) and other processes, busiest first.
    /// The first call has nothing to compare with, so every percentage is 0.
    public func sample() -> [AppCPUUsage] {
        let processes = ProcessList.all()
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = previousTime.map { now - $0 } ?? 0
        let percent = Dictionary(uniqueKeysWithValues: processes.map { p in
            (p.pid, Self.percent(previous: previous[p.pid], current: p.cpuTime, elapsed: elapsed))
        })
        previous = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0.cpuTime) })
        previousTime = now

        let me = ProcessInfo.processInfo.processIdentifier
        var claimed = Set<pid_t>()
        var rows: [AppCPUUsage] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleURL = app.bundleURL else { continue }
            let prefix = bundleURL.path + "/"
            let members = processes.filter { $0.pid == app.processIdentifier || $0.path.hasPrefix(prefix) }
            claimed.formUnion(members.map(\.pid))
            rows.append(AppCPUUsage(
                pid: app.processIdentifier,
                name: app.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent,
                path: bundleURL.path,
                isApp: true,
                percent: members.reduce(0) { $0 + (percent[$1.pid] ?? 0) },
                processCount: members.count,
                canQuit: app.processIdentifier != me && app.bundleIdentifier != "com.apple.finder"
            ))
        }
        // Everything else is grouped by the app bundle it lives in, so helpers of background apps roll up too.
        let others = Dictionary(grouping: processes.filter { !claimed.contains($0.pid) }) { Self.bundlePath(of: $0.path) ?? $0.path }
        for (path, members) in others {
            let isBundle = path.hasSuffix(".app")
            rows.append(AppCPUUsage(
                pid: members[0].pid,
                name: isBundle ? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent : members[0].name,
                path: path,
                isApp: isBundle,
                percent: members.reduce(0) { $0 + (percent[$1.pid] ?? 0) },
                processCount: members.count,
                canQuit: false
            ))
        }
        return rows.sorted { $0.percent > $1.percent }
    }

    /// The outermost app bundle containing an executable, e.g. `/Applications/X.app` for its helpers.
    nonisolated static func bundlePath(of executable: String) -> String? {
        guard let range = executable.range(of: ".app/") else { return nil }
        return String(executable[..<range.lowerBound]) + ".app"
    }

    /// Percent of one core used between two readings. A process that is new since the last reading counts as 0.
    nonisolated static func percent(previous: UInt64?, current: UInt64, elapsed: UInt64) -> Double {
        guard let previous, elapsed > 0, current >= previous else { return 0 }
        return Double(current - previous) / Double(elapsed) * 100
    }
}

enum Sysctl {
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func int(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}

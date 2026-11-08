import Darwin
import Foundation
import IOKit.ps

/// CPU, disk and battery readings for the menu bar monitor.
public struct SystemStats: Sendable {
    public let cpuPercent: Double
    public let diskFree: Int64
    public let diskTotal: Int64
    public let batteryPercent: Int?
    public let isCharging: Bool

    public init(cpuPercent: Double, diskFree: Int64, diskTotal: Int64, batteryPercent: Int?, isCharging: Bool) {
        self.cpuPercent = cpuPercent
        self.diskFree = diskFree
        self.diskTotal = diskTotal
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
    }
}

/// Keeps the previous CPU tick counts so usage can be computed as a delta.
public final class SystemStatsSampler: @unchecked Sendable {
    private var previous: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private let lock = NSLock()

    public init() {}

    public func sample() -> SystemStats {
        let volume = SpaceLens.volume()
        let battery = Self.battery()
        return SystemStats(
            cpuPercent: cpu(),
            diskFree: volume?.available ?? 0,
            diskTotal: volume?.total ?? 0,
            batteryPercent: battery?.0,
            isCharging: battery?.1 ?? false
        )
    }

    private func cpu() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let now = (user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
                   idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
        return lock.withLock {
            defer { previous = now }
            guard let p = previous else { return 0 }
            let busy = Double((now.user - p.user) + (now.system - p.system) + (now.nice - p.nice))
            let total = busy + Double(now.idle - p.idle)
            return total > 0 ? busy / total * 100 : 0
        }
    }

    static func battery() -> (Int, Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            return (current * 100 / max, charging)
        }
        return nil
    }
}

import Darwin
import Foundation

/// A running process owned by the current user, as seen through libproc.
public struct ProcessInfoSnapshot: Sendable, Hashable {
    public let pid: pid_t
    public let name: String
    public let path: String
    /// Physical memory footprint in bytes (what Activity Monitor calls "Memory").
    public let footprint: UInt64
    /// CPU time used since the process started, in nanoseconds.
    public let cpuTime: UInt64
}

public enum ProcessList {
    /// Every process this user can inspect. Other users' processes are skipped (they need root).
    public static func all() -> [ProcessInfoSnapshot] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let filled = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard filled > 0 else { return [] }
        return pids.prefix(Int(filled)).compactMap { pid in
            guard pid > 0, let path = path(of: pid) else { return nil }
            let usage = usage(of: pid)
            return ProcessInfoSnapshot(
                pid: pid,
                name: URL(fileURLWithPath: path).lastPathComponent,
                path: path,
                footprint: usage?.ri_phys_footprint ?? 0,
                cpuTime: usage.map { nanoseconds($0.ri_user_time + $0.ri_system_time) } ?? 0
            )
        }
    }

    public static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public static func footprint(of pid: pid_t) -> UInt64? {
        usage(of: pid)?.ri_phys_footprint
    }

    static func usage(of pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info : nil
    }

    /// rusage CPU times are in Mach time units, which are not nanoseconds on Apple silicon.
    static func nanoseconds(_ machTime: UInt64) -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        guard timebase.denom > 0 else { return machTime }
        return machTime * UInt64(timebase.numer) / UInt64(timebase.denom)
    }
}

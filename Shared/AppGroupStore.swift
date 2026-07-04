import Foundation

/// Shared key-value container backed by an App Group suite.
/// Both the main app target and the Widget Extension must be
/// members of the same App Group (configured in Signing & Capabilities).
public struct AppGroupStore {

    /// Replace this string with your team's App Group ID,
    /// e.g. "group.com.yourcompany.sysmon"
    private static let suiteName = "group.com.sysmon.shared"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    // MARK: - Keys

    private enum Key: String {
        case cpuPercent       = "stats.cpu.percent"
        case memoryPercent    = "stats.memory.percent"
        case memoryUsedGB     = "stats.memory.usedGB"
        case memoryTotalGB    = "stats.memory.totalGB"
        case lastUpdated      = "stats.lastUpdated"
        case userLoad         = "stats.cpu.user"
        case systemLoad       = "stats.cpu.system"
    }

    // MARK: - Write

    /// Persist a snapshot into the App Group store so widgets can read it.
    public static func save(_ snapshot: SystemSnapshot) {
        let d = defaults
        d?.set(snapshot.cpu.systemLoad,         forKey: Key.cpuPercent.rawValue)
        d?.set(snapshot.memory.usagePercentage, forKey: Key.memoryPercent.rawValue)
        d?.set(snapshot.memory.usedGB,          forKey: Key.memoryUsedGB.rawValue)
        d?.set(snapshot.memory.totalGB,         forKey: Key.memoryTotalGB.rawValue)
        d?.set(snapshot.timestamp.timeIntervalSince1970, forKey: Key.lastUpdated.rawValue)
        d?.set(snapshot.cpu.userLoad,           forKey: Key.userLoad.rawValue)
        d?.set(snapshot.cpu.systemCPULoad,      forKey: Key.systemLoad.rawValue)
        d?.synchronize()
    }

    // MARK: - Read

    /// Reconstruct the most recently persisted snapshot.
    public static var latestSnapshot: SystemSnapshot {
        let d = defaults
        let cpu = CPUStats(
            systemLoad:     d?.double(forKey: Key.cpuPercent.rawValue) ?? 0,
            userLoad:       d?.double(forKey: Key.userLoad.rawValue) ?? 0,
            systemCPULoad:  d?.double(forKey: Key.systemLoad.rawValue) ?? 0,
            niceLoad:       0
        )
        let mem = MemoryStats(
            totalBytes: UInt64((d?.double(forKey: Key.memoryTotalGB.rawValue) ?? 0) * 1_073_741_824),
            usedBytes:  UInt64((d?.double(forKey: Key.memoryUsedGB.rawValue)  ?? 0) * 1_073_741_824),
            wiredBytes: 0, activeBytes: 0, inactiveBytes: 0,
            freeBytes: 0, compressedBytes: 0
        )
        let ts = d?.double(forKey: Key.lastUpdated.rawValue) ?? 0
        let date = Date(timeIntervalSince1970: ts)
        return SystemSnapshot(cpu: cpu, memory: mem, timestamp: date)
    }
}
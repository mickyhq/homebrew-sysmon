import Foundation

/// Represents a snapshot of CPU utilization.
public struct CPUStats: Sendable {
    /// Overall CPU load as a percentage (0–100).
    public let systemLoad: Double
    /// CPU load attributed to user processes (0–100).
    public let userLoad: Double
    /// CPU load attributed to the system itself (0–100).
    public let systemCPULoad: Double
    /// Load attributed to nice'd processes (0–100).
    public let niceLoad: Double
    /// Total idle percentage (100 – systemLoad).
    public var idlePercentage: Double { max(0, 100.0 - systemLoad) }

    public init(systemLoad: Double, userLoad: Double, systemCPULoad: Double, niceLoad: Double) {
        self.systemLoad = min(100, max(0, systemLoad))
        self.userLoad = min(100, max(0, userLoad))
        self.systemCPULoad = min(100, max(0, systemCPULoad))
        self.niceLoad = min(100, max(0, niceLoad))
    }

    /// Convenience: all zeros.
    public static let zero = CPUStats(systemLoad: 0, userLoad: 0, systemCPULoad: 0, niceLoad: 0)
}

/// Represents a snapshot of memory utilization (in bytes).
public struct MemoryStats: Sendable {
    /// Total physical memory installed.
    public let totalBytes: UInt64
    /// Memory currently in use (wired + active + compressed).
    public let usedBytes: UInt64
    /// Memory wired down (cannot be paged out).
    public let wiredBytes: UInt64
    /// Memory currently marked active (recently used).
    public let activeBytes: UInt64
    /// Memory currently marked inactive (candidate for reclamation).
    public let inactiveBytes: UInt64
    /// Memory completely free / zero-filled.
    public let freeBytes: UInt64
    /// Compressed memory.
    public let compressedBytes: UInt64

    /// Usage percentage (0–100).
    public var usagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return min(100, (Double(usedBytes) / Double(totalBytes)) * 100.0)
    }

    /// Used memory in GB, formatted to one decimal place.
    public var usedGB: Double { Double(usedBytes) / 1_073_741_824.0 }
    /// Total memory in GB, formatted to one decimal place.
    public var totalGB: Double { Double(totalBytes) / 1_073_741_824.0 }

    public init(totalBytes: UInt64,
                usedBytes: UInt64,
                wiredBytes: UInt64,
                activeBytes: UInt64,
                inactiveBytes: UInt64,
                freeBytes: UInt64,
                compressedBytes: UInt64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.wiredBytes = wiredBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.freeBytes = freeBytes
        self.compressedBytes = compressedBytes
    }

    /// Convenience: all zeros.
    public static let zero = MemoryStats(
        totalBytes: 0, usedBytes: 0, wiredBytes: 0,
        activeBytes: 0, inactiveBytes: 0, freeBytes: 0, compressedBytes: 0
    )
}

/// Combined snapshot produced by the monitoring engine.
public struct SystemSnapshot: Sendable {
    public let cpu: CPUStats
    public let memory: MemoryStats
    public let timestamp: Date

    public init(cpu: CPUStats, memory: MemoryStats, timestamp: Date = Date()) {
        self.cpu = cpu
        self.memory = memory
        self.timestamp = timestamp
    }

    public static let zero = SystemSnapshot(cpu: .zero, memory: .zero)
}
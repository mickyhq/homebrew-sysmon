import Foundation
import Darwin

// MARK: - SystemMonitorEngine

/// A thread-safe engine that periodically samples CPU and memory stats
/// using only public, sandbox-safe host-level Mach APIs.
public final class SystemMonitorEngine: @unchecked Sendable {

    // MARK: Public interface

    /// The most recently fetched snapshot, or `nil` until the first sample completes.
    public private(set) var latestSnapshot: SystemSnapshot?

    /// Async stream of snapshots emitted at each sampling interval.
    public var snapshotStream: AsyncStream<SystemSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()

            // Send the most recent snapshot immediately if available.
            if let snap = latestSnapshot {
                continuation.yield(snap)
            }

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.continuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    /// Designated initializer.
    /// - Parameter sampleInterval: Seconds between samples. Default is 2.0.
    public init(sampleInterval: TimeInterval = 2.0) {
        self.sampleInterval = max(1.0, sampleInterval)
    }

    /// Start the sampling timer. Safe to call multiple times.
    public func start() {
        lock.lock()
        defer { lock.unlock() }

        guard isRunning == false else { return }
        isRunning = true

        // Take an immediate first sample.
        sample()

        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + sampleInterval, repeating: sampleInterval)
        timer?.setEventHandler { [weak self] in
            _ = self?.sampleNow()
        }
        timer?.resume()
    }

    /// Change how often snapshots are sampled without replacing the stream.
    public func updateSampleInterval(_ interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }

        sampleInterval = max(1.0, interval)
        guard isRunning else { return }

        timer?.schedule(
            deadline: .now() + sampleInterval,
            repeating: sampleInterval
        )
    }

    /// Stop the sampling timer. The latest snapshot remains available.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        timer?.cancel()
        timer = nil
        isRunning = false
    }

    /// Force an immediate sample now (thread-safe).
    public func sampleNow() -> SystemSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return sample()
    }

    deinit { stop() }

    // MARK: Private

    private var sampleInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.sysmon.engine", qos: .utility)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private var continuations: [UUID: AsyncStream<SystemSnapshot>.Continuation] = [:]
    private var previousCPUTicks: CPUTicks?

    private struct CPUTicks {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32
    }

    /// The lock must be held by the caller.
    @discardableResult
    private func sample() -> SystemSnapshot {
        let cpu = fetchCPUStats()
        let mem = fetchMemoryStats()
        let snapshot = SystemSnapshot(cpu: cpu, memory: mem)
        latestSnapshot = snapshot

        // Fan out to all registered AsyncStream continuations.
        for (_, continuation) in continuations {
            continuation.yield(snapshot)
        }

        return snapshot
    }

    // MARK: CPU sampling

    private func fetchCPUStats() -> CPUStats {
        var loadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &loadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return .zero
        }

        let current = CPUTicks(
            user: loadInfo.cpu_ticks.0,
            system: loadInfo.cpu_ticks.1,
            idle: loadInfo.cpu_ticks.2,
            nice: loadInfo.cpu_ticks.3
        )

        let ticks: CPUTicks
        if let previous = previousCPUTicks {
            ticks = CPUTicks(
                user: current.user &- previous.user,
                system: current.system &- previous.system,
                idle: current.idle &- previous.idle,
                nice: current.nice &- previous.nice
            )
        } else {
            ticks = current
        }
        previousCPUTicks = current

        let total = Double(
            UInt64(ticks.user)
                + UInt64(ticks.system)
                + UInt64(ticks.idle)
                + UInt64(ticks.nice)
        )
        guard total > 0 else { return .zero }

        let user = (Double(ticks.user) / total) * 100.0
        let system = (Double(ticks.system) / total) * 100.0
        let nice = (Double(ticks.nice) / total) * 100.0

        return CPUStats(
            systemLoad: user + system + nice,
            userLoad: user,
            systemCPULoad: system,
            niceLoad: nice
        )
    }

    // MARK: Memory sampling

    private func fetchMemoryStats() -> MemoryStats {
        // Total physical memory
        var physicalMemory: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &physicalMemory, &size, nil, 0)

        // VM statistics
        var vmStat = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryStats(
                totalBytes: physicalMemory,
                usedBytes: 0, wiredBytes: 0, activeBytes: 0,
                inactiveBytes: 0, freeBytes: 0, compressedBytes: 0
            )
        }

        let pageSize = UInt64(vm_kernel_page_size)

        let freePages    = UInt64(vmStat.free_count)     // completely free
        let activePages  = UInt64(vmStat.active_count)   // recently used, not reclaimable
        let inactivePages = UInt64(vmStat.inactive_count) // candidate for reclaim
        let wiredPages   = UInt64(vmStat.wire_count)      // cannot be paged out
        let compressedPages = UInt64(vmStat.compressor_page_count) // compressed

        let freeBytes    = freePages * pageSize
        let activeBytes  = activePages * pageSize
        let inactiveBytes = inactivePages * pageSize
        let wiredBytes   = wiredPages * pageSize
        let compressedBytes = compressedPages * pageSize

        // "Used" = wired + active + compressed (inactive can be reclaimed)
        let usedBytes = wiredBytes + activeBytes + compressedBytes

        return MemoryStats(
            totalBytes: physicalMemory,
            usedBytes: usedBytes,
            wiredBytes: wiredBytes,
            activeBytes: activeBytes,
            inactiveBytes: inactiveBytes,
            freeBytes: freeBytes,
            compressedBytes: compressedBytes
        )
    }
}

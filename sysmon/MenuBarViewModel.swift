import SwiftUI
import Combine

/// Which stat is displayed in the menu bar.
enum DisplayMode: String, CaseIterable {
    case cpu    = "CPU"
    case memory = "Memory"
    case both   = "Both"
}

/// Drives the menu bar UI by consuming snapshots from SystemMonitorEngine
/// and persisting them to the App Group store for widget consumption.
final class MenuBarViewModel: ObservableObject {

    // MARK: Published properties (driving SwiftUI updates)

    @Published var cpuPercentage: Double = 0
    @Published var memPercentage: Double = 0
    @Published var memUsedGB: Double = 0
    @Published var memTotalGB: Double = 0
    @Published var cpuUser: Double = 0
    @Published var cpuSystem: Double = 0
    @Published var lastUpdated: Date = .distantPast

    /// Controls which stat(s) appear in the menu bar label.
    @Published var displayMode: DisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: "DisplayMode")
        }
    }

    /// Refresh interval in seconds (1–10). Changing this restarts the engine.
    @Published var refreshInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "RefreshInterval")
            engine?.updateSampleInterval(refreshInterval)
        }
    }

    // MARK: Private

    private var engine: SystemMonitorEngine?
    private var streamTask: Task<Void, Never>?

    // MARK: Lifecycle

    init() {
        // Restore saved display mode, defaulting to .both
        if let raw = UserDefaults.standard.string(forKey: "DisplayMode"),
           let mode = DisplayMode(rawValue: raw) {
            self.displayMode = mode
        } else {
            self.displayMode = .both
        }

        // Restore saved refresh interval, defaulting to 2.0 seconds
        let savedInterval = UserDefaults.standard.double(forKey: "RefreshInterval")
        self.refreshInterval = savedInterval > 0 ? savedInterval : 2.0

        // Start the engine.
        startEngine()
    }

    deinit {
        engine?.stop()
        streamTask?.cancel()
    }

    /// Quit the application entirely.
    func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// Force an immediate refresh.
    func refreshNow() {
        let snapshot = engine?.sampleNow() ?? .zero
        apply(snapshot)
    }

    // MARK: Engine lifecycle

    private func startEngine() {
        let engine = SystemMonitorEngine(sampleInterval: refreshInterval)
        self.engine = engine
        engine.start()

        streamTask = Task { [weak self] in
            guard let self else { return }
            for await snapshot in engine.snapshotStream {
                await MainActor.run {
                    self.apply(snapshot)
                }
            }
        }
    }

    // MARK: Helpers

    private func apply(_ snapshot: SystemSnapshot) {
        cpuPercentage = snapshot.cpu.systemLoad
        memPercentage = snapshot.memory.usagePercentage
        memUsedGB    = snapshot.memory.usedGB
        memTotalGB   = snapshot.memory.totalGB
        cpuUser      = snapshot.cpu.userLoad
        cpuSystem    = snapshot.cpu.systemCPULoad
        lastUpdated  = snapshot.timestamp

        // Persist into App Group so the Widget Extension can read it.
        AppGroupStore.save(snapshot)
    }
}

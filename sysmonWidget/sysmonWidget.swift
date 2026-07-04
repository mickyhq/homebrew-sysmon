import WidgetKit
import SwiftUI

// MARK: - Entry

struct SystemStatsEntry: TimelineEntry {
    let date: Date
    let cpuPercent: Double
    let memPercent: Double
    let memUsedGB: Double
    let memTotalGB: Double
}

// MARK: - Provider

struct SystemStatsProvider: TimelineProvider {

    func placeholder(in context: Context) -> SystemStatsEntry {
        SystemStatsEntry(date: Date(), cpuPercent: 42, memPercent: 58,
                         memUsedGB: 8.0, memTotalGB: 16.0)
    }

    func getSnapshot(in context: Context, completion: @escaping (SystemStatsEntry) -> Void) {
        let snap = AppGroupStore.latestSnapshot
        let entry = SystemStatsEntry(
            date: snap.timestamp,
            cpuPercent: snap.cpu.systemLoad,
            memPercent: snap.memory.usagePercentage,
            memUsedGB: snap.memory.usedGB,
            memTotalGB: snap.memory.totalGB
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SystemStatsEntry>) -> Void) {
        let snap = AppGroupStore.latestSnapshot
        let entry = SystemStatsEntry(
            date: snap.timestamp,
            cpuPercent: snap.cpu.systemLoad,
            memPercent: snap.memory.usagePercentage,
            memUsedGB: snap.memory.usedGB,
            memTotalGB: snap.memory.totalGB
        )

        // Refresh every 60 seconds — widgets should not refresh too aggressively.
        let nextUpdate = Date().addingTimeInterval(60)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Definition

@main
struct sysmonWidget: Widget {
    let kind = "com.sysmon.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SystemStatsProvider()) { entry in
            SystemStatsWidgetView(entry: entry)
        }
        .configurationDisplayName("System Monitor")
        .description("Displays real-time CPU and memory usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
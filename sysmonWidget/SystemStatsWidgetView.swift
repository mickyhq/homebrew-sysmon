import SwiftUI
import WidgetKit

/// SwiftUI view that renders the widget for both .systemSmall and .systemMedium families.
struct SystemStatsWidgetView: View {
    let entry: SystemStatsEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        default:
            mediumWidget
        }
    }

    // MARK: - Small widget (2×2 gauges)

    private var smallWidget: some View {
        VStack(spacing: 12) {
            Gauge(value: entry.cpuPercent, in: 0...100) {
                Image(systemName: "cpu")
                    .font(.caption2)
            } currentValueLabel: {
                Text(String(format: "%.0f%%", entry.cpuPercent))
                    .font(.caption.monospacedDigit())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(gaugeTint(for: entry.cpuPercent))

            Gauge(value: entry.memPercent, in: 0...100) {
                Image(systemName: "memorychip")
                    .font(.caption2)
            } currentValueLabel: {
                Text(String(format: "%.0f%%", entry.memPercent))
                    .font(.caption.monospacedDigit())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(gaugeTint(for: entry.memPercent))
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Medium widget (horizontal layout with detail)

    private var mediumWidget: some View {
        HStack(spacing: 20) {
            // CPU gauge
            VStack(spacing: 6) {
                Text("CPU")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Gauge(value: entry.cpuPercent, in: 0...100) { }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(gaugeTint(for: entry.cpuPercent))
                Text(String(format: "%.1f%%", entry.cpuPercent))
                    .font(.title2.monospacedDigit().bold())
            }

            Divider()

            // Memory gauge + details
            VStack(spacing: 6) {
                Text("Memory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Gauge(value: entry.memPercent, in: 0...100) { }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(gaugeTint(for: entry.memPercent))
                Text(String(format: "%.1f%%", entry.memPercent))
                    .font(.title2.monospacedDigit().bold())
                Text(String(format: "%.1f / %.1f GB", entry.memUsedGB, entry.memTotalGB))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func gaugeTint(for value: Double) -> Color {
        if value > 80 {
            return .red
        } else if value > 60 {
            return .orange
        } else {
            return .green
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SystemStatsWidgetView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SystemStatsWidgetView(entry: SystemStatsEntry(
                date: Date(), cpuPercent: 35, memPercent: 62, memUsedGB: 10, memTotalGB: 16
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Small")

            SystemStatsWidgetView(entry: SystemStatsEntry(
                date: Date(), cpuPercent: 88, memPercent: 45, memUsedGB: 7.2, memTotalGB: 16
            ))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .previewDisplayName("Medium")
        }
    }
}
#endif
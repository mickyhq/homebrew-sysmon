import SwiftUI

/// Drop-down detail panel shown when the user clicks the menu bar item.
/// CPU and Memory sections are displayed side by side.
struct StatsDetailView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // --- Side-by-side stats ---
            HStack(alignment: .top, spacing: 12) {
                cpuSection
                Divider()
                memorySection
            }
            .frame(maxWidth: .infinity)

            Divider()

            // --- Menu Bar Display Picker ---
            HStack {
                Text("Show in menu bar:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $viewModel.displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // --- Refresh Interval ---
            HStack {
                Text("Refresh every:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { viewModel.refreshInterval },
                    set: { viewModel.refreshInterval = max(1, round($0)) }
                ), in: 1...10, step: 1)
                Text(String(format: "%.0f s", viewModel.refreshInterval))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }

            Divider()

            // --- Footer ---
            HStack {
                Text("Updated: \(viewModel.lastUpdated, style: .time)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    viewModel.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Refresh now")

                Button {
                    viewModel.quit()
                } label: {
                    Text("Quit")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: [.command])
            }
        }
        .padding()
        .frame(minWidth: 360, maxWidth: 400)
    }

    // MARK: - CPU Section

    private var cpuSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(loadColor(viewModel.cpuPercentage))
                Text("CPU")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1f%%", viewModel.cpuPercentage))
                    .font(.title3.monospacedDigit())
                    .foregroundColor(loadColor(viewModel.cpuPercentage))
            }

            ProgressView(value: viewModel.cpuPercentage, total: 100)
                .tint(loadColor(viewModel.cpuPercentage))

            HStack(spacing: 12) {
                StatBadge(label: "User",   value: viewModel.cpuUser,   color: .green)
                StatBadge(label: "System", value: viewModel.cpuSystem, color: .orange)
                StatBadge(label: "Idle",   value: 100 - viewModel.cpuPercentage, color: .gray)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Memory Section

    private var memorySection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "memorychip")
                    .foregroundColor(loadColor(viewModel.memPercentage))
                Text("Memory")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1f%%", viewModel.memPercentage))
                    .font(.title3.monospacedDigit())
                    .foregroundColor(loadColor(viewModel.memPercentage))
            }

            ProgressView(value: viewModel.memPercentage, total: 100)
                .tint(loadColor(viewModel.memPercentage))

            HStack {
                Text(String(format: "%.1f GB used of %.1f GB",
                            viewModel.memUsedGB, viewModel.memTotalGB))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Color coding

    /// Returns a color based on load severity.
    /// Green ≤ 60%  < Orange ≤ 80%  < Red
    private func loadColor(_ value: Double) -> Color {
        if value > 80 { return .red }
        if value > 60 { return .orange }
        return .green
    }
}

// MARK: - Supporting reusable badge

struct StatBadge: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f%%", value))
                .font(.caption.monospacedDigit().bold())
                .foregroundColor(color)
        }
    }
}
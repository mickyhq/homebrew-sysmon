import SwiftUI

/// Compact CPU and memory values displayed in the menu bar.
struct MenuBarLabelView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.displayMode != .memory {
                metricView(
                    icon: "cpu",
                    percentage: viewModel.cpuPercentage
                )
            }

            if viewModel.displayMode != .cpu {
                metricView(
                    icon: "memorychip",
                    percentage: viewModel.memPercentage
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func metricView(icon: String, percentage: Double) -> some View {
        let color = loadColor(percentage)
        return HStack(spacing: 3) {
            Image(systemName: icon)
            Text("\(percentage, specifier: "%.0f")%")
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(color)
    }

    private func loadColor(_ value: Double) -> Color {
        if value > 80 { return .red }
        if value > 60 { return .orange }
        return .green
    }
}

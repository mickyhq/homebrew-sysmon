import AppKit
import Combine
import SwiftUI

final class SysmonAppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }
}

final class StatusBarController: NSObject {
    private let viewModel = MenuBarViewModel()
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()

        configureButton()
        configurePopover()
        observeStats()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 400, height: 240)
        popover.contentViewController = NSHostingController(
            rootView: StatsDetailView(viewModel: viewModel)
        )
    }

    private func observeStats() {
        Publishers.CombineLatest3(
            viewModel.$cpuPercentage,
            viewModel.$memPercentage,
            viewModel.$displayMode
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] cpu, memory, mode in
            self?.updateTitle(cpu: cpu, memory: memory, mode: mode)
        }
        .store(in: &cancellables)
    }

    private func updateTitle(
        cpu: Double,
        memory: Double,
        mode: DisplayMode
    ) {
        guard let button = statusItem.button else { return }

        let title = NSMutableAttributedString()

        if mode != .memory {
            appendMetric(
                to: title,
                icon: "cpu",
                percentage: cpu,
                color: usageColor(cpu)
            )
        }

        if mode == .both {
            title.append(NSAttributedString(string: "  "))
        }

        if mode != .cpu {
            appendMetric(
                to: title,
                icon: "memorychip",
                percentage: memory,
                color: usageColor(memory)
            )
        }

        button.image = nil
        button.attributedTitle = title
        statusItem.length = NSStatusItem.variableLength
    }

    private func appendMetric(
        to title: NSMutableAttributedString,
        icon: String,
        percentage: Double,
        color: NSColor
    ) {
        let symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 11,
            weight: .medium
        ).applying(
            NSImage.SymbolConfiguration(paletteColors: [color])
        )

        if let image = NSImage(
            systemSymbolName: icon,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(symbolConfiguration) {
            image.isTemplate = false

            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: -2, width: 13, height: 13)
            title.append(NSAttributedString(attachment: attachment))
        }

        title.append(
            NSAttributedString(
                string: String(format: " %.0f%%", percentage),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(
                        ofSize: 11,
                        weight: .medium
                    ),
                    .foregroundColor: color
                ]
            )
        )
    }

    private func usageColor(_ percentage: Double) -> NSColor {
        if percentage > 80 {
            return .systemRed
        }

        if percentage > 60 {
            return .systemOrange
        }

        return .systemGreen
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
    }
}

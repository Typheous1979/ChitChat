import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private let appState: AppState
    private var eventMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.popover = NSPopover()

        setupPopover()
        setupStatusButton()
        setupEventMonitor()
    }

    private func setupPopover() {
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(onQuitClicked: {
                NSApp.terminate(nil)
            })
            .environment(appState)
        )
    }

    private func setupStatusButton() {
        guard let button = statusItem.button else { return }

        let image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "ChitChat")
        image?.isTemplate = true
        button.image = image
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func updateIcon(isRecording: Bool) {
        guard let button = statusItem.button else { return }
        let symbolName = isRecording ? "waveform.circle.fill" : "waveform.circle"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ChitChat")
        image?.isTemplate = !isRecording
        if isRecording {
            button.contentTintColor = .systemRed
        } else {
            button.contentTintColor = nil
        }
        button.image = image
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}

import AppKit
import SwiftUI

/// A borderless, transparent, always-on-top window for showing live transcription.
/// Floats near the cursor and ignores mouse events.
final class TranscriptionOverlayWindow: NSWindow {
    let overlayState = OverlayState()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 64),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false

        let overlayView = TranscriptionOverlayView()
            .environment(overlayState)
        let hosting = NSHostingView(rootView: overlayView)
        hosting.frame = contentRect(forFrameRect: frame)
        self.contentView = hosting
    }

    /// Update the displayed transcription text via the shared observable state.
    func updateText(_ text: String, isFinal: Bool) {
        overlayState.text = text
        overlayState.isFinal = isFinal
    }

    /// Position the overlay near the current mouse/cursor location.
    func positionNearCursor() {
        let mouseLocation = NSEvent.mouseLocation

        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return }

        let x = mouseLocation.x - frame.width / 2
        let y = mouseLocation.y + 30

        let screenFrame = screen.visibleFrame
        let clampedX = max(screenFrame.minX, min(x, screenFrame.maxX - frame.width))
        let clampedY = max(screenFrame.minY, min(y, screenFrame.maxY - frame.height))

        setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }

    /// Show the overlay with animation.
    func showAnimated() {
        positionNearCursor()
        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = 1
        }
    }

    /// Hide the overlay with animation.
    func hideAnimated() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

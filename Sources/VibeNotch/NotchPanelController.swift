import AppKit
import SwiftUI

/// A borderless, non-activating panel pinned centered under the notch.
@MainActor
final class NotchPanelController {
    private let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: NotchView())
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { show() }
    }

    /// Center horizontally, pinned to the top of the active screen (under the notch).
    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let topInset = max(screen.safeAreaInsets.top, 0) // notch height on notched Macs
        let y = frame.maxY - size.height - topInset
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

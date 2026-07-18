import AppKit
import Combine
import SwiftUI

/// Borderless panel that can still become key so its buttons receive clicks,
/// without activating the app (nonactivating).
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A borderless, non-activating panel pinned centered under the notch.
/// Resizes to hug its content so transparent areas never block clicks beneath.
@MainActor
final class NotchPanelController {
    private let panel: NotchPanel
    private let store: EventStore
    private var cancellable: AnyCancellable?

    init(store: EventStore) {
        self.store = store
        panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 40),
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
        panel.contentView = NSHostingView(rootView: NotchView(store: store))

        // Resize + reposition whenever the store changes.
        cancellable = store.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.sync() }
        }
    }

    func show() { sync() }

    func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { sync() }
    }

    private func sync() {
        panel.setContentSize(desiredSize())
        reposition()
        panel.orderFrontRegardless()
    }

    private func desiredSize() -> NSSize {
        if !store.pending.isEmpty { return NSSize(width: 400, height: 132) }
        if store.lastNotification != nil { return NSSize(width: 340, height: 40) }
        return NSSize(width: 220, height: 34)
    }

    /// Center horizontally on the notched screen, tucked just under the notch.
    private func reposition() {
        guard let screen = notchedScreen else { return }
        let frame = screen.frame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let topInset = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        let y = frame.maxY - size.height - topInset + 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private var notchedScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }
}

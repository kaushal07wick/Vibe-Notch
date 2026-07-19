import Combine
import DynamicNotchKit
import SwiftUI

/// Owns the DynamicNotch and keeps its expand/compact state in sync with the
/// event store. Expands on hover or when there's something to show; compacts
/// otherwise. DynamicNotchKit handles the window, geometry, hover, and morph.
@MainActor
final class NotchPanelController {
    private let store: EventStore
    private let notch: DynamicNotch<ExpandedContent, CompactLeading, CompactTrailing>
    private var cancellables: [AnyCancellable] = []
    private var expanded: Bool?
    private var lastPendingCount = 0
    /// After any auto-collapse, hover may not re-expand until the pointer has
    /// actually left the notch — otherwise a parked cursor loops expand/collapse.
    private var needsHoverExit = false
    private var recheckTask: Task<Void, Never>?
    /// Hover-only expansions self-dismiss after this dwell (VI: ~5s, ESC sooner).
    private var dwellTask: Task<Void, Never>?

    init(store: EventStore, usage: UsageModel) {
        self.store = store
        notch = DynamicNotch(
            hoverBehavior: .all,
            style: .auto,
            expanded: { ExpandedContent(store: store, usage: usage) },
            compactLeading: { CompactLeading(store: store) },
            compactTrailing: { CompactTrailing(store: store) }
        )
        // Springy morph — a little bounce on open/convert, a calm close.
        notch.transitionConfiguration = .init(
            // fast open — an approval must be actionable the instant it arrives
            openingAnimation: .spring(response: 0.32, dampingFraction: 0.85),
            closingAnimation: .spring(response: 0.26, dampingFraction: 0.92),
            conversionAnimation: .spring(response: 0.34, dampingFraction: 0.85)
        )
        cancellables.append(store.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.refresh() }
        })
        cancellables.append(notch.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.refresh() }
        })
        // app switches change whether the agent's terminal is frontmost
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// The underlying panel (labs lock-screen attach).
    var panelWindow: NSWindow? { notch.windowController?.window }

    func show() {
        Task { await notch.compact() }
        expanded = false
    }

    func toggle() {
        Task { await notch.expand() }
    }

    private func refresh() {
        if store.hovering != notch.isHovering { store.hovering = notch.isHovering } // drives brief→full

        // A decision just landed (clicked here OR answered in the terminal):
        // collapse immediately, even though the cursor still sits on the panel.
        let hasPending = !store.pending.isEmpty && !store.privacyHold
        if lastPendingCount > 0 && !hasPending {
            lastPendingCount = 0
            needsHoverExit = true
            expanded = false
            Task { await notch.compact() }
            return
        }
        lastPendingCount = store.pending.count

        if !notch.isHovering { needsHoverExit = false }
        // Flag-based only: any pointer-exit re-arms hover instantly. (The old
        // timed windows left hover dead with nothing scheduled to re-check.)
        let hovering = notch.isHovering && !needsHoverExit
        // smart suppression: if you're already looking at the agent's terminal,
        // the prompt is right in front of you — no popup (badge + hover still work)
        let suppressed = VNSettings.smartSuppression && !hovering && frontmostIsTerminal()
        let want = (hasPending && !suppressed) || hovering

        // Heartbeat while cards are pending: app-switch notifications can be
        // missed (Stage Manager, fast cmd-tab) — re-evaluate every second so
        // suppression engages/releases reliably.
        recheckTask?.cancel()
        if hasPending || (store.isBusy && VNSettings.autoHideWhenIdle) {
            recheckTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }

        // Auto-hide when idle: a paused/finished agent shouldn't sit over
        // fullscreen video. Reappears the instant work resumes or a card lands.
        if VNSettings.autoHideWhenIdle && !store.isBusy && !hovering {
            guard expanded != nil else { return }
            expanded = nil
            Task { await notch.hide() }
            return
        }

        // Coming back from hidden (auto-hide) — always re-show.
        if expanded == nil {
            expanded = want
            Task { if want { await notch.expand() } else { await notch.compact() } }
            return
        }

        guard want != expanded else { scheduleDwell(hasPending: hasPending, want: want); return }
        expanded = want
        Task {
            if want {
                await notch.expand()
                // NOTE: no makeKey — stealing key focus hijacked the user's typing
                // whenever a card popped. ^A/^G/^D are global monitors and buttons
                // take the first click without key status.
            } else {
                await notch.compact()
            }
        }
        scheduleDwell(hasPending: hasPending, want: want)
    }

    /// Auto-collapse hover-only expansions so the notch never squats open.
    private func scheduleDwell(hasPending: Bool, want: Bool) {
        dwellTask?.cancel()
        guard want, !hasPending else { return }
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.store.pending.isEmpty else { return }
            self.needsHoverExit = true
            self.expanded = false
            await self.notch.compact()
        }
    }

    /// ESC — collapse immediately.
    func collapseNow() {
        dwellTask?.cancel()
        needsHoverExit = true
        expanded = false
        Task { await notch.compact() }
    }
}

/// Is the frontmost app a terminal? If you're looking at ANY terminal, the
/// agent's prompt is on your screen — no popup. Bundle-prefix matching is
/// robust across localized names and app variants.
@MainActor
private func frontmostIsTerminal() -> Bool {
    let front = NSWorkspace.shared.frontmostApplication
    let bundle = (front?.bundleIdentifier ?? "").lowercased()
    let name = (front?.localizedName ?? "").lowercased()
    let bundles = ["com.mitchellh.ghostty", "com.googlecode.iterm2",
                   "com.apple.terminal", "dev.warp", "net.kovidgoyal.kitty",
                   "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper"]
    if bundles.contains(where: { bundle.hasPrefix($0) }) { return true }
    let names = ["ghostty", "iterm", "terminal", "warp", "kitty", "alacritty", "wezterm"]
    return names.contains(where: { name == $0 || name.hasPrefix($0) })
}

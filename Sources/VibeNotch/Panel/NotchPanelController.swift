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
    private var clickMonitor: Any?
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
        // The panel is non-activating, so a click on a non-key panel is spent making it
        // key and never reaches the button. Make it key first — only on a click, so
        // hovering still never steals the user's typing.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let panel = self?.panelWindow, event.window === panel, !panel.isKeyWindow { panel.makeKey() }
            return event
        }
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

    /// The screen the notch lives on. DynamicNotchKit defaults every call to
    /// `NSScreen.screens[0]`, which strands the notch on the built-in display
    /// for anyone working on an external monitor. Falls back to the main screen
    /// when the chosen display is unplugged.
    private var targetScreen: NSScreen {
        let wanted = VNSettings.notchDisplayID
        guard !wanted.isEmpty,
              let match = NSScreen.screens.first(where: { $0.vnDisplayID == wanted })
        else {
            // NSScreen.main follows keyboard focus, so with an external monitor
            // the notch jumped there; prefer the display that has a real notch.
            return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
                ?? NSScreen.main ?? NSScreen.screens[0]
        }
        return match
    }

    func show() {
        Task { await notch.compact(on: targetScreen) }
        expanded = false
    }

    func toggle() {
        open(seconds: 20)
    }

    /// Open the panel in its full (hovered) form without a pointer — the CLI's
    /// `vibenotch open`. Also how the UI gets looked at while iterating on it.
    func open(seconds: Double) {
        hoverUntil = Date().addingTimeInterval(seconds)
        store.hovering = true
        expanded = true
        Task { await notch.expand(on: targetScreen) }
        refresh()
    }

    /// While set, the panel behaves as if the pointer were on it.
    private var hoverUntil = Date.distantPast

    private func refresh() {
        if let id = store.controlSessionID, !store.activeSessions.contains(where: { $0.id == id }) {
            store.controlSessionID = nil
        }
        let held = Date() < hoverUntil || store.controlSessionID != nil
        let wantHover = notch.isHovering || held
        if store.hovering != wantHover { store.hovering = wantHover } // drives brief→full

        // A decision just landed (clicked here OR answered in the terminal):
        // collapse immediately, even though the cursor still sits on the panel.
        let hasPending = !store.pending.isEmpty && !store.privacyHold
        if lastPendingCount > 0 && !hasPending && store.controlSessionID == nil {
            lastPendingCount = 0
            needsHoverExit = true
            expanded = false
            Task { await notch.compact(on: targetScreen) }
            return
        }
        lastPendingCount = store.pending.count

        if !notch.isHovering { needsHoverExit = false }
        // Flag-based only: any pointer-exit re-arms hover instantly. (The old
        // timed windows left hover dead with nothing scheduled to re-check.)
        // With collapse-on-leave off, an opened panel stays up until Esc or a
        // decision — the pointer leaving is not enough.
        let stickyOpen = !VNSettings.collapseOnLeave && expanded == true && !needsHoverExit
        let hovering = (notch.isHovering && !needsHoverExit) || held || stickyOpen
        // smart suppression: if you're already looking at the agent's terminal,
        // the prompt is right in front of you — no popup (badge + hover still work)
        let suppressed = VNSettings.smartSuppression && !hovering && frontmostIsTerminal()
        let want = (hasPending && !suppressed) || hovering

        // Heartbeat while cards are pending: app-switch notifications can be
        // missed (Stage Manager, fast cmd-tab) — re-evaluate every second so
        // suppression engages/releases reliably.
        recheckTask?.cancel()
        if hasPending || held || (store.isBusy && VNSettings.autoHideWhenIdle) {
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
            Task { if want { await notch.expand(on: targetScreen) } else { await notch.compact(on: targetScreen) } }
            return
        }

        guard want != expanded else { scheduleDwell(hasPending: hasPending || held, want: want); return }
        expanded = want
        Task {
            if want {
                await notch.expand(on: targetScreen)
                // NOTE: no makeKey — stealing key focus hijacked the user's typing
                // whenever a card popped. ^A/^G/^D are global monitors and buttons
                // take the first click without key status.
            } else {
                await notch.compact(on: targetScreen)
            }
        }
        scheduleDwell(hasPending: hasPending || held, want: want)
    }

    /// Auto-collapse hover-only expansions so the notch never squats open.
    ///
    /// The deadline is absolute. This used to cancel and restart the timer on
    /// every call — and `refresh()` runs on every hook event, every hover tick
    /// and every app switch, so with an agent actually working the countdown
    /// restarted faster than it could finish and the panel stayed open until
    /// the sessions went quiet.
    private func scheduleDwell(hasPending: Bool, want: Bool) {
        guard want, !hasPending else {
            dwellTask?.cancel(); dwellTask = nil; dwellDeadline = nil
            return
        }
        if let deadline = dwellDeadline, deadline > Date(), dwellTask != nil { return }

        let deadline = Date().addingTimeInterval(VNSettings.dwellSeconds)
        dwellDeadline = deadline
        dwellTask?.cancel()
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, self.store.pending.isEmpty else { return }
            self.dwellDeadline = nil
            self.needsHoverExit = true
            self.expanded = false
            await self.notch.compact(on: self.targetScreen)
        }
    }

    /// When the current hover-only expansion is due to collapse.
    private var dwellDeadline: Date?

    /// ESC — collapse immediately.
    func collapseNow() {
        store.controlSessionID = nil
        hoverUntil = .distantPast
        dwellDeadline = nil
        dwellTask?.cancel()
        needsHoverExit = true
        expanded = false
        Task { await notch.compact(on: targetScreen) }
    }
}

extension NSScreen {
    /// Stable identity for the Display picker. `localizedName` changes with the
    /// system language and repeats across identical monitors; the CGDirectDisplayID
    /// survives both.
    var vnDisplayID: String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = deviceDescription[key] as? NSNumber else { return localizedName }
        return number.stringValue
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

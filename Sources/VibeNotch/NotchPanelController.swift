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
    /// After a decision the cursor is still over the panel — ignore hover
    /// briefly so the collapse isn't immediately re-expanded.
    private var suppressHoverUntil = Date.distantPast
    /// After any auto-collapse, hover may not re-expand until the pointer has
    /// actually left the notch — otherwise a parked cursor loops expand/collapse.
    private var needsHoverExit = false
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
            suppressHoverUntil = Date().addingTimeInterval(1.2)
            expanded = false
            Task { await notch.compact() }
            return
        }
        lastPendingCount = store.pending.count

        if !notch.isHovering { needsHoverExit = false }
        let hovering = notch.isHovering && !needsHoverExit && Date() > suppressHoverUntil
        // dictation keeps the panel open — the mic press must never collapse it
        let want = hasPending || hovering

        // Auto-hide: with nothing active and hover elsewhere, disappear entirely.
        if VNSettings.autoHideWhenIdle && !want && store.activeSessions.isEmpty {
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
        suppressHoverUntil = Date().addingTimeInterval(1.5)
        expanded = false
        Task { await notch.compact() }
    }
}

/// Is the app that hosts this session's terminal currently frontmost?
@MainActor
private func terminalIsFrontmost(_ terminal: String?) -> Bool {
    guard let terminal else { return false }
    let front = NSWorkspace.shared.frontmostApplication
    let name = front?.localizedName ?? ""
    let bundle = front?.bundleIdentifier ?? ""
    switch terminal {
    case "Ghostty":  return bundle == "com.mitchellh.ghostty" || name == "Ghostty"
    case "iTerm":    return bundle == "com.googlecode.iterm2" || name.hasPrefix("iTerm")
    case "Terminal": return bundle == "com.apple.Terminal"
    case "Warp":     return bundle.hasPrefix("dev.warp") || name == "Warp"
    case "VS Code":  return bundle == "com.microsoft.VSCode" || name.contains("Code")
    default:         return name == terminal
    }
}

import AppKit
import VibeNotchCore

/// Routes key events to `VNAction`s using the user's bindings (see Shortcuts).
/// The local monitor always works while the panel is focused; the global one
/// needs Accessibility granted once.
@MainActor
final class ShortcutMonitor {
    private var monitors: [Any] = []

    init(store: EventStore,
         collapse: @escaping () -> Void = {},
         panelWindow: @escaping () -> NSWindow? = { nil }) {
        // Clicking the panel focuses it just-in-time, so the FIRST click lands
        // on the button — without auto-expansion ever stealing typing focus.
        if let mouse = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { event in
            if let panel = panelWindow(), event.window === panel, !panel.isKeyWindow {
                panel.makeKey()
            }
            return event
        }) { monitors.append(mouse) }

        let handle: (NSEvent) -> Bool = { [weak store] event in
            guard VNSettings.shortcutsEnabled else { return false } // master switch, mappings kept
            guard let action = VNShortcuts.action(for: event) else { return false }
            if action == .collapse { collapse(); return true }
            guard let store else { return false }

            let decision: VNDecision?
            switch action {
            case .approve: decision = .allow
            case .deny: decision = .deny
            case .alwaysAllow: decision = .alwaysAllow
            case .bypass: decision = .bypass
            case .jump, .collapse: decision = nil
            }
            if let decision {
                guard let first = store.pending.first else { return false }
                store.resolve(first, decision)
                return true
            }
            // .jump — the card's terminal if one is waiting, else the live session's
            let target = store.pending.first.map { ($0.inbound.terminal, $0.inbound.tty, $0.inbound.termMeta ?? [:]) }
                ?? store.activeSession.map { ($0.terminal, $0.tty, $0.termMeta ?? [:]) }
            guard let target else { return false }
            TerminalJumper.jump(terminal: target.0, tty: target.1, meta: target.2)
            return true
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            guard let panel = panelWindow(), event.window === panel else { return event }
            if panel.firstResponder is NSTextView, VNShortcuts.action(for: event) != .collapse { return event }
            return handle(event) ? nil : event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            _ = handle(event)
        }) { monitors.append(global) }
    }

    // Lives for the app's lifetime — no teardown needed.
}

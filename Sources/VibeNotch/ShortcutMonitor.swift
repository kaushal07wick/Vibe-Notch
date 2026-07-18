import AppKit

/// Keyboard shortcuts: ^A approves the front permission card, ^G jumps to the
/// active session's terminal. Local monitor always works (panel focused);
/// the global monitor needs the user to grant Accessibility once.
/// ponytail: ESC-collapse skipped — the notch already collapses on mouse-leave.
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
            if event.keyCode == 53 { collapse(); return true } // ESC
            guard let store, event.modifierFlags.contains(.control) else { return false }
            switch event.charactersIgnoringModifiers {
            case "a":
                guard let first = store.pending.first else { return false }
                store.resolve(first, .allow)
                return true
            case "g":
                let target = store.pending.first.map { ($0.inbound.terminal, $0.inbound.tty) }
                    ?? store.activeSession.map { ($0.terminal, $0.tty) }
                guard let target else { return false }
                TerminalJumper.jump(terminal: target.0, tty: target.1)
                return true
            default:
                return false
            }
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            handle(event) ? nil : event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            _ = handle(event)
        }) { monitors.append(global) }
    }

    // Lives for the app's lifetime — no teardown needed.
}

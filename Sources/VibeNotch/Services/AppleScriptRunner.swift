import AppKit

/// Every AppleScript the app runs goes through here.
///
/// Automation consent is per-target-app and macOS reports a refusal as an
/// ordinary script error. Both call sites used to log it and return — so a
/// denied prompt (or a "Don't Allow" clicked months ago) made ^G and
/// reply-from-notch do *nothing*, with no way to find out why. One place to
/// notice, one place to point at the setting.
enum VNAppleScript {
    /// errAEEventNotPermitted — the user has not allowed us to drive this app.
    private static let notPermitted = -1743
    /// "not allowed to send keystrokes" — Accessibility, not Automation.
    private static let noKeystrokes = -1719

    @discardableResult
    static func run(_ source: String, purpose: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return result?.stringValue }

        NSLog("VibeNotch: AppleScript (\(purpose)) failed: \(error)")
        switch error[NSAppleScript.errorNumber] as? Int {
        case notPermitted:
            let app = error[NSAppleScript.errorAppName] as? String ?? "your terminal"
            Task { @MainActor in AutomationConsent.report(app: app, purpose: purpose) }
        case noKeystrokes:
            Task { @MainActor in AutomationConsent.reportKeystrokes(purpose: purpose) }
        default:
            break
        }
        return nil
    }
}

/// Explains a refusal once per target app per run — the same jump retried five
/// times should not stack five alerts.
@MainActor
private enum AutomationConsent {
    private static var reported = Set<String>()

    /// Typing into a terminal with no scripting API goes through System Events,
    /// which needs Accessibility — a different permission from Automation, and
    /// a different pane to grant it in.
    static func reportKeystrokes(purpose: String) {
        guard reported.insert("__keystrokes").inserted else { return }
        let alert = NSAlert()
        alert.messageText = "Vibe Notch needs Accessibility to type"
        alert.informativeText = """
            This terminal has no scripting API, so \(purpose) works by typing the \
            text for you — and macOS only allows that with Accessibility turned on.

            Turn on Vibe Notch under Privacy & Security › Accessibility, then try \
            again.
            """
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityPermission.openSettings()
        }
    }

    static func report(app: String, purpose: String) {
        guard reported.insert(app).inserted else { return }
        let alert = NSAlert()
        alert.messageText = "Vibe Notch can't control \(app)"
        alert.informativeText = """
            macOS blocked \(purpose) because Automation permission for \(app) \
            hasn't been granted.

            Turn on \(app) under Vibe Notch in Privacy & Security › Automation, \
            then try again.
            """
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        }
    }
}

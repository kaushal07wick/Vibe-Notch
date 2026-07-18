import Foundation
import ServiceManagement

/// UserDefaults-backed app settings. UI panes read/write these; backend
/// behaviors observe them. Keys are stable — don't rename.
@MainActor
enum VNSettings {
    private static let d = UserDefaults.standard

    // MARK: Sound

    static var soundEnabled: Bool {
        get { d.object(forKey: "soundEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "soundEnabled") }
    }

    /// 0…1 output gain for synthesized alerts.
    static var soundVolume: Double {
        get { d.object(forKey: "soundVolume") as? Double ?? 0.7 }
        set { d.set(newValue, forKey: "soundVolume") }
    }

    // MARK: Behavior

    /// Seconds before an unanswered permission escalates (repeat chime +
    /// ⚠ menu-bar badge). 0 disables.
    static var escalationSeconds: Int {
        get { d.object(forKey: "escalationSeconds") as? Int ?? 120 }
        set { d.set(newValue, forKey: "escalationSeconds") }
    }

    /// Auto-approve safe-listed simple commands (git status, ls, …).
    static var safeListEnabled: Bool {
        get { d.object(forKey: "safeListEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "safeListEnabled") }
    }

    /// Hide the compact notch entirely when no sessions are active.
    static var autoHideWhenIdle: Bool {
        get { d.bool(forKey: "autoHideWhenIdle") }
        set { d.set(newValue, forKey: "autoHideWhenIdle") }
    }

    /// Hold approval cards while the screen is being shared.
    static var screenShareGuard: Bool {
        get { d.object(forKey: "screenShareGuard") as? Bool ?? true }
        set { d.set(newValue, forKey: "screenShareGuard") }
    }

    /// ntfy.sh topic for phone escalation pings. Empty = off (default).
    static var ntfyTopic: String {
        get { d.string(forKey: "ntfyTopic") ?? "" }
        set { d.set(newValue, forKey: "ntfyTopic") }
    }

    /// Localhost web dashboard (0 = off).
    static var dashboardPort: Int {
        get { d.integer(forKey: "dashboardPort") }
        set { d.set(newValue, forKey: "dashboardPort") }
    }

    /// Labs: keep the notch above the lock screen / fullscreen (private API).
    static var lockScreenNotch: Bool {
        get { d.bool(forKey: "lockScreenNotch") }
        set { d.set(newValue, forKey: "lockScreenNotch") }
    }

    // MARK: Launch at login (SMAppService)

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("VibeNotch: launch-at-login failed: \(error)")
            }
        }
    }
}

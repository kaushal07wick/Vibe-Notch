import AppKit
import VibeNotchCore

// The menu-bar menu: quick actions only. Pure
// construction — behaviors stay on AppDelegate.
extension AppDelegate {
    /// Quick actions only. Everything configurable moved into Settings when the
    /// panes landed — two places to flip the same switch is two places to
    /// disagree, and the menu had grown past what a menu is good at.
    func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let sound = NSMenuItem(title: "Sound alerts", action: #selector(toggleSound), keyEquivalent: "")
        sound.target = self
        sound.state = SoundManager.shared.enabled ? .on : .off
        menu.addItem(sound)

        let yoloActive = Date().timeIntervalSince1970 < VNSettings.yoloUntil
        let yoloTitle = yoloActive
            ? "YOLO mode (\(max(1, Int((VNSettings.yoloUntil - Date().timeIntervalSince1970) / 60)))m left)"
            : "YOLO mode (30 min)"
        let yolo = NSMenuItem(title: yoloTitle, action: #selector(toggleYolo), keyEquivalent: "")
        yolo.target = self
        yolo.state = yoloActive ? .on : .off
        menu.addItem(yolo)

        let toggle = NSMenuItem(title: "Toggle Panel", action: #selector(togglePanel), keyEquivalent: "t")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())
        // Was reachable only by hovering the notch and hitting the gear.
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let welcome = NSMenuItem(title: "Setup Guide…", action: #selector(openWelcome), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)
        menu.addItem(NSMenuItem(title: "Quit Vibe Notch",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func openSettings() { SettingsWindow.show() }

    @objc private func openWelcome() { Welcome.show() }

    @objc private func togglePanel() { notch.toggle() }

    @objc private func toggleSound() {
        SoundManager.shared.enabled.toggle()
        if SoundManager.shared.enabled { SoundManager.shared.play(.done) }
    }

    @objc private func toggleYolo() {
        let active = Date().timeIntervalSince1970 < VNSettings.yoloUntil
        VNSettings.yoloUntil = active ? 0 : Date().timeIntervalSince1970 + 1800
    }

}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { buildMenu(menu) }
}

import AppKit
import VibeNotchCore

// The menu-bar menu: agents, SSH servers, toggles, rules. Pure construction —
// behaviors stay on AppDelegate.
extension AppDelegate {
    func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "Agents", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // Detected agents are toggleable; undetected ones shown dimmed for discoverability.
        for spec in Agents.all {
            let installer = AgentHookInstaller(spec)
            let item = NSMenuItem(title: spec.name, action: #selector(toggleAgent(_:)), keyEquivalent: "")
            item.representedObject = spec.id
            if spec.isDetected {
                item.target = self
                item.state = installer.isConnected ? .on : .off
            } else {
                item.isEnabled = false
                item.title = "\(spec.name)  (not installed)"
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let sshHeader = NSMenuItem(title: "SSH Remote", action: nil, keyEquivalent: "")
        sshHeader.isEnabled = false
        menu.addItem(sshHeader)
        for server in SSHRemote.load() {
            let item = NSMenuItem(title: server.host, action: #selector(removeSSHServer(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = server.host
            item.state = server.enabled ? .on : .off
            item.toolTip = "Click to remove this server"
            menu.addItem(item)
        }
        let addSSH = NSMenuItem(title: "Add SSH Server…", action: #selector(addSSHServer), keyEquivalent: "")
        addSSH.target = self
        menu.addItem(addSSH)

        menu.addItem(.separator())
        let sound = NSMenuItem(title: "Sound alerts", action: #selector(toggleSound), keyEquivalent: "")
        sound.target = self
        sound.state = SoundManager.shared.enabled ? .on : .off
        menu.addItem(sound)

        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = VNSettings.launchAtLogin ? .on : .off
        menu.addItem(login)

        let autoHide = NSMenuItem(title: "Auto-hide when idle", action: #selector(toggleAutoHide), keyEquivalent: "")
        autoHide.target = self
        autoHide.state = VNSettings.autoHideWhenIdle ? .on : .off
        menu.addItem(autoHide)

        let safe = NSMenuItem(title: "Auto-approve safe commands", action: #selector(toggleSafeList), keyEquivalent: "")
        safe.target = self
        safe.state = VNSettings.safeListEnabled ? .on : .off
        menu.addItem(safe)

        let editSafe = NSMenuItem(title: "Edit Safe List…", action: #selector(editSafeList), keyEquivalent: "")
        editSafe.target = self
        menu.addItem(editSafe)

        // Rules manager: every allow-rule in ~/.claude, click to remove.
        let rules = PermissionRules.listAllow(source: "claude")
        if !rules.isEmpty {
            let rulesItem = NSMenuItem(title: "Permission Rules", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for rule in rules {
                let item = NSMenuItem(title: rule, action: #selector(removeRule(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = rule
                item.toolTip = "Click to remove this always-allow rule"
                sub.addItem(item)
            }
            rulesItem.submenu = sub
            menu.addItem(rulesItem)
        }

        let intercept = NSMenuItem(title: "Notch handles", action: nil, keyEquivalent: "")
        let interceptMenu = NSMenu()
        for (value, label) in [("low", "All permissions"), ("medium", "Medium + high risk"), ("high", "High risk only")] {
            let item = NSMenuItem(title: label, action: #selector(pickMinRisk(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = VNSettings.notchMinRisk == value ? .on : .off
            interceptMenu.addItem(item)
        }
        intercept.submenu = interceptMenu
        menu.addItem(intercept)

        let theme = NSMenuItem(title: "Sound theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for name in ["chime", "arcade", "minimal"] {
            let item = NSMenuItem(title: name.capitalized, action: #selector(pickTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = VNSettings.soundTheme == name ? .on : .off
            themeMenu.addItem(item)
        }
        theme.submenu = themeMenu
        menu.addItem(theme)

        let dash = NSMenuItem(title: "Web dashboard (localhost:4141)", action: #selector(toggleDashboard), keyEquivalent: "")
        dash.target = self
        dash.state = VNSettings.dashboardPort > 0 ? .on : .off
        menu.addItem(dash)

        let yoloActive = Date().timeIntervalSince1970 < VNSettings.yoloUntil
        let yoloTitle = yoloActive
            ? "YOLO mode (\(max(1, Int((VNSettings.yoloUntil - Date().timeIntervalSince1970) / 60)))m left)"
            : "YOLO mode (30 min)"
        let yolo = NSMenuItem(title: yoloTitle, action: #selector(toggleYolo), keyEquivalent: "")
        yolo.target = self
        yolo.state = yoloActive ? .on : .off
        menu.addItem(yolo)

        let lock = NSMenuItem(title: "Labs: notch over lock screen", action: #selector(toggleLockScreen), keyEquivalent: "")
        lock.target = self
        lock.state = VNSettings.lockScreenNotch ? .on : .off
        menu.addItem(lock)

        let toggle = NSMenuItem(title: "Toggle Panel", action: #selector(togglePanel), keyEquivalent: "t")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Vibe Notch",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func togglePanel() { notch.toggle() }

    @objc private func toggleSound() {
        SoundManager.shared.enabled.toggle()
        if SoundManager.shared.enabled { SoundManager.shared.play(.done) }
    }

    @objc private func toggleLaunchAtLogin() { VNSettings.launchAtLogin.toggle() }

    @objc private func addSSHServer() {
        let alert = NSAlert()
        alert.messageText = "Add SSH Server"
        alert.informativeText = "user@host (key-based auth). Vibe Notch deploys its hook client and opens a reverse tunnel."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "deploy@my-server"
        alert.accessoryView = field
        alert.addButton(withTitle: "Deploy & Connect")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let host = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        Task { @MainActor in
            if let error = await tunnels.addServer(host: host) {
                let fail = NSAlert()
                fail.messageText = "SSH deploy failed"
                fail.informativeText = error
                fail.runModal()
            }
        }
    }

    @objc private func removeSSHServer(_ sender: NSMenuItem) {
        guard let host = sender.representedObject as? String else { return }
        tunnels.removeServer(host: host)
    }

    @objc private func toggleAutoHide() { VNSettings.autoHideWhenIdle.toggle() }

    @objc private func toggleSafeList() { VNSettings.safeListEnabled.toggle() }

    @objc private func pickMinRisk(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        VNSettings.notchMinRisk = value
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        VNSettings.soundTheme = name
        SoundManager.shared.play(.done)
    }

    @objc private func toggleYolo() {
        let active = Date().timeIntervalSince1970 < VNSettings.yoloUntil
        VNSettings.yoloUntil = active ? 0 : Date().timeIntervalSince1970 + 1800
    }

    @objc private func toggleDashboard() {
        VNSettings.dashboardPort = VNSettings.dashboardPort > 0 ? 0 : 4141
        applyDashboardSetting()
        if VNSettings.dashboardPort > 0, let url = URL(string: "http://localhost:4141") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLockScreen() {
        VNSettings.lockScreenNotch.toggle()
        applyLockScreenSetting()
    }

    @objc private func editSafeList() {
        _ = SafeList.patterns() // ensure the file exists
        NSWorkspace.shared.open(SafeList.url)
    }

    @objc private func removeRule(_ sender: NSMenuItem) {
        guard let rule = sender.representedObject as? String else { return }
        PermissionRules.removeAllowRule(source: "claude", rule: rule)
    }

    @objc private func toggleAgent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let spec = Agents.byID(id) else { return }
        let installer = AgentHookInstaller(spec)
        do {
            if installer.isConnected {
                try installer.disconnect()
            } else {
                let src = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/vibenotch-hook")
                try installer.connect(hookBinarySource: src)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Vibe Notch"
            alert.informativeText = "Could not update \(spec.name) hooks:\n\(error.localizedDescription)"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { buildMenu(menu) }
}

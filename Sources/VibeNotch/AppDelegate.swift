import AppKit
import Combine
import VibeNotchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let store = EventStore()
    private let usage = UsageModel()
    private var notch: NotchPanelController!
    private var server: IPCServer!
    private var shortcuts: ShortcutMonitor!
    private let tunnels = SSHTunnelManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? VNPaths.ensure()
        AgentHookInstaller.pluginSourceDir = Bundle.main.resourceURL
        autoConnectDetectedAgents()
        StatusLineInstaller.installIfNeeded()
        usage.start()
        setupStatusItem()
        notch = NotchPanelController(store: store, usage: usage)
        notch.show()
        shortcuts = ShortcutMonitor(store: store)
        startServer()
        tunnels.start()
        observeBadge()
    }

    /// Menu-bar icon shows the pending-approval count ("✦ 2") so a waiting
    /// agent is visible even when the notch is hidden or on another display.
    private var badgeObservers: [AnyCancellable] = []
    private func observeBadge() {
        store.$pending.combineLatest(store.$escalated)
            .sink { [weak self] pending, escalated in
                let count = pending.isEmpty ? "" : " \(pending.count)"
                self?.statusItem.button?.title = escalated ? " ⚠\(count)" : count
            }
            .store(in: &badgeObservers)
    }

    func applicationWillTerminate(_ notification: Notification) {
        tunnels.stop()
    }

    /// Zero-config: wire every detected agent on launch; refresh already-connected
    /// ones so newly added hook events land. Fail-open — errors are logged only.
    private func autoConnectDetectedAgents() {
        let hookBinary = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/vibenotch-hook")
        for spec in Agents.detected {
            let installer = AgentHookInstaller(spec)
            if installer.isConnected {
                installer.reconcile()
            } else {
                do { try installer.connect(hookBinarySource: hookBinary) }
                catch { NSLog("VibeNotch: could not connect \(spec.name): \(error)") }
            }
        }
    }

    private func startServer() {
        server = IPCServer(
            onNotify: { [weak self] inbound in
                Task { @MainActor in self?.store.updateSession(inbound) }
            },
            onRequest: { [weak self] id, inbound, complete in
                Task { @MainActor in
                    self?.store.enqueue(PendingApproval(id: id, inbound: inbound, reply: complete))
                }
            },
            onCancel: { [weak self] id in
                Task { @MainActor in self?.store.cancel(id) }
            }
        )
        do { try server.start() }
        catch { NSLog("VibeNotch: IPC server failed to start: \(error)") }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: "Vibe Notch"
        )
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func buildMenu(_ menu: NSMenu) {
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

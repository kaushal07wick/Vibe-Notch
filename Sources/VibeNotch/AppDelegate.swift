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
    private let privacy = PrivacyGuard()
    private let away = AwayTracker()
    private let dashboard = DashboardServer()
    private var lockSpace: LockScreenSpace?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? VNPaths.ensure()
        AgentHookInstaller.pluginSourceDir = Bundle.main.resourceURL
        autoConnectDetectedAgents()
        StatusLineInstaller.installIfNeeded()
        usage.start()
        setupStatusItem()
        notch = NotchPanelController(store: store, usage: usage)
        notch.show()
        shortcuts = ShortcutMonitor(store: store,
                                    collapse: { [weak self] in self?.notch.collapseNow() },
                                    panelWindow: { [weak self] in self?.notch.panelWindow })
        startServer()
        tunnels.start()
        observeBadge()
        privacy.onChange = { [weak self] sharing in self?.store.privacyHold = sharing }
        privacy.start()
        dashboard.stateProvider = { [weak self] in
            self?.handleControl(VNInbound(type: .control, source: "web", event: "list")) ?? "{}"
        }
        dashboard.actionHandler = { [weak self] action in
            self?.handleControl(VNInbound(type: .control, source: "web", event: action)) ?? "{}"
        }
        applyDashboardSetting()
        applyLockScreenSetting()
        away.onReturn = { [weak self] since in self?.store.showDigest(since: since) }
        away.start()
    }

    private func applyDashboardSetting() {
        let port = VNSettings.dashboardPort
        if port > 0 { dashboard.start(port: UInt16(port)) } else { dashboard.stop() }
    }

    private func applyLockScreenSetting() {
        if VNSettings.lockScreenNotch {
            if lockSpace == nil { lockSpace = LockScreenSpace() }
            if let window = notch.panelWindow { lockSpace?.attach(window) }
        } else {
            lockSpace?.detach()
            lockSpace = nil
        }
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
        let cli = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/vibenotch")
        if FileManager.default.fileExists(atPath: cli.path) {
            let dest = VNPaths.bin.appendingPathComponent("vibenotch")
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: cli, to: dest)
        }
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
            },
            onControl: { [weak self] cmd, reply in
                Task { @MainActor in
                    reply(self?.handleControl(cmd) ?? #"{"ok":false,"error":"shutting down"}"#)
                }
            }
        )
        do { try server.start() }
        catch { NSLog("VibeNotch: IPC server failed to start: \(error)") }
    }

    /// CLI/dashboard command dispatch. Replies one JSON line.
    private func handleControl(_ cmd: VNInbound) -> String {
        func fail(_ error: String) -> String { #"{"ok":false,"error":"\#(error)"}"# }
        func session(for target: String?) -> SessionActivity? {
            guard let target, !target.isEmpty else { return store.activeSession }
            return store.activeSessions.first {
                $0.sessionId.hasPrefix(target) || $0.folder == target
            }
        }
        switch cmd.event {
        case "list":
            var obj: [String: Any] = ["ok": true]
            obj["pending"] = store.pending.map {
                ["id": $0.id.uuidString, "tool": $0.inbound.tool ?? "",
                 "detail": $0.inbound.detail ?? "", "session": $0.inbound.sessionId ?? ""]
            }
            if let data = try? JSONEncoder().encode(store.activeSessions),
               let sessions = try? JSONSerialization.jsonObject(with: data) {
                obj["sessions"] = sessions
            }
            guard let out = try? JSONSerialization.data(withJSONObject: obj),
                  let text = String(data: out, encoding: .utf8) else { return fail("encoding") }
            return text
        case "approve_all":
            store.approveAll(sessionId: cmd.sessionId)
            return #"{"ok":true}"#
        case "undo":
            store.undoLast()
            return #"{"ok":true}"#
        case "approve", "deny":
            let match = cmd.sessionId == nil
                ? store.pending.first
                : store.pending.first { $0.inbound.sessionId?.hasPrefix(cmd.sessionId!) == true }
            guard let match else { return fail("no pending approval") }
            store.resolve(match, cmd.event == "approve" ? .allow : .deny)
            return #"{"ok":true}"#
        case "send":
            guard let s = session(for: cmd.sessionId), let text = cmd.detail else { return fail("no such session") }
            return TerminalControl.send(text, to: s) ? #"{"ok":true}"# : fail("terminal not injectable")
        case "interrupt":
            guard let s = session(for: cmd.sessionId) else { return fail("no such session") }
            return TerminalControl.interrupt(s) ? #"{"ok":true}"# : fail("no foreground process")
        default:
            return fail("unknown action")
        }
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

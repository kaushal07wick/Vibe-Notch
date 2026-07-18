import AppKit
import Combine
import VibeNotchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let store = EventStore()
    let usage = UsageModel()
    var notch: NotchPanelController!
    var server: IPCServer!
    var shortcuts: ShortcutMonitor!
    let tunnels = SSHTunnelManager()
    let privacy = PrivacyGuard()
    let away = AwayTracker()
    let dashboard = DashboardServer()
    var lockSpace: LockScreenSpace?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance across bundle paths (.build dev copy vs /Applications):
        // the newest launch wins — older copies are zombie panels holding no socket.
        let me = NSRunningApplication.current
        for app in NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.kaushalchoudhary.vibenotch")
        where app != me {
            NSLog("VibeNotch: terminating duplicate instance pid \(app.processIdentifier)")
            app.forceTerminate()
        }

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

    func applyDashboardSetting() {
        let port = VNSettings.dashboardPort
        if port > 0 { dashboard.start(port: UInt16(port)) } else { dashboard.stop() }
    }

    func applyLockScreenSetting() {
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
        store.flushForShutdown() // never strand an agent mid-approval
        dashboard.stop()
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
                Task { @MainActor in
                    self?.checkHookVersion(inbound)
                    self?.store.updateSession(inbound)
                }
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


    private var repairedHook = false
    /// Stale hook binary (left from an older app) → reinstall ours once.
    private func checkHookVersion(_ inbound: VNInbound) {
        guard !repairedHook, let version = inbound.hookVersion,
              version != VNProtocol.build else { return }
        repairedHook = true
        NSLog("VibeNotch: hook \(version) != app \(VNProtocol.build) — repairing")
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/vibenotch-hook")
        try? AgentHookInstaller.installHookBinary(from: bundled)
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

}


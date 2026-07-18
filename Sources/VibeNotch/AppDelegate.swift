import AppKit
import VibeNotchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let store = EventStore()
    private var notch: NotchPanelController!
    private var server: IPCServer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? VNPaths.ensure()
        ClaudeInstaller.reconcileIfConnected() // pick up newly-added activity hooks
        setupStatusItem()
        notch = NotchPanelController(store: store)
        notch.show()
        startServer()
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

        let connected = ClaudeInstaller.isConnected
        let status = NSMenuItem(title: connected ? "Claude Code: connected" : "Claude Code: not connected",
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let toggleClaude = NSMenuItem(title: connected ? "Disconnect Claude Code" : "Connect Claude Code",
                                      action: #selector(toggleClaudeConnection), keyEquivalent: "")
        toggleClaude.target = self
        menu.addItem(toggleClaude)

        menu.addItem(.separator())
        let sound = NSMenuItem(title: "Sound alerts", action: #selector(toggleSound), keyEquivalent: "")
        sound.target = self
        sound.state = SoundManager.shared.enabled ? .on : .off
        menu.addItem(sound)

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

    @objc private func toggleClaudeConnection() {
        do {
            if ClaudeInstaller.isConnected {
                try ClaudeInstaller.disconnect()
            } else {
                let src = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/vibenotch-hook")
                try ClaudeInstaller.connect(hookBinarySource: src)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Vibe Notch"
            alert.informativeText = "Could not update Claude Code hooks:\n\(error.localizedDescription)"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { buildMenu(menu) }
}

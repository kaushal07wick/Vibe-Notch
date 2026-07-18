import AppKit
import VibeNotchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var notch: NotchPanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? VNPaths.ensure()
        setupStatusItem()
        notch = NotchPanelController()
        notch.show()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: "Vibe Notch"
        )

        let menu = NSMenu()

        let toggle = NSMenuItem(title: "Toggle Panel", action: #selector(togglePanel), keyEquivalent: "t")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Vibe Notch",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func togglePanel() {
        notch.toggle()
    }
}

import AppKit
import ApplicationServices
import SwiftUI
import VibeNotchCore

/// First-run window. It exists because three things used to happen silently:
/// the app installed itself with no Dock icon and no window (nothing to find),
/// it edited agent config files before anyone had said yes, and the keyboard
/// shortcuts needed a permission nobody had been asked for — so they just
/// didn't fire. This asks, once, and stays reopenable from the menu bar.
@MainActor
enum Welcome {
    private static var window: NSWindow?

    static func showIfFirstRun() {
        guard !VNSettings.welcomeSeen else { return }
        show()
    }

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        w.title = "Welcome to Vibe Notch"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: WelcomeView(close: close))
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        VNSettings.welcomeSeen = true
        window?.close()
    }
}

// MARK: - Permissions

/// Accessibility gates the *global* shortcuts (the local ones work whenever the
/// panel has focus). macOS only tells us yes or no, so the window polls.
enum AccessibilityPermission {
    static var granted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt. macOS only shows it once per app version —
    /// afterwards this is a no-op, so offer Privacy Settings as the way back.
    static func request() {
        // kAXTrustedCheckOptionPrompt is a global var, so Swift 6 won't let us
        // read it across isolation — the key it holds is this literal.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

// MARK: - View

private struct WelcomeView: View {
    let close: () -> Void

    @State private var detected = Agents.detected
    @State private var connected = Set<String>()
    @State private var connectError: String?
    @State private var axGranted = AccessibilityPermission.granted
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                whereItLives
                agents
                permissions
                keys
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .frame(width: 520, height: 640)
        .onReceive(poll) { _ in
            axGranted = AccessibilityPermission.granted
            detected = Agents.detected
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            OwlMark(px: 2.2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Vibe Notch").font(.system(size: 20, weight: .semibold))
                Text("Approve, steer, and watch your coding agents from the notch.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var whereItLives: some View {
        SectionCard(title: "Where to find it") {
            SettingRow(label: "The notch is the window",
                       caption: "There's no Dock icon. Move the pointer over the notch and the panel opens.") { EmptyView() }
            SettingRow(label: "✦ in the menu bar",
                       caption: "Quick actions, Settings, and the count of agents waiting on you.",
                       divider: false) { EmptyView() }
        }
    }

    @ViewBuilder private var agents: some View {
        SectionCard(
            title: "Your agents",
            footnote: detected.isEmpty
                ? "Install Claude Code, Codex, or another supported CLI and reopen this window from the menu bar."
                : "Vibe Notch backs up each config once before its first edit, and removes only its own entries. You can undo any of this in Settings › CLI Hooks."
        ) {
            if detected.isEmpty {
                SettingRow(label: "No agent CLIs found yet",
                           caption: "Nothing has been changed on this Mac.",
                           divider: false) { EmptyView() }
            } else {
                ForEach(Array(detected.enumerated()), id: \.element.id) { index, spec in
                    SettingRow(label: spec.name,
                               caption: AgentHookInstaller(spec).isConnected || connected.contains(spec.id)
                                   ? "Connected" : "Found, not connected yet",
                               divider: index < detected.count - 1) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(VNColor.agent(spec.id).opacity(0.9))
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }

        if !detected.isEmpty {
            HStack(spacing: 10) {
                Button(action: connectAll) {
                    Text(allConnected ? "All connected" : "Connect \(detected.count) agent\(detected.count == 1 ? "" : "s")")
                }
                .buttonStyle(.borderedProminent)
                .disabled(allConnected)
                Text("Adds a hook that tells Vibe Notch when an agent needs you.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let connectError {
                Text(connectError).font(.caption).foregroundStyle(VNColor.stop)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissions: some View {
        SectionCard(title: "Permissions",
                    footnote: "Both are macOS system permissions. Vibe Notch sends nothing off this Mac either way.") {
            SettingRow(label: "Keyboard shortcuts",
                       caption: axGranted
                           ? "Accessibility granted — ^A and ^G work anywhere."
                           : "Needs Accessibility, or shortcuts only work while the panel is focused.") {
                if axGranted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(VNColor.go).labelStyle(.titleAndIcon)
                } else {
                    Button("Grant…") {
                        AccessibilityPermission.request()
                        AccessibilityPermission.openSettings()
                    }
                }
            }
            SettingRow(label: "Terminal control",
                       caption: "macOS asks the first time you jump to a tab or type a reply — one prompt per terminal app.",
                       divider: false) {
                Text("On demand").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var keys: some View {
        SectionCard(title: "Worth knowing") {
            SettingRow(label: "^A approve · ^G jump to the terminal · ⌘K palette",
                       caption: "All rebindable in Settings › Shortcuts.") { EmptyView() }
            SettingRow(label: "Try it without an agent",
                       caption: "./scripts/simulate.sh bash raises a real approval card.",
                       divider: false) { EmptyView() }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Start using Vibe Notch", action: close)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(.regularMaterial)
    }

    private var allConnected: Bool {
        !detected.isEmpty && detected.allSatisfy { AgentHookInstaller($0).isConnected }
    }

    private func connectAll() {
        let failures = AppDelegate.shared?.connectDetectedAgents(force: true) ?? []
        connected = Set(detected.map(\.id))
        connectError = failures.isEmpty ? nil
            : "Could not connect: " + failures.joined(separator: ", ")
    }
}

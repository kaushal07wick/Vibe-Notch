import AppKit
import SwiftUI
import VibeNotchCore

/// The Settings window — VI-style warm dark panel: sidebar + panes, every
/// backend toggle bound to VNSettings. Presented in a plain titled window
/// (the app has no SwiftUI App scene); content is pure SwiftUI.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        w.title = "Vibe Notch Settings"
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: SettingsRoot())
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private enum Pane: String, CaseIterable {
    case general = "General"
    case sound = "Sound"
    case notifications = "Notifications"
    case privacy = "Privacy"
    case labs = "Labs"

    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .sound: "speaker.wave.2.fill"
        case .notifications: "bell.badge.fill"
        case .privacy: "lock.shield.fill"
        case .labs: "flask.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: .gray
        case .sound: .pink
        case .notifications: .red
        case .privacy: .blue
        case .labs: .purple
        }
    }
}

private struct SettingsRoot: View {
    @State private var selected: Pane = .general

    var body: some View {
        // System Settings look: sidebar of categories, grouped form detail
        NavigationSplitView {
            List(Pane.allCases, id: \.self, selection: Binding(get: { selected }, set: { selected = $0 ?? .general })) { p in
                Label {
                    Text(p.rawValue)
                } icon: {
                    Image(systemName: p.icon)
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(p.iconColor, in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Form { pane(selected) }
                .formStyle(.grouped)
                .navigationTitle(selected.rawValue)
        }
        .frame(width: 660, height: 440)
    }

    @ViewBuilder private func pane(_ p: Pane) -> some View {
        switch p {
        case .general: GeneralPane()
        case .sound: SoundPane()
        case .notifications: NotificationsPane()
        case .privacy: PrivacyPane()
        case .labs: LabsPane()
        }
    }
}

// MARK: - Shared pane atoms



private struct SettingRow<Content: View>: View {
    let label: String
    var caption: String?
    @ViewBuilder var control: Content

    var body: some View {
        LabeledContent {
            control
        } label: {
            Text(label)
            if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct VNToggle: View {
    @State var isOn: Bool
    let write: (Bool) -> Void
    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
            .onChange(of: isOn) { _, v in write(v) }
    }
}

// MARK: - Panes

private struct GeneralPane: View {
    var body: some View {
        SettingRow(label: "Launch at login") {
            VNToggle(isOn: VNSettings.launchAtLogin) { VNSettings.launchAtLogin = $0 }
        }
        SettingRow(label: "Auto-hide when idle",
                   caption: "Disappear entirely when no agent sessions are active.") {
            VNToggle(isOn: VNSettings.autoHideWhenIdle) { VNSettings.autoHideWhenIdle = $0 }
        }
        SettingRow(label: "Undo window",
                   caption: "Hold decisions this long so they can be taken back. 0 sends them instantly.") {
            UndoField()
        }
    }
}

private struct SoundPane: View {
    @State private var volume = VNSettings.soundVolume

    var body: some View {
        SettingRow(label: "Sound alerts") {
            VNToggle(isOn: VNSettings.soundEnabled) { VNSettings.soundEnabled = $0 }
        }
        SettingRow(label: "Volume") {
            Slider(value: $volume, in: 0...1) { editing in
                if !editing {
                    VNSettings.soundVolume = volume
                    SoundManager.shared.play(.done)
                }
            }
            .frame(width: 160)
        }
        Text("Custom packs: drop permission/waiting/done (.wav .aiff .mp3 .m4a) into ~/.vibenotch/sounds")
            .font(.caption).foregroundStyle(.secondary)
    }
}

private struct NotificationsPane: View {
    @State private var escalation = VNSettings.escalationSeconds
    @State private var topic = VNSettings.ntfyTopic

    var body: some View {
        SettingRow(label: "Escalate unanswered permissions",
                   caption: "Repeat the chime and badge while a request sits unanswered. 0 turns it off.") {
            HStack(spacing: 6) {
                TextField("", value: $escalation, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 52)
                    .onSubmit { VNSettings.escalationSeconds = max(0, escalation) }
                Text("sec").foregroundStyle(.secondary)
            }
        }
        SettingRow(label: "Phone pings (ntfy.sh topic)",
                   caption: "Escalations also POST to ntfy.sh/<topic> — subscribe in the ntfy app. Empty = off.") {
            TextField("my-secret-topic", text: $topic)
                .textFieldStyle(.roundedBorder).frame(width: 160)
                .onSubmit { VNSettings.ntfyTopic = topic.trimmingCharacters(in: .whitespaces) }
        }
    }
}

private struct PrivacyPane: View {
    var body: some View {
        SettingRow(label: "Screen-share guard",
                   caption: "While your screen is shared, approval cards queue silently — nothing pops up mid-demo.") {
            VNToggle(isOn: VNSettings.screenShareGuard) { VNSettings.screenShareGuard = $0 }
        }
        SettingRow(label: "Focus-mode guard",
                   caption: "Also hold cards quietly while a macOS Focus is on.") {
            VNToggle(isOn: VNSettings.focusGuard) { VNSettings.focusGuard = $0 }
        }
        SettingRow(label: "Auto-approve safe list",
                   caption: "Simple read-only commands (git status, ls, pwd…) approve silently.") {
            VNToggle(isOn: VNSettings.safeListEnabled) { VNSettings.safeListEnabled = $0 }
        }
        SettingRow(label: "Safe list", caption: "Patterns, user-editable JSON.") {
            Button("Edit…") { NSWorkspace.shared.open(SafeList.url) }
                .controlSize(.small)
        }
        SettingRow(label: "Per-project policies",
                   caption: "Strict folders can disable Bypass / Always Allow / safe-list by path prefix.") {
            Button("Edit…") {
                let url = VNPaths.data.appendingPathComponent("policies.json")
                if !FileManager.default.fileExists(atPath: url.path) {
                    try? Data("[]".utf8).write(to: url)
                }
                NSWorkspace.shared.open(url)
            }
            .controlSize(.small)
        }
    }
}

private struct LabsPane: View {
    @State private var port = VNSettings.dashboardPort

    var body: some View {
        SettingRow(label: "Web dashboard",
                   caption: "Sessions + pending approvals in the browser — handy on an iPad via Tailscale. Toggle from the menu bar.") {
            Button("Open") {
                if let url = URL(string: "http://localhost:\(VNSettings.dashboardPort)") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
        SettingRow(label: "Dashboard port") {
            TextField("", value: $port, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).frame(width: 64)
                .onSubmit { VNSettings.dashboardPort = port }
        }
        SettingRow(label: "Notch over lock screen",
                   caption: "Experimental — keeps the panel visible on the lock screen.") {
            VNToggle(isOn: VNSettings.lockScreenNotch) { VNSettings.lockScreenNotch = $0 }
        }
        Text("CLI: ~/.vibenotch/bin/vibenotch — list · approve · deny · send · interrupt")
            .font(.caption.monospaced()).foregroundStyle(.secondary)
    }
}


private struct UndoField: View {
    @State private var secs = VNSettings.undoSeconds
    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: $secs, format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 44)
                .onSubmit { VNSettings.undoSeconds = max(0, secs) }
            Text("sec").foregroundStyle(.secondary)
        }
    }
}

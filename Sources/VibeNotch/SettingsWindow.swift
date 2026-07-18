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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.title = "Vibe Notch"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(red: 0.11, green: 0.09, blue: 0.08, alpha: 1)
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
}

private struct SettingsRoot: View {
    @State private var pane: Pane = .general

    var body: some View {
        HStack(spacing: 0) {
            // sidebar
            VStack(alignment: .leading, spacing: 2) {
                Text("VIBE NOTCH").font(VNFont.sysMono(9.5, .semibold)).tracking(1.6)
                    .foregroundStyle(VNColor.paper.opacity(0.4))
                    .padding(.bottom, 10).padding(.leading, 8)
                ForEach(Pane.allCases, id: \.self) { p in
                    Button {
                        pane = p
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: p.icon).font(.system(size: 11))
                                .frame(width: 16)
                            Text(p.rawValue).font(.system(size: 12.5, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(pane == p ? VNColor.text : VNColor.muted)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Color.white.opacity(pane == p ? 0.08 : 0),
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(EdgeInsets(top: 40, leading: 12, bottom: 14, trailing: 10))
            .frame(width: 168)
            .background(Color.black.opacity(0.22))

            // pane
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch pane {
                    case .general: GeneralPane()
                    case .sound: SoundPane()
                    case .notifications: NotificationsPane()
                    case .privacy: PrivacyPane()
                    case .labs: LabsPane()
                    }
                }
                .padding(EdgeInsets(top: 40, leading: 22, bottom: 22, trailing: 22))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 560, height: 400)
        .background(Color(hex: 0x1C1714))
        .foregroundStyle(VNColor.text)
    }
}

// MARK: - Shared pane atoms

private struct PaneTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 16, weight: .semibold))
    }
}

private struct SettingRow<Content: View>: View {
    let label: String
    var caption: String?
    @ViewBuilder var control: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12.5))
                if let caption {
                    Text(caption).font(.system(size: 10.5)).foregroundStyle(VNColor.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.vertical, 2)
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
        PaneTitle(text: "General")
        SettingRow(label: "Launch at login") {
            VNToggle(isOn: VNSettings.launchAtLogin) { VNSettings.launchAtLogin = $0 }
        }
        SettingRow(label: "Auto-hide when idle",
                   caption: "Disappear entirely when no agent sessions are active.") {
            VNToggle(isOn: VNSettings.autoHideWhenIdle) { VNSettings.autoHideWhenIdle = $0 }
        }
    }
}

private struct SoundPane: View {
    @State private var volume = VNSettings.soundVolume

    var body: some View {
        PaneTitle(text: "Sound")
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
            .font(.system(size: 10.5)).foregroundStyle(VNColor.faint)
    }
}

private struct NotificationsPane: View {
    @State private var escalation = VNSettings.escalationSeconds
    @State private var topic = VNSettings.ntfyTopic

    var body: some View {
        PaneTitle(text: "Notifications")
        SettingRow(label: "Escalate unanswered permissions",
                   caption: "Repeat the chime and badge while a request sits unanswered. 0 turns it off.") {
            HStack(spacing: 6) {
                TextField("", value: $escalation, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 52)
                    .onSubmit { VNSettings.escalationSeconds = max(0, escalation) }
                Text("sec").font(.system(size: 11)).foregroundStyle(VNColor.muted)
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
        PaneTitle(text: "Privacy & Trust")
        SettingRow(label: "Screen-share guard",
                   caption: "While your screen is shared, approval cards queue silently — nothing pops up mid-demo.") {
            VNToggle(isOn: VNSettings.screenShareGuard) { VNSettings.screenShareGuard = $0 }
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
        PaneTitle(text: "Labs")
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
            .font(VNFont.sysMono(10, .regular)).foregroundStyle(VNColor.faint)
    }
}

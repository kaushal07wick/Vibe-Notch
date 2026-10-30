import AppKit
import SwiftUI
import VibeNotchCore

/// The Settings window. Sidebar + panes, grouped into Setup / Advanced / app,
/// mirroring where people expect each control to live.
///
/// House style, not System Settings': flat tinted tiles with a hairline and a
/// tight 5pt radius (Apple's are glossy gradient squares), mono section
/// headers, and our warm-paper-on-ink palette throughout.
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
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        w.title = "Vibe Notch Settings"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
        w.contentViewController = NSHostingController(rootView: SettingsRoot().tint(VNColor.running).preferredColorScheme(.dark))
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Panes

private enum Pane: String, CaseIterable, Identifiable {
    case general = "General"
    case integrations = "Integrations"
    case notifications = "Notifications"
    case display = "Display"
    case sound = "Sound"
    case usage = "Usage"
    case shortcuts = "Shortcuts"
    case ssh = "SSH Remote"
    case labs = "Labs"
    case about = "About"

    var id: String { rawValue }

    /// Sidebar grouping — matches how often you actually reach for each.
    static let setup: [Pane] = [.general, .integrations, .notifications, .display, .sound, .usage]
    static let advanced: [Pane] = [.shortcuts, .ssh, .labs]
    static let app: [Pane] = [.about]

    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .integrations: "puzzlepiece.extension.fill"
        case .notifications: "bell.fill"
        case .display: "macbook"
        case .sound: "speaker.wave.2.fill"
        case .usage: "gauge.medium"
        case .shortcuts: "keyboard.fill"
        case .ssh: "network"
        case .labs: "flask.fill"
        case .about: "info.circle.fill"
        }
    }

    /// Our palette, not Apple's system colors.
    var tint: Color {
        switch self {
        case .general: VNColor.paper.opacity(0.55)
        case .integrations: VNColor.invader
        case .notifications: VNColor.stop
        case .display: VNColor.running
        case .sound: VNColor.go
        case .usage: VNColor.amber
        case .shortcuts: VNColor.agent("cursor")
        case .ssh: VNColor.agent("codex")
        case .labs: VNColor.agent("qoder")
        case .about: VNColor.agent("claude")
        }
    }

    var blurb: String {
        switch self {
        case .general: "Startup, visibility, and which permissions reach the notch."
        case .integrations: "Which coding agents send their events here."
        case .notifications: "Chasing you when something waits — and when to stay quiet."
        case .display: "Which screen the notch lives on, and how long it stays open."
        case .sound: "Alert tones for permissions, waits, and finishes."
        case .usage: "Plan limits in the panel header, read from local files."
        case .shortcuts: "Keys for approving, jumping, and dismissing."
        case .ssh: "Agents running on other machines, over an SSH tunnel."
        case .labs: "Experiments: web dashboard, lock-screen notch, the CLI."
        case .about: "Version, links, and removing Vibe Notch cleanly."
        }
    }
}

// MARK: - Shell

private struct SettingsRoot: View {
    @State private var selected: Pane = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 208)
                .background(Color(hex: 0x09090B).ignoresSafeArea())
            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PaneHeader(pane: selected)
                    pane(selected)
                }
                .padding(EdgeInsets(top: 14, leading: 26, bottom: 26, trailing: 26))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background(VNColor.ink.ignoresSafeArea())
        }
        .frame(width: 760, height: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                PixelGhost(mood: .working, px: 1.5)
                Text("Vibe Notch").font(.system(size: 14, weight: .semibold))
            }
            .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
            group(Pane.setup)
            label("ADVANCED"); group(Pane.advanced)
            label("APP"); group(Pane.app)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }

    private func label(_ t: String) -> some View {
        Text(t).font(VNFont.sysMono(9.5, .semibold)).tracking(1.2)
            .foregroundStyle(VNColor.faint)
            .padding(EdgeInsets(top: 14, leading: 8, bottom: 4, trailing: 8))
    }

    private func group(_ panes: [Pane]) -> some View {
        ForEach(panes) { p in
            Button { selected = p } label: {
                HStack(spacing: 9) {
                    IconTile(pane: p, size: 20)
                    Text(p.rawValue).font(.system(size: 12.5, weight: selected == p ? .semibold : .regular))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .foregroundStyle(selected == p ? VNColor.paper : VNColor.muted)
                .background(Color.white.opacity(selected == p ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private func pane(_ p: Pane) -> some View {
        switch p {
        case .general: GeneralPane()
        case .integrations: IntegrationsPane()
        case .notifications: NotificationsPane()
        case .display: DisplayPane()
        case .sound: SoundPane()
        case .usage: UsagePane()
        case .shortcuts: ShortcutsPane()
        case .ssh: SSHPane()
        case .labs: LabsPane()
        case .about: AboutPane()
        }
    }
}

private struct SidebarRow: View {
    let pane: Pane
    var body: some View {
        Label { Text(pane.rawValue) } icon: { IconTile(pane: pane, size: 20) }
            .tag(pane)
    }
}

/// Flat tint fill + hairline + tight radius — deliberately not Apple's glossy
/// gradient square, so the window reads as ours at a glance.
private struct IconTile: View {
    let pane: Pane
    var size: CGFloat

    var body: some View {
        Image(systemName: pane.icon)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [pane.tint, pane.tint.opacity(0.62)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .shadow(color: pane.tint.opacity(0.35), radius: 3, y: 1)
    }
}

private struct PaneHeader: View {
    let pane: Pane
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconTile(pane: pane, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.rawValue).font(.system(size: 17, weight: .semibold))
                Text(pane.blurb).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Atoms

/// A titled group of rows. Mono headers are the house voice.
struct SectionCard<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(VNFont.sysMono(10, .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
            }
            VStack(spacing: 0) { content }
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                )
            if let footnote {
                Text(footnote).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingRow<Content: View>: View {
    let label: String
    var caption: String?
    var divider = true
    @ViewBuilder var control: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 13))
                    if let caption {
                        Text(caption).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                control
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            if divider { Divider().opacity(0.35).padding(.leading, 12) }
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

/// Seconds field that commits on Enter *and* on focus loss — a value typed and
/// abandoned used to be silently discarded.
private struct SecondsField: View {
    @State var value: Int
    var width: CGFloat = 52
    var unit = "sec"
    let write: (Int) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder).frame(width: width)
                .focused($focused)
                .onSubmit { write(max(0, value)) }
                .onChange(of: focused) { _, isFocused in if !isFocused { write(max(0, value)) } }
            Text(unit).foregroundStyle(.secondary).font(.caption)
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    var body: some View {

        SectionCard(title: "Panel") {
            SettingRow(label: "Collapse when the pointer leaves",
                       caption: "Off keeps an opened panel up until Esc, a decision, or the dwell timer.",
                       divider: false) {
                VNToggle(isOn: VNSettings.collapseOnLeave) { VNSettings.collapseOnLeave = $0 }
            }
        }
        SectionCard(title: "Startup") {
            SettingRow(label: "Launch at login") {
                VNToggle(isOn: VNSettings.launchAtLogin) { VNSettings.launchAtLogin = $0 }
            }
            SettingRow(label: "Auto-hide when idle",
                       caption: "Disappear entirely when no agent is working — keeps the notch off fullscreen video.") {
                VNToggle(isOn: VNSettings.autoHideWhenIdle) { VNSettings.autoHideWhenIdle = $0 }
            }
            SettingRow(label: "Smart suppression",
                       caption: "Don't pop cards while the agent's own terminal is the app you're looking at.", divider: false) {
                VNToggle(isOn: VNSettings.smartSuppression) { VNSettings.smartSuppression = $0 }
            }
        }

        SectionCard(title: "Approvals",
                    footnote: "Below the threshold, the agent's own terminal prompt handles it — the notch never sees it.") {
            SettingRow(label: "Notch handles",
                       caption: "Which permissions are worth interrupting you for.") {
                MinRiskPicker()
            }
            SettingRow(label: "Undo window",
                       caption: "Hold decisions this long so they can be taken back. 0 sends them instantly.") {
                SecondsField(value: VNSettings.undoSeconds, width: 44) { VNSettings.undoSeconds = $0 }
            }
            SettingRow(label: "Auto-approve safe list",
                       caption: "Simple read-only commands (git status, ls, pwd…) approve silently.") {
                VNToggle(isOn: VNSettings.safeListEnabled) { VNSettings.safeListEnabled = $0 }
            }
            SettingRow(label: "Safe list", caption: "The patterns that qualify. Plain JSON.") {
                Button("Edit…") {
                    _ = SafeList.patterns() // seed the file so there's something to open
                    NSWorkspace.shared.open(SafeList.url)
                }.controlSize(.small)
            }
            SettingRow(label: "Per-project policies",
                       caption: "Strict folders can disable Bypass / Always Allow / safe-list by path prefix.", divider: false) {
                Button("Edit…") {
                    let url = VNPaths.data.appendingPathComponent("policies.json")
                    if !FileManager.default.fileExists(atPath: url.path) {
                        try? Data("[]".utf8).write(to: url)
                    }
                    NSWorkspace.shared.open(url)
                }.controlSize(.small)
            }
        }
    }
}

private struct MinRiskPicker: View {
    @State private var value = VNSettings.notchMinRisk
    var body: some View {
        Picker("", selection: $value) {
            Text("All permissions").tag("low")
            Text("Medium + high risk").tag("medium")
            Text("High risk only").tag("high")
        }
        .labelsHidden().frame(width: 178).controlSize(.small)
        .onChange(of: value) { _, v in VNSettings.notchMinRisk = v }
    }
}

// MARK: - Integrations

private struct IntegrationsPane: View {
    /// Bumped after every connect/disconnect so the rows re-read from disk.
    @State private var revision = 0

    var body: some View {
        SectionCard(title: "CLI Hooks",
                    footnote: "Vibe Notch backs up each config once before its first edit, and removes only its own entries.") {
            ForEach(Array(Agents.all.enumerated()), id: \.element.id) { index, spec in
                AgentRow(spec: spec, isLast: index == Agents.all.count - 1) { revision += 1 }
            }
        }
        .id(revision)

        SectionCard(title: "Setup") {
            SettingRow(label: "Auto-configure new CLIs",
                       caption: "Wire up newly detected agents on launch. Off means Vibe Notch never touches a config you didn't connect yourself.", divider: false) {
                VNToggle(isOn: VNSettings.autoConfigureAgents) { VNSettings.autoConfigureAgents = $0 }
            }
        }
    }
}

private struct AgentRow: View {
    let spec: AgentSpec
    let isLast: Bool
    let changed: () -> Void

    private var installer: AgentHookInstaller { AgentHookInstaller(spec) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                AgentIcon(source: spec.id, size: 18)
                    .opacity(spec.isDetected ? 1 : 0.3)
                Text(spec.name).font(.system(size: 13))
                    .foregroundStyle(spec.isDetected ? .primary : .secondary)
                Spacer(minLength: 12)
                if !spec.isDetected {
                    Text("Not installed").font(.caption).foregroundStyle(.secondary)
                } else if installer.isConnected {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(VNColor.go).labelStyle(.titleAndIcon)
                } else {
                    Label("Off", systemImage: "circle")
                        .font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                }
                Toggle("", isOn: Binding(
                    get: { installer.isConnected },
                    set: { on in toggle(to: on) }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .disabled(!spec.isDetected)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            if !isLast { Divider().opacity(0.35).padding(.leading, 12) }
        }
    }

    private func toggle(to on: Bool) {
        do {
            if on {
                let src = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/vibenotch-hook")
                try installer.connect(hookBinarySource: src)
            } else {
                try installer.disconnect()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not update \(spec.name)"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        changed()
    }
}

// MARK: - Notifications

private struct NotificationsPane: View {
    @State private var topic = VNSettings.ntfyTopic

    var body: some View {
        SectionCard(title: "Follow-up") {
            SettingRow(label: "Escalate unanswered permissions",
                       caption: "Repeat the chime and mark the menu bar while a request sits waiting. 0 turns it off.", divider: false) {
                SecondsField(value: VNSettings.escalationSeconds) { VNSettings.escalationSeconds = $0 }
            }
        }

        SectionCard(title: "Phone",
                    footnote: "Escalations POST to ntfy.sh/<topic> — subscribe in the ntfy app. Nothing else ever leaves your Mac.") {
            SettingRow(label: "ntfy.sh topic",
                       caption: "Pick something unguessable — anyone with the topic sees the notification.", divider: false) {
                TextField("my-secret-topic", text: $topic)
                    .textFieldStyle(.roundedBorder).frame(width: 178)
                    .onSubmit { VNSettings.ntfyTopic = topic.trimmingCharacters(in: .whitespaces) }
            }
        }

        SectionCard(title: "Quiet scenes",
                    footnote: "While a scene is active, cards queue silently — no sound, no auto-expand. The menu-bar count still moves.") {
            SettingRow(label: "Screen is being shared",
                       caption: "Nothing pops open mid-demo. Browser-tab shares can't be detected.") {
                VNToggle(isOn: VNSettings.screenShareGuard) { VNSettings.screenShareGuard = $0 }
            }
            SettingRow(label: "Focus mode is on", divider: false) {
                VNToggle(isOn: VNSettings.focusGuard) { VNSettings.focusGuard = $0 }
            }
        }
    }
}

// MARK: - Display

private struct DisplayPane: View {
    @State private var screenID = VNSettings.notchDisplayID
    @State private var dwell = VNSettings.dwellSeconds

    var body: some View {

        SectionCard(title: "Size",
                    footnote: "Everything in the panel scales together — text, pills and the mono blocks.") {
            SettingRow(label: "Content size",
                       caption: "Larger text in the notch panel. 100% is the default.") {
                Picker("", selection: Binding(
                    get: { VNSettings.contentScale },
                    set: { VNSettings.contentScale = $0 }
                )) {
                    Text("90%").tag(0.9)
                    Text("100%").tag(1.0)
                    Text("110%").tag(1.1)
                    Text("125%").tag(1.25)
                    Text("150%").tag(1.5)
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 92)
            }
            SettingRow(label: "Panel width",
                       caption: "How wide the expanded panel gets, in points.",
                       divider: false) {
                SecondsField(value: VNSettings.panelWidth, width: 62, unit: "pt") {
                    VNSettings.panelWidth = min(1000, max(420, $0))
                }
            }
        }
        SectionCard(title: "Notch",
                    footnote: "If the chosen display is unplugged, the notch falls back to the main one.") {
            SettingRow(label: "Display",
                       caption: "Which screen the notch appears on.", divider: false) {
                Picker("", selection: $screenID) {
                    Text("Main Display").tag("")
                    ForEach(NSScreen.screens, id: \.vnDisplayID) { screen in
                        Text(screen.localizedName).tag(screen.vnDisplayID)
                    }
                }
                .labelsHidden().frame(width: 178).controlSize(.small)
                .onChange(of: screenID) { _, v in VNSettings.notchDisplayID = v }
            }
        }

        SectionCard(title: "Behavior") {
            SettingRow(label: "Hover dwell",
                       caption: "How long a hover-opened panel stays up before collapsing itself. Cards with a decision waiting ignore this.", divider: false) {
                HStack(spacing: 8) {
                    Slider(value: $dwell, in: 2...15, step: 0.5) { editing in
                        if !editing { VNSettings.dwellSeconds = dwell }
                    }
                    .frame(width: 132)
                    Text("\(dwell, specifier: "%.1f")s")
                        .font(VNFont.sysMono(11)).foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Sound

private struct SoundPane: View {
    @State private var volume = VNSettings.soundVolume
    @State private var theme = VNSettings.soundTheme

    var body: some View {
        SectionCard(title: "Alerts",
                    footnote: "Custom pack: drop permission / waiting / done (.wav .aiff .mp3 .m4a) into ~/.vibenotch/sounds to override the synth tones.") {
            SettingRow(label: "Sound alerts") {
                VNToggle(isOn: VNSettings.soundEnabled) { VNSettings.soundEnabled = $0 }
            }
            SettingRow(label: "Theme", caption: "Three synthesized voices — no audio files needed.") {
                Picker("", selection: $theme) {
                    Text("Chime").tag("chime")
                    Text("Arcade").tag("arcade")
                    Text("Minimal").tag("minimal")
                }
                .labelsHidden().frame(width: 140).controlSize(.small)
                .onChange(of: theme) { _, v in
                    VNSettings.soundTheme = v
                    SoundManager.shared.play(.done)
                }
            }
            SettingRow(label: "Volume", divider: false) {
                Slider(value: $volume, in: 0...1) { editing in
                    if !editing {
                        VNSettings.soundVolume = volume
                        SoundManager.shared.play(.done)
                    }
                }
                .frame(width: 178)
            }
        }
    }
}

// MARK: - Usage

private struct UsagePane: View {
    @State private var connected = StatusLineInstaller.isInstalled

    var body: some View {
        SectionCard(title: "Usage limits") {
            SettingRow(label: "Show usage limits",
                       caption: "Plan windows in the expanded panel header.", divider: false) {
                VNToggle(isOn: VNSettings.showUsageLimits) { VNSettings.showUsageLimits = $0 }
            }
        }

        SectionCard(title: "Claude usage bridge",
                    footnote: "Read from local files only — no API keys, no accounts, no network. Codex usage needs no setup; it comes from its own session logs.") {
            SettingRow(label: "Status line bridge",
                       caption: connected
                           ? "Connected. Your own status line output is unchanged — we only tee the rate-limit numbers."
                           : "Claude reports its limits to the status line. Vibe Notch wraps yours to read them.") {
                if connected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(VNColor.go)
                } else {
                    Button("Connect usage") {
                        StatusLineInstaller.installIfNeeded()
                        connected = StatusLineInstaller.isInstalled
                    }.controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    @State private var revision = 0
    @State private var axGranted = AccessibilityPermission.granted
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        SectionCard(title: "Global") {
            SettingRow(label: "Enable keyboard shortcuts",
                       caption: "Turn every shortcut off without losing the mappings.") {
                VNToggle(isOn: VNSettings.shortcutsEnabled) { VNSettings.shortcutsEnabled = $0 }
            }
            // Without Accessibility the global monitor never fires and the keys
            // look broken. This is where people come looking.
            SettingRow(label: "Accessibility permission",
                       caption: axGranted
                           ? "Granted — shortcuts work in any app."
                           : "Not granted — shortcuts only work while the notch panel is focused.",
                       divider: false) {
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
        }
        .onReceive(poll) { _ in axGranted = AccessibilityPermission.granted }

        SectionCard(title: "Keys",
                    footnote: "Click a shortcut to record a new one, ⌫ to clear, esc to cancel. Outside the panel these need Accessibility permission, granted once in System Settings › Privacy & Security.") {
            ForEach(Array(VNAction.allCases.enumerated()), id: \.element.id) { index, action in
                SettingRow(label: action.title, caption: action.caption,
                           divider: index < VNAction.allCases.count - 1) {
                    ShortcutField(action: action) { revision += 1 }
                }
            }
        }
        .id(revision)

        SectionCard(title: "Panel") {
            SettingRow(label: "Command palette",
                       caption: "Search sessions, resume history, approve all. Built into the panel — not rebindable.",
                       divider: false) {
                KeyCap(text: "⌘K")
            }
        }
    }
}

private struct KeyCap: View {
    let text: String
    var muted = false
    var body: some View {
        Text(text)
            .font(VNFont.sysMono(11, .semibold))
            .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }
}

/// Click to arm, then the next key combination is captured. Refuses a
/// combination another action already owns — silently shadowing an existing
/// binding is how you get a shortcut that mysteriously stops working.
private struct ShortcutField: View {
    let action: VNAction
    let changed: () -> Void

    @State private var recording = false
    @State private var conflict: VNAction?

    var body: some View {
        HStack(spacing: 6) {
            if let conflict {
                Text("used by \(conflict.title)")
                    .font(.caption).foregroundStyle(VNColor.stop)
            }
            Button {
                recording.toggle()
                conflict = nil
            } label: {
                if recording {
                    KeyCap(text: "Recording…", muted: true)
                } else if let shortcut = VNShortcuts.get(action) {
                    KeyCap(text: shortcut.display)
                } else {
                    KeyCap(text: "unassigned", muted: true)
                }
            }
            .buttonStyle(.plain)
            .background(KeyRecorder(active: $recording, onKey: capture))

            Button {
                VNShortcuts.reset(action)
                changed()
            } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 10))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Reset to \(action.defaultShortcut.display)")
        }
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 { recording = false; return }        // esc cancels
        if event.keyCode == 51 {                                     // delete clears
            VNShortcuts.set(nil, for: action)
            recording = false
            changed()
            return
        }
        guard let shortcut = VNShortcut(event: event) else { return } // needs a modifier
        if let owner = VNShortcuts.conflict(shortcut, excluding: action) {
            conflict = owner
            recording = false
            return
        }
        VNShortcuts.set(shortcut, for: action)
        recording = false
        changed()
    }
}

/// Swallows the next key event while armed. SwiftUI has no key-capture
/// primitive, so this is an AppKit view that takes first responder on demand.
private struct KeyRecorder: NSViewRepresentable {
    @Binding var active: Bool
    let onKey: (NSEvent) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onKey = onKey
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onKey = onKey
        if active, view.window?.firstResponder !== view {
            view.window?.makeFirstResponder(view)
        } else if !active, view.window?.firstResponder === view {
            view.window?.makeFirstResponder(nil)
        }
    }

    final class CaptureView: NSView {
        var onKey: ((NSEvent) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) { onKey?(event) }
        /// Menu equivalents (⌘Q, ⌘W…) never reach keyDown — intercept them so
        /// they can be recorded instead of quitting the app mid-capture.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            onKey?(event)
            return true
        }
    }
}

// MARK: - SSH Remote

/// Concrete `Host` aliases from ~/.ssh/config (wildcards and negations skipped),
/// following one level of `Include`.
private enum SSHConfigHosts {
    static func aliases() -> [String] {
        var seen = Set<String>(), out: [String] = []
        let ssh = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        func read(_ url: URL, depth: Int) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            for raw in text.split(whereSeparator: \.isNewline) {
                let parts = raw.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "=" }).map(String.init)
                guard let key = parts.first?.lowercased(), parts.count > 1 else { continue }
                if key == "host" {
                    for name in parts.dropFirst() where !name.contains(where: { "*?!".contains($0) }) {
                        if seen.insert(name).inserted { out.append(name) }
                    }
                } else if key == "include", depth == 0 {
                    for pattern in parts.dropFirst() {
                        let path = pattern.hasPrefix("/") ? pattern : pattern.hasPrefix("~") ? (pattern as NSString).expandingTildeInPath : ssh.appendingPathComponent(pattern).path
                        var g = glob_t()
                        if glob(path, 0, nil, &g) == 0 {
                            for i in 0..<Int(g.gl_pathc) { if let c = g.gl_pathv[i] { read(URL(fileURLWithPath: String(cString: c)), depth: 1) } }
                        }
                        globfree(&g)
                    }
                }
            }
        }
        read(ssh.appendingPathComponent("config"), depth: 0)
        return out
    }
}

private struct SSHPane: View {
    @State private var servers = SSHRemote.load()
    @State private var aliases = SSHConfigHosts.aliases()
    @State private var busy = false
    @State private var tick = Date()
    @ObservedObject private var tunnels = AppDelegate.shared?.tunnels ?? SSHTunnelManager()
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        // Explanation, not a control — a row with an empty trailing slot reads
        // like a setting whose switch failed to draw.
        VStack(alignment: .leading, spacing: 6) {
            Text("Monitor and approve agents running on another machine.")
                .font(.system(size: 13))
            Text("Requires key-based SSH auth. Vibe Notch deploys a small Python hook client and keeps an auto-reconnecting reverse tunnel; approvals ride back over it. Remote sessions show a host badge, and Always Allow stays allow-once for them — persistent rules belong on the server.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))

        SectionCard(title: "Hosts") {
            if servers.isEmpty {
                SettingRow(label: "No hosts configured yet", divider: true) { EmptyView() }
            } else {
                ForEach(Array(servers.enumerated()), id: \.element.host) { index, server in
                    SettingRow(label: server.host,
                               caption: status(for: server),
                               divider: true) {
                        HStack(spacing: 8) {
                            Circle().fill(statusColor(for: server)).frame(width: 7, height: 7)
                            Button("Remove") {
                                AppDelegate.shared?.tunnels.removeServer(host: server.host)
                                servers = SSHRemote.load()
                            }.controlSize(.small)
                        }
                    }
                }
            }
            SettingRow(label: "Add a host", caption: "user@hostname", divider: !pending.isEmpty) {
                Button(busy ? "Deploying…" : "Add Host…") { addHost() }
                    .controlSize(.small).disabled(busy)
            }
        }
        // Keeps the retry countdown ticking.
        .onReceive(poll) { tick = $0 }

        if !pending.isEmpty {
            SectionCard(title: "From ~/.ssh/config",
                        footnote: "Adding deploys the hook client to that machine over SSH, so it only happens when you ask.") {
                SettingRow(label: "\(pending.count) host\(pending.count == 1 ? "" : "s") found",
                           caption: "Every alias in your SSH config.", divider: true) {
                    Button(busy ? "Deploying…" : "Add all") { add(pending) }
                        .controlSize(.small).disabled(busy)
                }
                ForEach(Array(pending.enumerated()), id: \.element) { index, alias in
                    SettingRow(label: alias, divider: index < pending.count - 1) {
                        Button("Add") { add([alias]) }.controlSize(.small).disabled(busy)
                    }
                }
            }
        }
    }

    private var pending: [String] {
        let have = Set(servers.map(\.host))
        return aliases.filter { !have.contains($0) }
    }

    private func add(_ hosts: [String]) {
        guard let delegate = AppDelegate.shared else { return }
        busy = true
        Task { @MainActor in
            var failures: [String] = []
            for host in hosts {
                if let error = await delegate.tunnels.addServer(host: host) { failures.append("\(host): \(error)") }
                servers = SSHRemote.load()
            }
            busy = false
            if !failures.isEmpty {
                let fail = NSAlert()
                fail.messageText = "SSH deploy failed for \(failures.count) host\(failures.count == 1 ? "" : "s")"
                fail.informativeText = failures.joined(separator: "\n")
                fail.runModal()
            }
        }
    }

    /// Live tunnel state, not the stored enabled flag — that said "Connected"
    /// whether or not anything was actually connected.
    private func status(for server: SSHServer) -> String {
        guard server.enabled else { return "Disabled" }
        switch tunnels.state[server.host] {
        case .up(let since):
            return "Connected · up \(ageString(since))"
        case .retrying(let at, let reason):
            let secs = max(0, Int(at.timeIntervalSince(tick)))
            return "\(reason) — retrying in \(secs)s"
        case .connecting:
            return "Connecting…"
        case .stopped, .none:
            return "Not connected"
        }
    }

    private func statusColor(for server: SSHServer) -> Color {
        guard server.enabled else { return .secondary.opacity(0.4) }
        switch tunnels.state[server.host] {
        case .up: return VNColor.go
        case .retrying: return VNColor.amber
        default: return .secondary.opacity(0.5)
        }
    }

    private func addHost() {
        let alert = NSAlert()
        alert.messageText = "Add SSH Server"
        alert.informativeText = "user@host, with key-based auth. Vibe Notch deploys its hook client and opens a reverse tunnel."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "deploy@my-server"
        alert.accessoryView = field
        alert.addButton(withTitle: "Deploy & Connect")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let host = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, let delegate = AppDelegate.shared else { return }
        busy = true
        Task { @MainActor in
            if let error = await delegate.tunnels.addServer(host: host) {
                let fail = NSAlert()
                fail.messageText = "SSH deploy failed"
                fail.informativeText = error
                fail.runModal()
            }
            servers = SSHRemote.load()
            busy = false
        }
    }
}

// MARK: - Labs

private struct LabsPane: View {
    @State private var port = VNSettings.dashboardPort
    @State private var dashboardOn = VNSettings.dashboardPort > 0

    var body: some View {
        SectionCard(title: "Web dashboard",
                    footnote: "Bound to 127.0.0.1 only. The page is read-only; approve/deny need a token printed to the log at startup.") {
            SettingRow(label: "Run the dashboard",
                       caption: "Sessions and pending approvals in a browser.") {
                VNToggle(isOn: dashboardOn) { on in
                    dashboardOn = on
                    VNSettings.dashboardPort = on ? (port > 0 ? port : 4141) : 0
                    AppDelegate.shared?.applyDashboardSetting()
                }
            }
            SettingRow(label: "Port", divider: false) {
                HStack(spacing: 8) {
                    TextField("", value: $port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).frame(width: 64)
                        .onSubmit {
                            VNSettings.dashboardPort = dashboardOn ? port : 0
                            AppDelegate.shared?.applyDashboardSetting()
                        }
                    Button("Open") {
                        if let url = URL(string: "http://127.0.0.1:\(VNSettings.dashboardPort)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small).disabled(!dashboardOn)
                }
            }
        }

        SectionCard(title: "Experiments") {
            SettingRow(label: "Notch over lock screen",
                       caption: "Pins the panel into a max-level window space. Uses a private API — expect weirdness.", divider: false) {
                VNToggle(isOn: VNSettings.lockScreenNotch) { on in
                    VNSettings.lockScreenNotch = on
                    AppDelegate.shared?.applyLockScreenSetting()
                }
            }
        }

        SectionCard(title: "Command line",
                    footnote: "Add ~/.vibenotch/bin to your PATH for a bare `vibenotch`.") {
            SettingRow(label: "vibenotch",
                       caption: "list · approve · deny · send · interrupt · model", divider: false) {
                Text("~/.vibenotch/bin")
                    .font(VNFont.sysMono(11)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            PixelGhost(mood: .working, px: 6)
            Text("Vibe Notch").font(.system(size: 19, weight: .semibold))
            Text(version).font(VNFont.sysMono(11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)

        SectionCard {
            LinkRow(label: "Source & releases", value: "GitHub",
                    url: "https://github.com/kaushal07wick/Vibe-Notch")
            LinkRow(label: "Report a bug", value: "Issues",
                    url: "https://github.com/kaushal07wick/Vibe-Notch/issues")
            LinkRow(label: "License", value: "GPL-3.0", divider: false,
                    url: "https://github.com/kaushal07wick/Vibe-Notch/blob/master/LICENSE")
        }

        SectionCard(title: "Remove",
                    footnote: "Unhooks every agent config, leaving your own hooks and status line intact. The app and ~/.vibenotch stay — delete them yourself.") {
            SettingRow(label: "Disconnect all agents",
                       caption: "Stop sending events here, without uninstalling.", divider: false) {
                Button("Disconnect…", role: .destructive) { disconnectAll() }
                    .controlSize(.small)
            }
        }
    }

    private func disconnectAll() {
        let connected = Agents.all.filter { AgentHookInstaller($0).isConnected }
        let alert = NSAlert()
        alert.messageText = "Disconnect \(connected.count) agent\(connected.count == 1 ? "" : "s")?"
        alert.informativeText = connected.isEmpty
            ? "Nothing is connected right now."
            : "Removes Vibe Notch's hooks from: " + connected.map(\.name).joined(separator: ", ")
        alert.addButton(withTitle: "Disconnect")
        alert.addButton(withTitle: "Cancel")
        guard !connected.isEmpty, alert.runModal() == .alertFirstButtonReturn else { return }
        for spec in connected { try? AgentHookInstaller(spec).disconnect() }
        // Otherwise the next launch would helpfully wire them all back up.
        VNSettings.autoConfigureAgents = false
    }
}

private struct LinkRow: View {
    let label: String
    let value: String
    var divider = true
    let url: String

    var body: some View {
        SettingRow(label: label, divider: divider) {
            Button {
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            } label: {
                HStack(spacing: 4) {
                    Text(value)
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                }
            }
            .buttonStyle(.link)
        }
    }
}

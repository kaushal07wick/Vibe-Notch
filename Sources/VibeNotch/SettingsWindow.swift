import AppKit
import SwiftUI

/// The Settings window — SwiftUI content bound to VNSettings, presented in a
/// plain titled window (the app has no SwiftUI App scene to hang Settings on).
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
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        w.title = "Vibe Notch Settings"
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: SettingsView())
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsView: View {
    @State private var launchAtLogin = VNSettings.launchAtLogin
    @State private var autoHide = VNSettings.autoHideWhenIdle
    @State private var soundOn = VNSettings.soundEnabled
    @State private var volume = VNSettings.soundVolume

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in VNSettings.launchAtLogin = v }
                Toggle("Auto-hide when no active sessions", isOn: $autoHide)
                    .onChange(of: autoHide) { _, v in VNSettings.autoHideWhenIdle = v }
            }
            Section("Sound") {
                Toggle("Sound alerts", isOn: $soundOn)
                    .onChange(of: soundOn) { _, v in VNSettings.soundEnabled = v }
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $volume, in: 0...1) { editing in
                        if !editing {
                            VNSettings.soundVolume = volume
                            SoundManager.shared.play(.done) // preview at new volume
                        }
                    }
                    .disabled(!soundOn)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                Text("Drop custom sounds in ~/.vibenotch/sounds — permission/waiting/done (.wav, .aiff, .mp3, .m4a).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 320)
    }
}

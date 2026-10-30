import SwiftUI
import VibeNotchCore

// Root notch content. DynamicNotchKit draws the notch shape, background, and
// morph; these views supply the expanded panel and the compact flanks.

/// The expanded panel: approval card > decision flash > session activity.
struct ExpandedContent: View {
    @ObservedObject var store: EventStore
    @ObservedObject var usage: UsageModel

    @AppStorage("soundEnabled") private var soundOn = true
    @AppStorage("showUsageLimits") private var showUsage = true
    @AppStorage("contentScale") private var contentScale = 1.0
    @AppStorage("panelWidth") private var panelWidth = 620
    @State private var showHistory = false
    @State private var showPalette = false
    @State private var history: [ResumeEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            // stats header — usage left, history + mute + settings right (VI layout)
            HStack(spacing: 12) {
                if showUsage && !usage.providers.isEmpty {
                    UsageChips(providers: usage.providers)
                }
                Spacer(minLength: 8)
                // ⌘K palette — keyboard-only, no icon (header stays quiet)
                Button("") { showPalette.toggle(); if showPalette { showHistory = false } }
                    .keyboardShortcut("k", modifiers: .command)
                    .frame(width: 0, height: 0).opacity(0)
                    .accessibilityHidden(true) // invisible shortcut host, not a control
                HeaderIconButton(symbol: "clock.arrow.circlepath",
                                 tint: showHistory ? VNColor.go : .white.opacity(0.62),
                                 label: "Session history") {
                    if !showHistory { history = SessionHistory.load() }
                    showHistory.toggle()
                    if showHistory { showPalette = false }
                }
                HeaderIconButton(
                    symbol: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    tint: soundOn ? .white.opacity(0.62) : .orange.opacity(0.92),
                    label: soundOn ? "Mute alerts" : "Unmute alerts"
                ) {
                    soundOn.toggle() // @AppStorage — same key VNSettings reads, always in sync
                }
                HeaderIconButton(symbol: "gearshape.fill", tint: .white.opacity(0.62),
                                 label: "Settings") {
                    SettingsWindow.show()
                }
            }
            .padding(.horizontal, 16).padding(.top, -26).padding(.bottom, 3)
            // while-you-were-away digest (backend clears it after a few seconds)
            if let digest = store.digest {
                HStack(spacing: 7) {
                    Image(systemName: "moon.zzz.fill").font(VNFont.ui(10))
                        .foregroundStyle(VNColor.running)
                    Text(digest).font(VNFont.ui(10.5, .medium))
                        .foregroundStyle(VNColor.muted).lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.vertical, 4)
            }

            // screen-share guard: cards are queued silently while sharing
            if store.privacyHold && !store.pending.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill").font(VNFont.ui(10))
                    Text("\(store.pending.count) approval\(store.pending.count == 1 ? "" : "s") held while screen sharing")
                        .font(VNFont.ui(10.5, .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(VNColor.amber)
                .padding(.horizontal, 20).padding(.vertical, 3)
            }
            ZStack {
                if showPalette {
                    PaletteView(store: store) { showPalette = false }
                } else if showHistory && store.pending.isEmpty {
                    HistoryList(entries: history) { showHistory = false }
                } else {
                    currentCard
                        .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity),
                                                removal: .opacity))
                }
            }
        }
        .foregroundStyle(VNColor.text)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: stateKey)
        .onChange(of: store.pending.isEmpty) { _, empty in
            if !empty { showHistory = false } // approvals always take the stage
        }
    }

    /// Identity of the visible state — drives the cross-fade/scale transition.
    /// (Decision flash intentionally not rendered — the card resolving away is
    /// the confirmation, matching Vibe Island.)
    private var stateKey: String {
        if let a = store.pending.first { return "approval-\(a.id)" }
        let active = store.activeSessions
        guard let s = active.first else { return "idle" }
        return "act-\(active.count)-\(s.id)-\(s.event)"
    }

    @ViewBuilder private var currentCard: some View {
        if let approval = store.pending.first {
            ApprovalCard(approval: approval, store: store, queued: store.pending.count - 1).id(approval.id)
        } else {
            ActivityCard(store: store, sessions: store.activeSessions, full: store.hovering,
                         onDismiss: { store.dismiss(sessionId: $0) })
        }
    }
}

// MARK: - Compact flanks (either side of the physical notch)

/// One animated pixel invader per active agent, in its brand color.
struct CompactLeading: View {
    @ObservedObject var store: EventStore
    var body: some View {
        HStack(spacing: 4) {
            // OUR mascot — the Owl — regardless of which brands are running
            // (per-agent marks live in the expanded rows)
            PixelInvader(color: store.escalated ? VNColor.amber : VNColor.running,
                         px: 1.5, animated: anyRunning)
            // activity is a dot beside the owl, not a second creature
            Circle()
                .fill(store.escalated ? VNColor.amber : VNColor.running)
                .frame(width: 4, height: 4)
                .opacity(anyRunning ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: anyRunning)
        }
        // mirror-width flanks keep the shape centred on the physical notch
        .frame(width: 38)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.escalated ? "Vibe Notch, a permission is waiting"
                                            : anyRunning ? "Vibe Notch, agents working" : "Vibe Notch, idle")
    }

    private var anyRunning: Bool {
        store.activeSessions.contains { ["PreToolUse", "PostToolUse", "UserPromptSubmit"].contains($0.event) }
    }

    /// Distinct agents that have a live session, most-recent first.
    private var activeAgents: [String] {
        var seen = Set<String>(); var out: [String] = []
        for s in store.activeSessions where !seen.contains(s.source) {
            seen.insert(s.source); out.append(s.source)
        }
        return out
    }
}

/// Active-session count (or a dim idle dot).
struct CompactTrailing: View {
    @ObservedObject var store: EventStore
    var body: some View {
        Group {
            if store.undo != nil {
                // decision in its undo window — tap the glyph to take it back
                Button { store.undoLast() } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(VNFont.ui(10)).foregroundStyle(VNColor.amber)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo the last decision")
                .help("Undo the last decision")
            } else if store.privacyHold && !store.pending.isEmpty {
                // shared screen: a lock instead of the count — no info leaked
                Image(systemName: "lock.fill").font(VNFont.ui(8))
                    .foregroundStyle(VNColor.amber)
            } else if needsYou > 0 {
                // something is waiting on you — amber, and the number is what's waiting
                Text("\(needsYou)")
                    .font(VNFont.ui(10.5, .bold)).monospacedDigit()
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5).background(VNColor.amber, in: Capsule())
                    .accessibilityLabel("\(needsYou) waiting for you")
            } else if count > 0 {
                Text("\(count)")
                    .font(VNFont.ui(10.5, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(VNColor.text)
                    .accessibilityLabel("\(count) active session\(count == 1 ? "" : "s")")
            } else {
                Circle().fill(VNColor.faint).frame(width: 4, height: 4)
            }
        }
        // mirror of CompactLeading — equal width keeps the notch split evenly
        .frame(width: 32)
        .padding(.horizontal, 2)
    }
    private var count: Int { max(store.pending.count, store.activeSessions.count) }
    private var needsYou: Int { store.pending.count + store.activeSessions.filter { $0.event == "Notification" }.count }
}

/// Tiny live mic-level meter for the dictation pill.

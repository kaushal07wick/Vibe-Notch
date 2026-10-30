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
    @State private var historyLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // stats header — usage left, history + mute + settings right (VI layout)
            HStack(spacing: 12) {
                if showUsage && !usage.providers.isEmpty {
                    UsageChips(providers: usage.providers)
                }
                if let n = StatsLog.today()["sessions"], n > 0 {
                    Text("\(n) today").font(VNFont.ui(10.5, .medium)).foregroundStyle(VNColor.muted)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.07), in: Capsule())
                        .help("Sessions today — see History")
                }
                Spacer(minLength: 8)
                // ⌘K palette — keyboard-only, no icon (header stays quiet)
                Button("") { showPalette.toggle(); if showPalette { showHistory = false } }
                    .keyboardShortcut("k", modifiers: .command)
                    .frame(width: 0, height: 0).opacity(0)
                    .accessibilityHidden(true) // invisible shortcut host, not a control
                HeaderIconButton(symbol: store.showWidgets ? "music.note.house.fill" : "music.note.house",
                                 tint: store.showWidgets ? VNColor.running : .white.opacity(0.62),
                                 label: "Music and calendar") {
                    store.showWidgets.toggle()
                    if store.showWidgets { store.showTray = false; showHistory = false; showPalette = false }
                }
                HeaderIconButton(symbol: store.showTray ? "tray.full.fill" : "tray",
                                 tint: store.showTray ? VNColor.running : .white.opacity(0.62),
                                 label: "File tray") {
                    store.showTray.toggle()
                    if store.showTray { store.showWidgets = false; showHistory = false; showPalette = false }
                }
                HeaderIconButton(symbol: "clock.arrow.circlepath",
                                 tint: showHistory ? VNColor.go : .white.opacity(0.62),
                                 label: "Session history") {
                    if !showHistory {
                        store.showTray = false; store.showWidgets = false
                        historyLoading = true
                        Task.detached {
                            let loaded = SessionHistory.load()
                            await MainActor.run { history = loaded; historyLoading = false }
                        }
                    }
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
                } else if store.showWidgets && store.pending.isEmpty {
                    WidgetsView()
                } else if store.showTray && store.pending.isEmpty {
                    TrayView()
                } else if showHistory && store.pending.isEmpty {
                    HistoryList(entries: history, loading: historyLoading) { showHistory = false }
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
        } else if let question = store.codexQuestion {
            CodexQuestionCard(store: store, question: question).id("\(question.id)-\(store.codexQuestionStep)")
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Mood { case idle, working, waiting }
    private var mood: Mood {
        if store.escalated || needsYou { return .waiting }
        return anyRunning ? .working : .idle
    }

    var body: some View {
        // Pixel-snapped motion only (1pt steps), so the sprite never blurs:
        // working hops on the beat, waiting shakes for attention, idle just breathes.
        TimelineView(.animation(minimumInterval: 0.15, paused: mood == .idle && reduceMotion)) { ctx in
            let tick = Int(ctx.date.timeIntervalSinceReferenceDate / 0.15)
            let still = reduceMotion
            let dy: CGFloat = mood == .working && !still && tick % 4 < 2 ? -1 : 0
            let dx: CGFloat = mood == .waiting && !still ? (tick % 2 == 0 ? -1 : 1) : 0
            let breathe = mood == .idle ? (0.45 + 0.2 * (tick / 6 % 2 == 0 ? 1 : 0)) : 1
            let color = mood == .waiting ? VNColor.amber : VNColor.running
            HStack(spacing: 4) {
                PixelGhost(mood: mood == .waiting ? .waiting : mood == .working ? .working : .idle, px: 1.5)
                    .offset(x: dx, y: dy)
                    .opacity(breathe)
                Circle().fill(color).frame(width: 4, height: 4)
                    .opacity(mood == .idle ? 0 : (mood == .working && !still && tick % 8 >= 4 ? 0.35 : 1))
            }
        }
        // mirror-width flanks keep the shape centred on the physical notch
        .frame(width: 38)
        .onDrop(of: [.fileURL], isTargeted: nil) { TrayStore.handleDrop($0) { store.showTray = true } }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mood == .waiting ? "Vibe Notch, something is waiting for you"
                                             : mood == .working ? "Vibe Notch, agents working" : "Vibe Notch, idle")
    }

    private var needsYou: Bool {
        !store.pending.isEmpty || store.activeSessions.contains { $0.event == "Notification" }
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
        .onDrop(of: [.fileURL], isTargeted: nil) { TrayStore.handleDrop($0) { store.showTray = true } }
        .padding(.horizontal, 2)
    }
    private var count: Int { max(store.pending.count, store.activeSessions.count) }
    private var needsYou: Int { store.pending.count + store.activeSessions.filter { $0.event == "Notification" }.count }
}

/// Tiny live mic-level meter for the dictation pill.

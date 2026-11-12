import SwiftUI
import VibeNotchCore

// Root notch content. DynamicNotchKit draws the notch shape, background, and
// morph; these views supply the expanded panel and the compact flanks.

/// The expanded panel: approval card > decision flash > session activity.
struct ExpandedContent: View {
    @ObservedObject var store: EventStore
    @ObservedObject var usage: UsageModel

    @AppStorage("interfaceStyle") private var styleID = VNInterfaceStyle.classic.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var interfaceStyle: VNInterfaceStyle { VNInterfaceStyle(rawValue: styleID) ?? .classic }
    @AppStorage("soundEnabled") private var soundOn = true
    @AppStorage("showUsageLimits") private var showUsage = true
    @AppStorage("contentScale") private var contentScale = 1.0
    @AppStorage("panelWidth") private var panelWidth = 620
    @State private var showHistory = false
    @State private var showPalette = false
    @State private var history: [ResumeEntry] = []
    @State private var historyLoading = false

    private var contentWidth: CGFloat {
        let idle = store.activeSessions.isEmpty && store.pending.isEmpty && store.codexQuestion == nil
            && !store.showWidgets && !store.showTray && !showHistory && !showPalette && store.timelineSessionID == nil
        return idle ? min(max(420, cameraWidth + 220), VNSettings.effectivePanelWidth) : VNSettings.effectivePanelWidth
    }

    private var cameraHeight: CGFloat { VNSettings.notchScreen?.safeAreaInsets.top ?? 0 }
    private var cameraWidth: CGFloat {
        guard let screen = VNSettings.notchScreen,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return 0 }
        return screen.frame.width - left.width - right.width
    }

    private var toolbarWingWidth: CGFloat {
        max(0, (contentWidth - 16 - cameraWidth - (cameraWidth > 0 ? 24 : 0)) / 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            // stats header — usage left, history + mute + settings right (VI layout)
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                // ⌘K palette — keyboard-only, no icon (header stays quiet)
                Button("") { showPalette.toggle(); if showPalette { showHistory = false; store.timelineSessionID = nil } }
                    .keyboardShortcut("k", modifiers: .command)
                    .frame(width: 0, height: 0).opacity(0)
                    .accessibilityHidden(true) // invisible shortcut host, not a control
                HeaderIconButton(symbol: store.showWidgets ? "music.note.house.fill" : "music.note.house",
                                 tint: store.showWidgets ? VNColor.running : .white.opacity(0.62),
                                 label: "Music and calendar") {
                    store.showWidgets.toggle()
                    if store.showWidgets { store.showTray = false; showHistory = false; showPalette = false; store.timelineSessionID = nil }
                }
                HeaderIconButton(symbol: store.showTray ? "tray.full.fill" : "tray",
                                 tint: store.showTray ? VNColor.running : .white.opacity(0.62),
                                 label: "File tray") {
                    store.showTray.toggle()
                    if store.showTray { store.showWidgets = false; showHistory = false; showPalette = false; store.timelineSessionID = nil }
                }
                }
                .frame(width: toolbarWingWidth, alignment: .leading)
                // This space belongs to the physical camera, never to a button.
                Color.clear.frame(width: cameraWidth + (cameraWidth > 0 ? 24 : 0), height: 1)
                HStack(spacing: 8) {
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
                    if showHistory { showPalette = false; store.timelineSessionID = nil }
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
                .contextMenu {
                    ForEach(VNInterfaceStyle.allCases) { style in
                        Button { styleID = style.rawValue } label: {
                            if style == interfaceStyle { Label(style.title, systemImage: "checkmark") }
                            else { Text(style.title) }
                        }
                    }
                }
                }
                .frame(width: toolbarWingWidth, alignment: .trailing)
            }
            // Reuse the camera row reserved by DynamicNotchKit, with controls
            // in its two wings. The card starts directly below the cutout.
            .padding(.horizontal, 8)
            .frame(height: max(28, cameraHeight))
            .padding(.top, cameraHeight > 0 ? -cameraHeight : 0)
            .padding(.bottom, 4)
            if showUsage && !usage.providers.isEmpty {
                HStack {
                    UsageChips(providers: usage.providers)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.bottom, 6)
            }
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
                        .transition(interfaceStyle == .classic && !reduceMotion
                            ? .asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity)
                            : .opacity)
                }
            }
        }
        .frame(width: contentWidth)
        .foregroundStyle(VNColor.text)
        .environment(\.vnInterfaceStyle, interfaceStyle)
        .animation(reduceMotion ? .easeOut(duration: 0.1) : interfaceStyle.contentAnimation, value: stateKey)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: styleID)
        .onChange(of: store.timelineSessionID) { _, selected in
            if selected != nil { showHistory = false; showPalette = false; store.showTray = false; store.showWidgets = false }
        }
        .onChange(of: store.pending.isEmpty) { _, empty in
            if !empty { showHistory = false } // approvals always take the stage
        }
    }

    /// Identity of the visible state — drives the cross-fade/scale transition.
    /// (Decision flash intentionally not rendered — the card resolving away is
    /// the confirmation, matching Vibe Island.)
    private var stateKey: String {
        if let a = store.pending.first { return "approval-\(a.id)" }
        if let id = store.timelineSessionID { return "timeline-\(id)" }
        let active = store.activeSessions
        guard let s = active.first else { return "idle" }
        return "act-\(active.count)-\(s.id)-\(s.event)"
    }

    @ViewBuilder private var currentCard: some View {
        if let approval = store.pending.first {
            ApprovalCard(approval: approval, store: store, queued: store.pending.count - 1).id(approval.id)
        } else if let question = store.codexQuestion {
            CodexQuestionCard(store: store, question: question).id("\(question.id)-\(store.codexQuestionStep)")
        } else if let id = store.timelineSessionID {
            SessionTimelineView(store: store, sessionID: id)
        } else if !store.hovering, let id = store.justFinished, let done = store.sessions[id] {
            ActivityCard(store: store, sessions: [done], full: false, onDismiss: { store.dismiss(sessionId: $0) })
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
    @AppStorage("interfaceStyle") private var styleID = VNInterfaceStyle.classic.rawValue
    private var interfaceStyle: VNInterfaceStyle { VNInterfaceStyle(rawValue: styleID) ?? .classic }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Mood { case idle, working, waiting }
    private var mood: Mood {
        if store.escalated || needsYou { return .waiting }
        return anyRunning ? .working : .idle
    }

    var body: some View {
        // Pixel-snapped motion only (1pt steps), so the sprite never blurs:
        // working hops on the beat, waiting shakes for attention, idle just breathes.
        TimelineView(.animation(minimumInterval: interfaceStyle == .classic ? 0.15 : 1,
                                paused: mood == .idle && (reduceMotion || interfaceStyle != .classic))) { ctx in
            let tick = Int(ctx.date.timeIntervalSinceReferenceDate / 0.15)
            let still = reduceMotion || interfaceStyle != .classic
            let dy: CGFloat = mood == .working && !still && tick % 4 < 2 ? -1 : 0
            let dx: CGFloat = mood == .waiting && !still ? (tick % 2 == 0 ? -1 : 1) : 0
            let breathe = mood == .idle ? (0.45 + 0.2 * (tick / 6 % 2 == 0 ? 1 : 0)) : 1
            let color = mood == .waiting ? VNColor.amber : VNColor.running
            HStack(spacing: 4) {
                if interfaceStyle == .classic {
                    PixelGhost(mood: mood == .waiting ? .waiting : mood == .working ? .working : .idle, px: 1.5,
                               sweat: store.activeSessions.contains { ($0.contextTokens).map(ContextChip.percent) ?? 0 >= 85 })
                        .offset(x: dx, y: dy).opacity(breathe)
                } else {
                    InterfaceStyleMark(style: interfaceStyle, size: 18, waiting: mood == .waiting, active: mood != .idle)
                }
                Circle().fill(color).frame(width: 4, height: 4)
                    .opacity(mood == .idle ? 0 : (mood == .working && !still && tick % 8 >= 4 ? 0.35 : 1))
            }
        }
        // mirror-width flanks keep the shape centred on the physical notch
        .frame(width: 32)
        .offset(y: -3)
        .onDrop(of: [.fileURL], isTargeted: nil) { TrayStore.handleDrop($0) { store.showTray = true } }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mood == .waiting ? "Vibe Notch, something is waiting for you"
                                             : mood == .working ? "Vibe Notch, agents working" : "Vibe Notch, idle")
    }

    private var needsYou: Bool {
        !store.pending.isEmpty || store.codexQuestion != nil || store.activeSessions.contains { store.phase(for: $0).needsAttention }
    }

    private var anyRunning: Bool {
        store.activeSessions.contains { store.phase(for: $0) == .working }
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
    @AppStorage("interfaceStyle") private var styleID = VNInterfaceStyle.classic.rawValue
    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let count = max(store.pending.count, store.activeSessions.filter { store.phase(for: $0, now: context.date).isBusy }.count)
            let needsYou = waitingCount(at: context.date)
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
        .offset(y: -3)
        .onDrop(of: [.fileURL], isTargeted: nil) { TrayStore.handleDrop($0) { store.showTray = true } }
        .padding(.horizontal, 2)
    }
    private func waitingCount(at now: Date) -> Int {
        let pendingSessions = Set(store.pending.compactMap { $0.inbound.sessionId })
        let observedWaiting = store.activeSessions.filter {
            !pendingSessions.contains($0.id) && store.phase(for: $0, now: now).needsAttention
        }.count
        return store.pending.count + observedWaiting
    }
}

/// Tiny live mic-level meter for the dictation pill.

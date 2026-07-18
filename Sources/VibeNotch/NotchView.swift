import SwiftUI
import VibeNotchCore

// Root notch content. DynamicNotchKit draws the notch shape, background, and
// morph; these views supply the expanded panel and the compact flanks.

/// The expanded panel: approval card > decision flash > session activity.
struct ExpandedContent: View {
    @ObservedObject var store: EventStore
    @ObservedObject var usage: UsageModel

    @AppStorage("soundEnabled") private var soundOn = true
    @State private var showHistory = false
    @State private var showPalette = false
    @State private var history: [ResumeEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            // stats header — usage left, history + mute + settings right (VI layout)
            HStack(spacing: 12) {
                if !usage.providers.isEmpty {
                    UsageChips(providers: usage.providers)
                }
                Spacer(minLength: 8)
                // ⌘K palette — keyboard-only, no icon (header stays quiet)
                Button("") { showPalette.toggle(); if showPalette { showHistory = false } }
                    .keyboardShortcut("k", modifiers: .command)
                    .frame(width: 0, height: 0).opacity(0)
                HeaderIconButton(symbol: "clock.arrow.circlepath",
                                 tint: showHistory ? VNColor.go : .white.opacity(0.62)) {
                    if !showHistory { history = SessionHistory.load() }
                    showHistory.toggle()
                    if showHistory { showPalette = false }
                }
                HeaderIconButton(
                    symbol: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    tint: soundOn ? .white.opacity(0.62) : .orange.opacity(0.92)
                ) {
                    soundOn.toggle() // @AppStorage — same key VNSettings reads, always in sync
                }
                HeaderIconButton(symbol: "gearshape.fill", tint: .white.opacity(0.62)) {
                    SettingsWindow.show()
                }
            }
            .padding(.horizontal, 20).padding(.top, -26).padding(.bottom, 4)
            // while-you-were-away digest (backend clears it after a few seconds)
            if let digest = store.digest {
                HStack(spacing: 7) {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 10))
                        .foregroundStyle(VNColor.running)
                    Text(digest).font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(VNColor.muted).lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.vertical, 4)
            }

            // screen-share guard: cards are queued silently while sharing
            if store.privacyHold && !store.pending.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 10))
                    Text("\(store.pending.count) approval\(store.pending.count == 1 ? "" : "s") held while screen sharing")
                        .font(.system(size: 10.5, weight: .medium))
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
                        .id(stateKey)
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
            ApprovalCard(approval: approval, store: store, queued: store.pending.count - 1)
        } else {
            ActivityCard(sessions: store.activeSessions, full: store.hovering,
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
            OwlMark(px: 1.1, escalated: store.escalated)
            // …and the orbit spinner while any session works
            PixelSpinner(active: anyRunning)
        }
        // mirror-width flanks keep the shape centred on the physical notch
        .frame(width: 32)
        .padding(.horizontal, 2)
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
                        .font(.system(size: 10)).foregroundStyle(VNColor.amber)
                }
                .buttonStyle(.plain)
                .help("Undo the last decision")
            } else if store.privacyHold && !store.pending.isEmpty {
                // shared screen: a lock instead of the count — no info leaked
                Image(systemName: "lock.fill").font(.system(size: 8))
                    .foregroundStyle(VNColor.amber)
            } else if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(VNColor.text)
            } else {
                Circle().fill(VNColor.faint).frame(width: 4, height: 4)
            }
        }
        // mirror of CompactLeading — equal width keeps the notch split evenly
        .frame(width: 32)
        .padding(.horizontal, 2)
    }
    private var count: Int { max(store.pending.count, store.activeSessions.count) }
}

/// Tiny live mic-level meter for the dictation pill.

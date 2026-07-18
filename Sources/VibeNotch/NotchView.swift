import SwiftUI
import VibeNotchCore

// Root notch content. DynamicNotchKit draws the notch shape, background, and
// morph; these views supply the expanded panel and the compact flanks.

/// The expanded panel: approval card > decision flash > session activity.
struct ExpandedContent: View {
    @ObservedObject var store: EventStore
    @ObservedObject var usage: UsageModel

    @State private var muted = !SoundManager.shared.enabled
    @State private var showHistory = false
    @State private var history: [ResumeEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            // stats header — usage left, history + mute + settings right (VI layout)
            HStack(spacing: 12) {
                if !usage.providers.isEmpty {
                    UsageChips(providers: usage.providers)
                }
                Spacer(minLength: 8)
                HeaderIconButton(symbol: "clock.arrow.circlepath",
                                 tint: showHistory ? VNColor.go : .white.opacity(0.62)) {
                    if !showHistory { history = SessionHistory.load() }
                    showHistory.toggle()
                }
                HeaderIconButton(
                    symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    tint: muted ? .orange.opacity(0.92) : .white.opacity(0.62)
                ) {
                    SoundManager.shared.enabled.toggle()
                    muted = !SoundManager.shared.enabled
                }
                HeaderIconButton(symbol: "gearshape.fill", tint: .white.opacity(0.62)) {
                    SettingsWindow.show()
                }
            }
            .padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 2)
            ZStack {
                if showHistory && store.pending.isEmpty {
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
        Group {
            // subtle: a single tiny invader — amber when a permission has been
            // waiting too long (escalation), else the most recent agent's color
            PixelInvader(color: store.escalated ? VNColor.amber
                         : activeAgents.first.map(VNColor.agent) ?? VNColor.invader, px: 1)
        }
        // physical notch is ~166pt; ~12pt flanks keep the shape barely wider + centred
        .frame(width: 12)
        .padding(.horizontal, 2)
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
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(VNColor.text)
            } else {
                Circle().fill(VNColor.faint).frame(width: 4, height: 4)
            }
        }
        // mirror of CompactLeading — equal width keeps the notch split evenly
        .frame(width: 12)
        .padding(.horizontal, 2)
    }
    private var count: Int { max(store.pending.count, store.activeSessions.count) }
}

import SwiftUI
import VibeNotchCore

// Root notch content. DynamicNotchKit draws the notch shape, background, and
// morph; these views supply the expanded panel and the compact flanks.

/// The expanded panel: approval card > decision flash > session activity.
struct ExpandedContent: View {
    @ObservedObject var store: EventStore
    @ObservedObject var usage: UsageModel

    var body: some View {
        VStack(spacing: 0) {
            if !usage.providers.isEmpty {
                UsageChips(providers: usage.providers)
                    .padding(.horizontal, 18).padding(.top, 5).padding(.bottom, 2)
            }
            ZStack {
                currentCard
                    .id(stateKey)
                    .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
        .foregroundStyle(VNColor.text)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: stateKey)
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
        HStack(spacing: 8) {
            if activeAgents.isEmpty {
                PixelInvader(color: VNColor.invader, px: 3) // idle mascot
            } else {
                ForEach(activeAgents, id: \.self) { PixelInvader(color: VNColor.agent($0), px: 2.5) }
            }
        }
        .padding(.leading, 15).padding(.trailing, 9)
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
                    .font(.system(size: 14.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(VNColor.text)
            } else {
                Circle().fill(VNColor.faint).frame(width: 6, height: 6)
            }
        }
        .padding(.trailing, 16).padding(.leading, 9)
    }
    private var count: Int { max(store.pending.count, store.activeSessions.count) }
}

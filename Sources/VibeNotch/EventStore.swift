import Foundation
import VibeNotchCore

/// A pending Claude permission request awaiting the user's decision.
/// `reply` signals the blocked hook connection with the chosen decision.
struct PendingApproval: Identifiable {
    let id = UUID()
    let inbound: VNInbound
    let reply: @Sendable (VNDecision) -> Void
}

/// Drives the notch UI: the approval queue, the latest notification, and a
/// brief post-decision flash. Notifications and flashes auto-clear.
@MainActor
final class EventStore: ObservableObject {
    @Published var pending: [PendingApproval] = []
    @Published var lastNotification: VNInbound?
    @Published var flash: VNDecision?
    @Published var hovering = false

    private var noteGen = 0

    func enqueue(_ approval: PendingApproval) {
        pending.append(approval)
    }

    func resolve(_ approval: PendingApproval, _ decision: VNDecision) {
        approval.reply(decision)
        pending.removeAll { $0.id == approval.id }
        showFlash(decision)
    }

    func note(_ inbound: VNInbound) {
        lastNotification = inbound
        noteGen += 1
        scheduleClear(noteGen)
    }

    /// Auto-dismiss after a few seconds — but keep it up while the user is reading (hovering).
    private func scheduleClear(_ generation: Int) {
        Task {
            try? await Task.sleep(for: .seconds(5))
            guard generation == noteGen else { return }
            if hovering { scheduleClear(generation) } else { lastNotification = nil }
        }
    }

    private func showFlash(_ decision: VNDecision) {
        flash = decision
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            if pending.isEmpty { flash = nil }
        }
    }
}

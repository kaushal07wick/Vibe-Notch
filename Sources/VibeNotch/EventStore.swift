import Foundation
import VibeNotchCore

/// A pending Claude permission request awaiting the user's decision.
/// `reply` signals the blocked hook connection with the chosen decision.
struct PendingApproval: Identifiable {
    let id = UUID()
    let inbound: VNInbound
    let reply: @Sendable (VNDecision) -> Void
}

/// Drives the notch UI. Holds the approval queue and the latest notification.
@MainActor
final class EventStore: ObservableObject {
    @Published var pending: [PendingApproval] = []
    @Published var lastNotification: VNInbound?

    func enqueue(_ approval: PendingApproval) {
        pending.append(approval)
    }

    func resolve(_ approval: PendingApproval, _ decision: VNDecision) {
        approval.reply(decision)
        pending.removeAll { $0.id == approval.id }
    }

    func note(_ inbound: VNInbound) {
        lastNotification = inbound
    }
}

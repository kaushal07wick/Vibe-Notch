import SwiftUI
import VibeNotchCore

/// Root notch content. Renders the top pending approval, else the latest
/// notification, else a compact idle pill.
struct NotchView: View {
    @ObservedObject var store: EventStore

    var body: some View {
        VStack(spacing: 0) {
            if let approval = store.pending.first {
                ApprovalCard(approval: approval, store: store)
            } else if let note = store.lastNotification {
                NotificationPill(inbound: note)
            } else {
                IdlePill()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ApprovalCard: View {
    let approval: PendingApproval
    @ObservedObject var store: EventStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                Text(approval.inbound.tool ?? approval.inbound.event)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(approval.inbound.source.uppercased())
                    .font(.system(size: 10, weight: .bold)).opacity(0.55)
            }
            if let detail = approval.inbound.detail {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(2).truncationMode(.middle)
                    .opacity(0.85)
            }
            HStack(spacing: 8) {
                Button("Deny") { store.resolve(approval, .deny) }
                    .buttonStyle(PillButton(tint: .red))
                Button("Approve") { store.resolve(approval, .allow) }
                    .buttonStyle(PillButton(tint: .green))
            }
        }
        .padding(12)
        .frame(width: 376, alignment: .leading)
        .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.white)
    }
}

private struct NotificationPill: View {
    let inbound: VNInbound
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.fill").font(.system(size: 11))
            Text(inbound.detail ?? inbound.event)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(width: 320, alignment: .leading)
        .background(.black.opacity(0.9), in: Capsule())
        .foregroundStyle(.white)
    }
}

private struct IdlePill: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 11))
            Text("Vibe Notch").font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(.black.opacity(0.85), in: Capsule())
        .foregroundStyle(.white)
    }
}

private struct PillButton: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(tint.opacity(configuration.isPressed ? 0.5 : 0.85), in: Capsule())
            .foregroundStyle(.white)
    }
}

import SwiftUI
import VibeNotchCore

/// Read-only event history. This does not replay commands or restore files.
struct SessionTimelineView: View {
    @ObservedObject var store: EventStore
    let sessionID: String

    private var entries: [ActivityTimelineEntry] {
        Array(store.timeline.entries(for: sessionID).reversed())
    }

    private var title: String {
        if let session = store.sessions[sessionID] {
            return session.customTitle ?? session.folder ?? agentName(session.source)
        }
        return entries.first.map { agentName($0.source) } ?? "Session"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { store.timelineSessionID = nil } label: {
                    Label("Sessions", systemImage: "chevron.left")
                        .font(VNFont.ui(11, .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(VNColor.muted)
                Spacer(minLength: 8)
                Text("Activity timeline").font(VNFont.ui(12, .semibold))
            }
            Text(title).font(VNFont.ui(11, .medium)).lineLimit(1)
                .foregroundStyle(VNColor.muted)
            if entries.isEmpty {
                Text("No activity recorded yet.")
                    .font(VNFont.ui(12)).foregroundStyle(VNColor.muted)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            row(entry)
                            if entry.id != entries.last?.id {
                                Divider().overlay(VNColor.hair).padding(.leading, 19)
                            }
                        }
                    }
                }
                .frame(height: min(260, CGFloat(entries.count) * 72))
            }
            Text("Events observed by Vibe-Notch. Saved on this Mac for up to 7 days.")
                .font(VNFont.ui(9.5)).foregroundStyle(VNColor.faint)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
        .frame(width: VNSettings.effectivePanelWidth, alignment: .leading)
    }

    private func row(_ entry: ActivityTimelineEntry) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol(entry)).font(VNFont.ui(10, .medium))
                .foregroundStyle(tint(entry)).frame(width: 11).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.title).font(VNFont.ui(11.5, .medium))
                    if let tool = entry.tool {
                        Text(tool).font(VNFont.sysMono(9.5)).foregroundStyle(VNColor.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(entry.timestamp, format: .dateTime.hour().minute().second())
                        .font(VNFont.sysMono(9)).foregroundStyle(VNColor.faint)
                }
                if let detail = entry.detail {
                    Text(detail).font(VNFont.uiMono(10)).foregroundStyle(VNColor.muted)
                        .lineLimit(3).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(entry.origin == .transcript ? "Observed in session log" : "Received from agent")
                    .font(VNFont.ui(9)).foregroundStyle(VNColor.faint)
            }
        }
        .padding(.vertical, 9)
    }

    private func symbol(_ entry: ActivityTimelineEntry) -> String {
        switch entry.kind {
        case .approvalRequested: return "hand.raised"
        case .approvalDecision:
            switch entry.outcome {
            case "deny": return "xmark.circle"
            case "ask": return "arrow.turn.up.right"
            case "held": return "clock"
            case "undone": return "arrow.uturn.backward"
            default: return "checkmark.circle"
            }
        case .approvalCancelled: return "minus.circle"
        case .activity: return entry.origin == .transcript ? "doc.text" : "circle.fill"
        }
    }

    private func tint(_ entry: ActivityTimelineEntry) -> Color {
        switch entry.kind {
        case .approvalRequested: return VNColor.amber
        case .approvalDecision:
            if entry.outcome == "deny" { return VNColor.stop }
            if ["ask", "held", "undone"].contains(entry.outcome ?? "") { return VNColor.muted }
            return VNColor.go
        case .approvalCancelled: return VNColor.muted
        case .activity: return VNColor.running
        }
    }
}

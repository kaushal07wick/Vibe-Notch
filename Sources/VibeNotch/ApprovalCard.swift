import SwiftUI
import VibeNotchCore

/// The permission card: folder · task, You-line, tool warning, boxed command,
/// and the four decision buttons.
struct ApprovalCard: View {
    let approval: PendingApproval
    @ObservedObject var store: EventStore
    let queued: Int
    private var i: VNInbound { approval.inbound }

    /// Plan-review mode: `ExitPlanMode` carries the Markdown plan for approval.
    private var isPlanReview: Bool { i.tool == "ExitPlanMode" && i.plan != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isPlanReview, let plan = i.plan {
                planLine
                planBlock(plan)
                planButtons
            } else {
                toolLine
                commandBlock
                buttons
            }
            if queued > 0 {
                Text("Show all \(queued + 1) sessions")
                    .font(.system(size: 11)).foregroundStyle(VNColor.faint)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 1)
            }
        }
        .padding(EdgeInsets(top: 6, leading: 15, bottom: 10, trailing: 15))
        .frame(width: 540)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            AgentIcon(source: i.source)
            VStack(alignment: .leading, spacing: 2) {
                Text(sessionTitle(folder: (i.cwd as NSString?)?.lastPathComponent, task: i.title))
                    .font(.system(size: 13.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                if let user = i.userMessage {
                    Text("You: \(user)").font(.system(size: 11)).foregroundStyle(VNColor.muted)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            PillCluster(source: i.source, model: i.model, terminal: i.terminal, tty: i.tty)
        }
    }

    private var toolLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(VNColor.amber)
            Text(i.tool ?? "Tool").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(VNColor.amber)
            Spacer(minLength: 0)
        }
    }

    private var commandBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            (Text("$ ").foregroundStyle(VNColor.amber) + Text(i.detail ?? "").foregroundStyle(Color(hex: 0xE7E8E4)))
                .font(VNFont.mono(11.5)).lineLimit(3).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            if let desc = i.commandDescription {
                Text(desc).font(.system(size: 11)).foregroundStyle(VNColor.muted).lineLimit(1)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(VNColor.ink2, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(VNColor.hair))
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            WideButton(title: "Deny", kind: .deny) { store.resolve(approval, .deny) }
            WideButton(title: "Allow Once", kind: .primary) { store.resolve(approval, .allow) }
            WideButton(title: "Always Allow", kind: .always) { store.resolve(approval, .alwaysAllow) }
            WideButton(title: "Bypass", kind: .danger) { store.resolve(approval, .bypass) }
        }
    }

    // MARK: Plan review

    private var planLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text").font(.system(size: 10)).foregroundStyle(VNColor.running)
            Text("Plan ready for review").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(VNColor.running)
            Spacer(minLength: 0)
        }
    }

    private func planBlock(_ plan: String) -> some View {
        ScrollView {
            Text(planAttributed(plan))
                .font(.system(size: 11.5))
                .foregroundStyle(VNColor.text.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 230)
        .background(VNColor.ink2, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(VNColor.hair))
    }

    /// Markdown → AttributedString; falls back to plain text if parsing fails.
    private func planAttributed(_ plan: String) -> AttributedString {
        (try? AttributedString(
            markdown: plan,
            options: .init(allowsExtendedAttributes: false,
                           interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(plan)
    }

    private var planButtons: some View {
        HStack(spacing: 8) {
            WideButton(title: "Keep planning", kind: .deny) { store.resolve(approval, .deny) }
            WideButton(title: "Approve plan", kind: .primary) { store.resolve(approval, .allow) }
        }
    }
}

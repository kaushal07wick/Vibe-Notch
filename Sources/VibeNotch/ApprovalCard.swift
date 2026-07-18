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
            if let questions = i.questions, !questions.isEmpty {
                QuestionPrompt(questions: questions) { store.answer(approval, answers: $0) }
            } else if isPlanReview, let plan = i.plan {
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
        .padding(EdgeInsets(top: 4, leading: 20, bottom: 10, trailing: 20))
        .frame(width: 620)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            // mascot + pixel status badge — "?" while a decision is pending (VI style)
            HStack(alignment: .top, spacing: 3) {
                AgentIcon(source: i.source, size: 22)
                PixelGlyph(grid: PixelGlyph.question, color: VNColor.agent(i.source), px: 2.2)
                    .offset(y: -2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(sessionTitle(folder: (i.cwd as NSString?)?.lastPathComponent, task: i.title))
                    .font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                if let user = i.userMessage {
                    Text("You: \(user)").font(.system(size: 10.5)).foregroundStyle(VNColor.muted)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            PillCluster(source: i.source, terminal: i.terminal, tty: i.tty)
        }
    }

    private var toolLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(VNColor.amber)
            Text(i.tool ?? "Tool").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(VNColor.amber)
            Spacer(minLength: 0)
        }
    }

    /// VI card: the FULL command up to `maxLines`, then a dim "+N lines"
    /// marker, with the description at the bottom of the same box.
    private var commandBlock: some View {
        let maxLines = 12
        let all = (i.detail ?? "").components(separatedBy: "\n")
        let shown = all.prefix(maxLines).joined(separator: "\n")
        let overflow = all.count - maxLines
        return VStack(alignment: .leading, spacing: 6) {
            (Text("$ ").foregroundStyle(VNColor.amber) + Text(shown).foregroundStyle(VNColor.paper.opacity(0.82)))
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if overflow > 0 {
                Text("+\(overflow) lines").font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(VNColor.paper.opacity(0.35))
            }
            if let desc = i.commandDescription {
                Text(desc).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VNColor.paper.opacity(0.5)).lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            WideButton(title: "Deny", kind: .deny) { store.resolve(approval, .deny) }
            WideButton(title: "Allow Once", kind: .primary, hint: "^A") { store.resolve(approval, .allow) }
            // Always Allow only when the agent offers a rule (backend seam:
            // VNInbound.permissionSuggestions — requested on the board)
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

// MARK: - AskUserQuestion

/// Renders agent questions with tappable options. Single question, single
/// select → tapping answers immediately (VI's "Tap to select"). Otherwise
/// selections accumulate and an Answer button submits one label per question.
private struct QuestionPrompt: View {
    let questions: [VNQuestion]
    let submit: ([String]) -> Void
    @State private var picked: [Int: Set<String>] = [:]

    private var instant: Bool { questions.count == 1 && !questions[0].multiSelect }
    private var complete: Bool { (0..<questions.count).allSatisfy { !(picked[$0] ?? []).isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(questions.enumerated()), id: \.offset) { qi, q in
                VStack(alignment: .leading, spacing: 6) {
                    Text(q.question)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(VNColor.paper.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(q.options, id: \.label) { opt in
                        optionRow(qi: qi, q: q, opt: opt)
                    }
                }
            }
            if !instant {
                WideButton(title: "Answer", kind: .primary) {
                    submit(questions.indices.map { (picked[$0] ?? []).sorted().joined(separator: ", ") })
                }
                .disabled(!complete)
                .opacity(complete ? 1 : 0.4)
            }
        }
    }

    private func optionRow(qi: Int, q: VNQuestion, opt: VNQuestion.Option) -> some View {
        let isOn = picked[qi]?.contains(opt.label) ?? false
        return Button {
            if instant { submit([opt.label]); return }
            var set = picked[qi] ?? []
            if q.multiSelect {
                if isOn { set.remove(opt.label) } else { set.insert(opt.label) }
            } else {
                set = [opt.label]
            }
            picked[qi] = set
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isOn ? VNColor.invader : VNColor.faint)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(opt.label).font(.system(size: 11.8, weight: .medium)).foregroundStyle(VNColor.text)
                    if let d = opt.description, !d.isEmpty {
                        Text(d).font(.system(size: 10.5)).foregroundStyle(VNColor.muted)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(isOn ? 0.07 : 0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(isOn ? VNColor.invader.opacity(0.5) : Color.white.opacity(0.05)))
    }
}

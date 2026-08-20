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
                if i.diffOld != nil || i.diffNew != nil {
                    diffBlock
                } else {
                    commandBlock
                }
                buttons
            }
            if queued > 0 {
                HStack(spacing: 14) {
                    Text("Show all \(queued + 1) sessions")
                        .font(VNFont.ui(11)).foregroundStyle(VNColor.faint)
                    Button { store.approveAll() } label: {
                        Text("Approve all \(queued + 1)")
                            .font(VNFont.ui(11, .semibold)).foregroundStyle(VNColor.go)
                    }
                    .buttonStyle(PressFeedback())
                }
                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 1)
            }
        }
        .padding(EdgeInsets(top: 4, leading: 20, bottom: 10, trailing: 20))
        .frame(width: CGFloat(VNSettings.panelWidth))
        .background(riskTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(riskBorder, lineWidth: risk == .high ? 1.2 : 0.8))
        .padding(.horizontal, 4)
    }

    /// High risk earns a red cast, medium a faint amber one, low nothing.
    private var riskTint: Color {
        switch risk {
        case .high: VNColor.stop.opacity(0.07)
        case .medium: VNColor.amber.opacity(0.035)
        case .low: .clear
        }
    }

    private var riskBorder: Color {
        switch risk {
        case .high: VNColor.stop.opacity(0.55)
        case .medium: VNColor.amber.opacity(0.28)
        case .low: .clear
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            AgentIcon(source: i.source, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // "?" belongs on the line it qualifies, not floating off
                    // the mascot's shoulder.
                    PixelGlyph(grid: PixelGlyph.question, color: VNColor.amber, px: 2)
                    Text(sessionTitle(folder: (i.cwd as NSString?)?.lastPathComponent, task: i.title))
                        .font(VNFont.ui(13, .semibold)).lineLimit(1).truncationMode(.tail)
                }
                if let user = i.userMessage {
                    Text("You: \(user)").font(VNFont.ui(11)).foregroundStyle(VNColor.muted)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            PillCluster(source: i.source, terminal: i.terminal, tty: i.tty)
        }
    }

    private var toolLine: some View {
        let tint = risk == .high ? VNColor.stop : VNColor.amber
        return HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(VNFont.ui(9)).foregroundStyle(tint)
            Text(i.tool ?? "Tool").font(VNFont.ui(11.5, .semibold)).foregroundStyle(tint)
            if risk == .high {
                Text("HIGH RISK").font(VNFont.sysMono(9, .semibold)).tracking(0.8)
                    .foregroundStyle(VNColor.stop)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(VNColor.stop.opacity(0.14), in: Capsule())
            }
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
                .font(VNFont.uiMono(11.5, .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if overflow > 0 {
                Text("+\(overflow) lines").font(VNFont.ui(10.5, .medium))
                    .foregroundStyle(VNColor.paper.opacity(0.35))
            }
            if let desc = i.commandDescription {
                Text(desc).font(VNFont.ui(11, .medium))
                    .foregroundStyle(VNColor.paper.opacity(0.5)).lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }

    private var risk: Risk { RiskGrader.grade(tool: i.tool, detail: i.detail) }

    private var buttons: some View {
        HStack(spacing: 8) {
            WideButton(title: "Deny", kind: .deny) { store.resolve(approval, .deny) }
            WideButton(title: "Allow Once", kind: .primary, hint: "^A") { store.resolve(approval, .allow) }
            // Always Allow only when the agent offers a rule (backend seam:
            // VNInbound.permissionSuggestions — requested on the board)
            WideButton(title: "Bypass", kind: .danger) { store.resolve(approval, .bypass) }
        }
    }

    /// Side-by-side minus/plus block for Edit/Write approvals.
    private var diffBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let old = i.diffOld, !old.isEmpty {
                diffLines(old, prefix: "-", color: VNColor.stop)
            }
            if let new = i.diffNew, !new.isEmpty {
                diffLines(new, prefix: "+", color: VNColor.go)
            }
            if let desc = i.commandDescription {
                Text(desc).font(VNFont.ui(11, .medium))
                    .foregroundStyle(VNColor.paper.opacity(0.5)).lineLimit(1).padding(.top, 3)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }

    private func diffLines(_ text: String, prefix: String, color: Color) -> some View {
        let lines = text.components(separatedBy: "\n")
        let shown = lines.prefix(6)
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                Text("\(prefix) \(line)")
                    .font(VNFont.uiMono(11, .medium))
                    .foregroundStyle(color.opacity(0.9))
                    .lineLimit(1).truncationMode(.tail)
            }
            if lines.count > 6 {
                Text("\(prefix) +\(lines.count - 6) lines").font(VNFont.ui(10))
                    .foregroundStyle(color.opacity(0.5))
            }
        }
    }

    // MARK: Plan review

    private var planLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text").font(VNFont.ui(10)).foregroundStyle(VNColor.running)
            Text("Plan ready for review").font(VNFont.ui(12.5, .semibold)).foregroundStyle(VNColor.running)
            Spacer(minLength: 0)
        }
    }

    private func planBlock(_ plan: String) -> some View {
        ScrollView {
            Text(planAttributed(plan))
                .font(VNFont.ui(11.5))
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

/// White pill that fills red while held — releases the approval at 100%.

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
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(questions.enumerated()), id: \.offset) { qi, q in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                if questions.count > 1 {
                                    Text("\(qi + 1)/\(questions.count)")
                                        .font(VNFont.sysMono(9.5, .semibold))
                                        .foregroundStyle(VNColor.faint)
                                }
                                Text(q.question)
                                    .font(VNFont.ui(12, .semibold))
                                    .foregroundStyle(VNColor.paper.opacity(0.86))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(q.options, id: \.label) { opt in
                                optionRow(qi: qi, q: q, opt: opt)
                            }
                        }
                    }
                }
                .padding(.trailing, 2)
            }
            // Cap it and let it scroll — the Answer button has to stay reachable.
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
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
                    .font(VNFont.ui(11))
                    .foregroundStyle(isOn ? VNColor.invader : VNColor.faint)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(opt.label).font(VNFont.ui(11.8, .medium)).foregroundStyle(VNColor.text)
                    if let d = opt.description, !d.isEmpty {
                        Text(d).font(VNFont.ui(10.5)).foregroundStyle(VNColor.muted)
                            .lineLimit(2).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
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

import AppKit
import VibeNotchCore

/// User-triggered setup and repairs always show the concrete file changes first.
@MainActor
enum HookConnectionReview {
    @discardableResult static func apply(_ plans: [HookChangePlan]) throws -> Bool {
        guard !plans.isEmpty else { return false }
        var byPath: [URL: HookChangePlan.FileChange] = [:]
        var ordered: [HookChangePlan.FileChange] = []
        for plan in plans {
            for change in plan.changes {
                if let existing = byPath[change.url] {
                    guard existing.before == change.before, existing.after == change.after else {
                        throw HookChangePlan.ChangeError.changedSinceReview(change.url.path)
                    }
                    continue
                }
                byPath[change.url] = change
                ordered.append(change)
            }
        }
        let combined = HookChangePlan(agentName: plans.map(\.agentName).joined(separator: ", "),
                                      connecting: plans.allSatisfy(\.connecting),
                                      events: plans.flatMap { plan in plan.events.map { "\(plan.agentName): \($0)" } },
                                      changes: ordered)
        let alert = NSAlert()
        alert.messageText = combined.connecting ? "Review agent connection" : "Review hook removal"
        alert.informativeText = "Review the paths and changes below. Existing files will be backed up; other integrations stay in place."
        alert.addButton(withTitle: combined.connecting ? "Apply changes" : "Remove hooks")
        alert.addButton(withTitle: "Cancel")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 620, height: 300))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.string = combined.reviewText
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        alert.accessoryView = scroll
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        try combined.apply()
        return true
    }
}

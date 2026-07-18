import AppKit

/// Notices when you leave (screen lock / display sleep) and come back, so the
/// store can show a "while you were away" digest.
@MainActor
final class AwayTracker {
    var onReturn: ((Date) -> Void)?
    private var awaySince: Date?

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                              object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.markAway() }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                              object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.markBack() }
        }
        let dist = DistributedNotificationCenter.default()
        dist.addObserver(forName: .init("com.apple.screenIsLocked"),
                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.markAway() }
        }
        dist.addObserver(forName: .init("com.apple.screenIsUnlocked"),
                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.markBack() }
        }
    }

    private func markAway() {
        if awaySince == nil { awaySince = Date() }
    }

    private func markBack() {
        guard let since = awaySince else { return }
        awaySince = nil
        // Only digest meaningful absences.
        if Date().timeIntervalSince(since) > 60 { onReturn?(since) }
    }
}

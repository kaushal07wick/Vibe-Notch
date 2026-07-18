import AppKit
import VibeNotchCore

/// Holds approval cards while the screen is shared, so commands and paths
/// don't pop up mid-demo. Detects macOS screen-sharing sessions plus the
/// share-indicator windows of common meeting apps.
/// ponytail: browser-tab shares (Meet in Chrome) are invisible to both checks.
@MainActor
final class PrivacyGuard {
    private(set) var isSharing = false
    var onChange: ((Bool) -> Void)?
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in self.poll() }
        }
        poll()
    }

    private func poll() {
        guard VNSettings.screenShareGuard else {
            if isSharing { isSharing = false; onChange?(false) }
            return
        }
        let now = Self.detectSharing()
        if now != isSharing {
            isSharing = now
            onChange?(now)
        }
    }

    static func detectSharing() -> Bool {
        // 1. macOS screen sharing / remote sessions
        if let dict = CGSessionCopyCurrentDictionary() as? [String: Any],
           (dict["CGSSessionScreenIsShared"] as? Bool) == true {
            return true
        }
        // 2. Meeting-app share indicators (Zoom/Teams/Webex overlay windows)
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        let markers = ["zoom share", "sharing indicator", "screen sharing bar", "webex share"]
        return windows.contains { info in
            let name = ((info[kCGWindowName as String] as? String) ?? "").lowercased()
            return !name.isEmpty && markers.contains { name.contains($0) }
        }
    }
}

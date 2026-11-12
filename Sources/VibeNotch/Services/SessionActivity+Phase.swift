import Foundation
import VibeNotchCore

extension SessionActivity {
    var phase: SessionPhase { phase(at: Date()) }

    func phase(at now: Date, hasPendingRequest: Bool = false) -> SessionPhase {
        SessionPhase.resolve(event: event, updatedAt: updatedAt, now: now,
                             hasPendingRequest: hasPendingRequest)
    }
}

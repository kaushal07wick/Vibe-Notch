import EventKit
import SwiftUI

/// Today's events for the notch's calendar widget. Asks for calendar access the first time
/// the widget is shown; without it the widget just offers to connect.
@MainActor
final class CalendarModel: ObservableObject {
    static let shared = CalendarModel()
    @Published var events: [EKEvent] = []
    @Published var denied = false
    private let store = EKEventStore()

    func load() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            denied = false; fetch()
        case .notDetermined:
            store.requestFullAccessToEvents { granted, _ in
                Task { @MainActor in self.denied = !granted; if granted { self.fetch() } }
            }
        default:
            denied = true
        }
    }

    private func fetch() {
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { $0.endDate > Date() }
            .sorted { $0.startDate < $1.startDate }
    }
}

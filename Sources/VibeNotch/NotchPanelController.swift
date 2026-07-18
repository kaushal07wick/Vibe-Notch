import Combine
import DynamicNotchKit
import SwiftUI

/// Owns the DynamicNotch and keeps its expand/compact state in sync with the
/// event store. Expands on hover or when there's something to show; compacts
/// otherwise. DynamicNotchKit handles the window, geometry, hover, and morph.
@MainActor
final class NotchPanelController {
    private let store: EventStore
    private let notch: DynamicNotch<ExpandedContent, CompactLeading, CompactTrailing>
    private var cancellables: [AnyCancellable] = []
    private var expanded: Bool?

    init(store: EventStore) {
        self.store = store
        notch = DynamicNotch(
            hoverBehavior: .all,
            style: .auto,
            expanded: { ExpandedContent(store: store) },
            compactLeading: { CompactLeading(store: store) },
            compactTrailing: { CompactTrailing(store: store) }
        )
        cancellables.append(store.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.refresh() }
        })
        cancellables.append(notch.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.refresh() }
        })
    }

    func show() {
        Task { await notch.compact() }
        expanded = false
    }

    func toggle() {
        Task { await notch.expand() }
    }

    private func refresh() {
        let hasEvent = !store.pending.isEmpty || store.flash != nil || store.lastNotification != nil
        let want = hasEvent || notch.isHovering
        guard want != expanded else { return } // avoid re-triggering the morph on every change
        expanded = want
        Task {
            if want { await notch.expand() } else { await notch.compact() }
        }
    }
}

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
        // Springy morph — a little bounce on open/convert, a calm close.
        notch.transitionConfiguration = .init(
            openingAnimation: .spring(response: 0.42, dampingFraction: 0.70),
            closingAnimation: .spring(response: 0.34, dampingFraction: 0.90),
            conversionAnimation: .spring(response: 0.42, dampingFraction: 0.72)
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
        if store.hovering != notch.isHovering { store.hovering = notch.isHovering } // drives brief→full
        let want = !store.pending.isEmpty || store.flash != nil || notch.isHovering
        guard want != expanded else { return } // avoid re-triggering the morph on every change
        expanded = want
        Task {
            if want { await notch.expand() } else { await notch.compact() }
        }
    }
}

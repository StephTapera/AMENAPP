import SwiftUI

// MARK: - PinnedReplyBadge
// Convenience wrapper around GlassBadge for the "Pinned reply" indicator.
// Apply via the .pinnedReplyBadge(isVisible:) view modifier.

@MainActor
struct PinnedReplyBadge: View {
    var isVisible: Bool = true

    var body: some View {
        GlassBadge(
            icon: "pin.fill",
            label: "Pinned",
            tint: Color.amenGold,
            isVisible: isVisible
        )
    }
}

// MARK: - View extension for convenience overlay

extension View {
    /// Overlays a PinnedReplyBadge at the top-trailing edge.
    func pinnedReplyBadge(
        isVisible: Bool = true,
        alignment: Alignment = .topTrailing
    ) -> some View {
        overlay(alignment: alignment) {
            PinnedReplyBadge(isVisible: isVisible)
                .padding(6)
        }
    }
}

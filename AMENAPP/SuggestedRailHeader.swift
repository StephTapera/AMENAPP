// SuggestedRailHeader.swift
// AMENAPP
//
// Shared header for the Suggested Accounts rail across all surfaces.
// Shows surface-specific title + subtitle, and an overflow Menu with:
//   "Hide this rail for now", "Show fewer suggestions", "Why am I seeing this?"

import SwiftUI

struct SuggestedRailHeader: View {
    let surface: SuggestionSurface
    let onHide: () -> Void
    let onShowFewer: () -> Void
    let onWhyShown: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(surface.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(surface.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button {
                    HapticManager.impact(style: .light)
                    onHide()
                } label: {
                    Label("Hide this rail for now", systemImage: "eye.slash")
                }

                Button {
                    HapticManager.impact(style: .light)
                    onShowFewer()
                } label: {
                    Label("Show fewer suggestions", systemImage: "minus.circle")
                }

                Button {
                    HapticManager.impact(style: .light)
                    onWhyShown()
                } label: {
                    Label("Why am I seeing this?", systemImage: "questionmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Suggestions options")
        }
        .padding(.horizontal, 16)
    }
}

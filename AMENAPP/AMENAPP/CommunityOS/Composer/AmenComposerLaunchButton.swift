// AmenComposerLaunchButton.swift
// AMEN App — CommunityOS / Composer
//
// Phase 2 — Agent A3 (Universal Composer)
// A drop-in button any screen can embed to open AmenUniversalComposerView as a sheet.
//
// Usage:
//   AmenComposerLaunchButton(
//       source: ComposerSource(type: .newPost, ...),
//       label: "New Discussion",
//       systemImage: "bubble.left.and.bubble.right"
//   )
//
// Design (C3): uses .tint(.accentColor) — no custom colors.
// Touch target: always >= 44pt (Label layout).

import SwiftUI

// MARK: - AmenComposerLaunchButton

struct AmenComposerLaunchButton: View {

    // MARK: Inputs

    /// The source that seeds the composer session.
    let source: ComposerSource
    /// Text label shown on the button.
    let label: String
    /// SF Symbol name for the leading icon.
    let systemImage: String

    // MARK: State

    @State private var isPresenting: Bool = false

    // MARK: Body

    var body: some View {
        Button {
            isPresenting = true
        } label: {
            Label(label, systemImage: systemImage)
        }
        .tint(Color.accentColor)
        .accessibilityLabel(label)
        .accessibilityHint("Opens the composer to \(label.lowercased())")
        .sheet(isPresented: $isPresenting) {
            AmenUniversalComposerView(
                source: source,
                onDismiss: { isPresenting = false }
            )
        }
    }
}

// MARK: - AmenComposerLaunchButton + Style Variant

extension AmenComposerLaunchButton {

    /// A filled pill variant suitable for use in action rows or empty-state CTAs.
    func filledPillStyle() -> some View {
        self
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
    }
}

// MARK: - Preview

#Preview("Launch Button — inline") {
    VStack(spacing: 20) {
        AmenComposerLaunchButton(
            source: ComposerSource(
                type: .newPost,
                existingRef: nil,
                existingOwnerId: nil,
                prefillText: nil,
                prefillTitle: nil
            ),
            label: "New Post",
            systemImage: "plus.bubble"
        )

        AmenComposerLaunchButton(
            source: ComposerSource(
                type: .prayerRequest,
                existingRef: nil,
                existingOwnerId: nil,
                prefillText: nil,
                prefillTitle: nil
            ),
            label: "Pray",
            systemImage: "hands.and.sparkles"
        )

        AmenComposerLaunchButton(
            source: ComposerSource(
                type: .churchNote,
                existingRef: "users/uid1/churchNotes/note_abc",
                existingOwnerId: "uid1",
                prefillText: "Key insight from today's sermon.",
                prefillTitle: nil
            ),
            label: "Discuss This Note",
            systemImage: "bubble.left.and.bubble.right"
        )
        .filledPillStyle()
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

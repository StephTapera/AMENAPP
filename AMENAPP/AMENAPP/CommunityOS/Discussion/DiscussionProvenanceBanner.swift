// DiscussionProvenanceBanner.swift
// AMEN App — Community OS / Discussion OS (A6)
//
// A compact, dismissible banner shown at the top of a discussion room when it was
// spawned from another object. Lets the reader understand the origin of the conversation.
//
// Design contract (C3):
//   - System colors only — no amenGold, no hex
//   - 32pt height chip on systemGroupedBackground page background
//   - Tappable to navigate to the source object
//   - .caption font, chain-link icon + "From [sourceType]" label
//   - Subtle separator below to delineate from thread content

import SwiftUI

// MARK: - DiscussionProvenanceBanner

/// A compact chip / banner showing the source object a discussion room was spawned from.
/// Shown at the top of DiscussionRoomView when `room.provenance != nil`.
/// Also injected into the legacy DiscussionThreadView when `viewModel.provenance != nil`.
struct DiscussionProvenanceBanner: View {

    let provenance: SpawnProvenance
    /// Callback fired when the user taps the chip to navigate to the source object.
    var onTap: (() -> Void)?

    @State private var isDismissed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !isDismissed {
            VStack(spacing: 0) {
                chip
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .top))
                    )
                Divider()
                    .padding(.top, 6)
            }
            .animation(reduceMotion ? .none : .easeOut(duration: 0.2), value: isDismissed)
        }
    }

    // MARK: - Chip

    private var chip: some View {
        HStack(spacing: 6) {
            // Source type icon
            Image(systemName: provenance.sourceTypeSystemImage)
                .font(.systemScaled(11, weight: .regular))
                .foregroundStyle(Color(uiColor: .secondaryLabel))

            // "From [SourceType]" label
            Text("From \(provenance.sourceTypeDisplayName)")
                .font(.caption)
                .foregroundStyle(Color(uiColor: .secondaryLabel))

            Spacer()

            // Dismiss button
            Button {
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.18)) {
                    isDismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(9, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss provenance banner")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(
            Capsule()
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .contentShape(Capsule())
        .onTapGesture {
            onTap?()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Discussion spawned from \(provenance.sourceTypeDisplayName). Tap to view source.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("With provenance") {
    VStack(spacing: 16) {
        DiscussionProvenanceBanner(
            provenance: SpawnProvenance(
                sourceType: "post",
                sourceRef: "/posts/abc123",
                sourceOwnerId: "uid_XYZ",
                intent: "discuss",
                createdAt: Date()
            ),
            onTap: { }
        )
        .padding(.horizontal, 16)

        DiscussionProvenanceBanner(
            provenance: SpawnProvenance(
                sourceType: "berean_insight",
                sourceRef: "/users/uid/bereanInsights/ins1",
                sourceOwnerId: nil,
                intent: "discuss",
                createdAt: Date()
            ),
            onTap: nil
        )
        .padding(.horizontal, 16)

        DiscussionProvenanceBanner(
            provenance: SpawnProvenance(
                sourceType: "scripture_reference",
                sourceRef: nil,
                sourceOwnerId: nil,
                intent: "discuss",
                createdAt: Date()
            ),
            onTap: nil
        )
        .padding(.horizontal, 16)
    }
    .padding(.vertical, 24)
    .background(Color(uiColor: .systemGroupedBackground))
}
#endif

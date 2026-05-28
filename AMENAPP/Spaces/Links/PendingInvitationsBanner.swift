// PendingInvitationsBanner.swift
// AMENAPP — Spaces v2 Cross-Community Links (Agent F)
//
// Non-intrusive pill banner shown to community admins when they have pending
// link invitations waiting for their response. Tapping opens PendingInvitationsSheet.
//
// Design: AmenLiquidGlassCapsuleSurface pill, LinkedGlyph(.small), tokens only.
// Hidden when there are no pending invitations.
// No "church" anywhere.

import SwiftUI

// MARK: - PendingInvitationsBanner

/// Non-intrusive pill banner shown to community admins when pending link invitations exist.
/// Renders: LinkedGlyph(.small) + "N pending community link invitation(s)".
/// Hidden when `invitations.isEmpty`.
/// Tapping calls `onTap` (typically opens PendingInvitationsSheet).
struct PendingInvitationsBanner: View {

    // MARK: - Parameters

    let invitations: [PendingLinkInvitation]
    /// Called when the banner is tapped — typically opens PendingInvitationsSheet.
    var onTap: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @GestureState private var isPressed: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        if !invitations.isEmpty {
            bannerContent
        }
    }

    // MARK: - Banner

    private var bannerContent: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                LinkedGlyph(size: .small)

                Text(labelText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if reduceTransparency {
                    Capsule(style: .continuous)
                        .fill(AmenTheme.Colors.surfaceChip)
                } else {
                    Capsule(style: .continuous)
                        .fill(LiquidGlassTokens.blurThin)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(AmenTheme.Colors.amenPurple.opacity(0.08))
                        }
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(AmenTheme.Colors.amenPurple.opacity(0.28), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .animation(reduceMotion ? .easeOut(duration: 0.12) : Motion.liquidSpring, value: isPressed)
        .accessibilityLabel(labelText)
        .accessibilityHint("Double-tap to review pending invitations.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Label

    private var labelText: String {
        let count = invitations.count
        return "\(count) pending community link \(count == 1 ? "invitation" : "invitations")"
    }
}

#if DEBUG
#Preview("PendingInvitationsBanner") {
    let sample = [
        PendingLinkInvitation(
            id: "link_1",
            spaceId: "space_1",
            spaceTitle: "Romans Study",
            fromCommunityId: "community_a",
            fromCommunityName: "Hillside Community",
            fromCommunityAvatarURL: nil,
            createdAt: Date()
        ),
        PendingLinkInvitation(
            id: "link_2",
            spaceId: "space_2",
            spaceTitle: "Prayer Wall",
            fromCommunityId: "community_b",
            fromCommunityName: "Grace Fellowship",
            fromCommunityAvatarURL: nil,
            createdAt: Date()
        )
    ]

    VStack(spacing: 20) {
        PendingInvitationsBanner(invitations: sample) {
            print("tapped")
        }
        PendingInvitationsBanner(invitations: [sample[0]]) {
            print("tapped")
        }
        // Hidden when empty:
        PendingInvitationsBanner(invitations: []) {
            print("tapped")
        }
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
#endif

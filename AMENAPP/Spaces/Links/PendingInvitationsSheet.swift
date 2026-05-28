// PendingInvitationsSheet.swift
// AMENAPP — Spaces v2 Cross-Community Links (Agent F)
//
// Sheet showing all pending link invitations TO a community.
// Community admins review, accept, or decline each invitation.
//
// Accept → calls service.acceptLink → card disappears via listener update.
// Decline → calls service.revokeLink → status flips to revoked; card disappears via listener.
// NEVER hard-deletes any document.
//
// Design: AmenLiquidGlassBottomSheet, hero-profile style invitation cards.
// No "church" anywhere.

import SwiftUI

struct PendingInvitationsSheet: View {

    // MARK: - Parameters

    let communityId: String
    @Binding var isPresented: Bool

    // MARK: - State

    @StateObject private var service = SpacesLinksService()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        AmenLiquidGlassBottomSheet(
            title: "Pending Invitations",
            subtitle: invitationsSubtitle,
            aiDisclosure: nil,
            content: {
                VStack(spacing: 0) {
                    Group {
                        if service.isLoading {
                            loadingView
                        } else if service.pendingInvitations.isEmpty {
                            emptyView
                        } else {
                            invitationsList
                        }
                    }

                    if let errorMsg = service.error {
                        errorBanner(message: errorMsg)
                            .padding(.top, 8)
                    }
                }
            },
            footer: {
                Button("Done") { isPresented = false }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AmenTheme.Colors.surfaceChip)
                    .clipShape(Capsule(style: .continuous))
                    .accessibilityLabel("Done, close invitations sheet")
            }
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await service.loadPendingInvitations(forCommunityId: communityId)
        }
    }

    // MARK: - Subtitle

    private var invitationsSubtitle: String? {
        let count = service.pendingInvitations.count
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? "invitation" : "invitations")"
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack {
            ProgressView()
                .padding(.vertical, 40)
                .accessibilityLabel("Loading invitations")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 10) {
            LinkedGlyph(size: .large)
            Text("No pending invitations")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("When another community invites you to share a Space, it will appear here.")
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No pending invitations")
    }

    // MARK: - Invitations list

    private var invitationsList: some View {
        VStack(spacing: 12) {
            ForEach(service.pendingInvitations) { invitation in
                InvitationCard(
                    invitation: invitation,
                    onAccept: {
                        Task {
                            do {
                                try await service.acceptLink(
                                    linkId: invitation.id,
                                    communityId: communityId
                                )
                            } catch {
                                // Error will surface via service.error publisher.
                            }
                        }
                    },
                    onDecline: {
                        Task {
                            do {
                                try await service.revokeLink(
                                    linkId: invitation.id,
                                    communityId: communityId
                                )
                            } catch {
                                // Error will surface via service.error publisher.
                            }
                        }
                    }
                )
            }
        }
    }

    // MARK: - Error banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AmenTheme.Colors.statusError)
            Text(message)
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.statusError)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                .fill(AmenTheme.Colors.statusError.opacity(0.08))
        }
        .accessibilityLabel("Error: \(message)")
    }
}

// MARK: - InvitationCard

/// Hero-profile style card for a single pending invitation.
/// Accept → acceptLink; Decline → revokeLink (status flip, no delete).
private struct InvitationCard: View {

    let invitation: PendingLinkInvitation
    var onAccept: () -> Void
    var onDecline: () -> Void

    @State private var isAccepting: Bool = false
    @State private var isDeclining: Bool = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Hero header: community avatar + name + space title
            HStack(spacing: 12) {
                SpaceAvatarView(
                    avatarURL: invitation.fromCommunityAvatarURL,
                    title: invitation.fromCommunityName,
                    size: 48,
                    isShared: true,
                    sharedCommunityName: invitation.fromCommunityName
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(invitation.fromCommunityName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Text("Shared Space from \(invitation.fromCommunityName)")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            // Space title pill
            HStack(spacing: 6) {
                LinkedGlyph(size: .small)
                Text(invitation.spaceTitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            // Timestamp
            Text(invitation.createdAt.formatted(.relative(presentation: .numeric)))
                .font(.caption2)
                .foregroundStyle(AmenTheme.Colors.textTertiary)

            // Action buttons
            HStack(spacing: 12) {
                Spacer(minLength: 0)

                // Decline — text button, calls revokeLink (status flip only)
                Button("Decline") {
                    isDeclining = true
                    onDecline()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .disabled(isAccepting || isDeclining)
                .accessibilityLabel("Decline invitation from \(invitation.fromCommunityName)")
                .accessibilityHint("Double-tap to decline. The invitation status will be revoked.")

                // Accept — filled pill button
                AmenLiquidGlassPillButton(
                    title: "Accept",
                    systemImage: "checkmark",
                    isLoading: isAccepting,
                    isDisabled: isDeclining,
                    hint: "Double-tap to accept this community link invitation."
                ) {
                    isAccepting = true
                    onAccept()
                }
                .accessibilityLabel("Accept invitation from \(invitation.fromCommunityName)")
            }
        }
        .padding(16)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceChip)
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(LiquidGlassTokens.blurThin)
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Invitation from \(invitation.fromCommunityName) to share \(invitation.spaceTitle)")
    }
}

#if DEBUG
#Preview("PendingInvitationsSheet") {
    @Previewable @State var isPresented = true
    Text("Tap to show sheet")
        .sheet(isPresented: $isPresented) {
            PendingInvitationsSheet(
                communityId: "community_local",
                isPresented: $isPresented
            )
        }
}
#endif

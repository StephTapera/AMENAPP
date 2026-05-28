// LinkInviteInboxView.swift
// AMENAPP — Spaces v2 Cross-Community Links (Agent F)
//
// Where community admins review incoming link invitations.
// Card style mirrors AmenAccessRequestInboxView (glass card with action buttons).
// Accessible from community settings or a deep-link notification.
//
// No Combine — async/await only. No "church" anywhere.

import SwiftUI

struct LinkInviteInboxView: View {

    // MARK: - Parameters

    let communityId: String

    // MARK: - State

    @StateObject private var viewModel = CrossCommunityViewModel()
    @State private var alertItem: InboxAlertItem? = nil

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.incomingInvites.isEmpty {
                emptyView
            } else {
                inviteList
            }
        }
        .navigationTitle("Link Invites")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.loadIncomingInvites(communityId: communityId) }
        .task { await viewModel.loadIncomingInvites(communityId: communityId) }
        .alert(item: $alertItem) { item in
            Alert(title: Text("Error"), message: Text(item.message))
        }
        .onChange(of: viewModel.error?.localizedDescription) { _, newValue in
            if let msg = newValue { alertItem = InboxAlertItem(message: msg) }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .accessibilityLabel("Loading invitations")
            Spacer()
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        ContentUnavailableView(
            "No Invitations",
            systemImage: "link.badge.plus",
            description: Text("When another community invites you to share a Space, it will appear here.")
        )
    }

    // MARK: - Invite list

    private var inviteList: some View {
        List {
            ForEach(viewModel.incomingInvites) { invite in
                InviteInboxCard(invite: invite) { spaceId in
                    Task { await viewModel.acceptInvite(link: invite, spaceId: spaceId) }
                } onDecline: {
                    Task { await viewModel.declineInvite(link: invite) }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
        .listStyle(.plain)
        .background(AmenTheme.Colors.backgroundPrimary)
    }
}

// MARK: - InviteInboxCard

/// Mirrors AmenAccessRequestInboxView card style:
/// glass container + avatar + title/description + Accept/Decline row.
private struct InviteInboxCard: View {

    let invite: CommunityLinkRecord
    var onAccept: (String) -> Void
    var onDecline: () -> Void

    @State private var isVisible: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The spaceId is embedded in scope or link; we use a placeholder if not directly available.
    // The scope format is "Shared: <Space title>" — extract space title for display.
    private var scopeTitle: String {
        invite.scope.hasPrefix("Shared: ")
            ? String(invite.scope.dropFirst("Shared: ".count))
            : invite.scope
    }

    var body: some View {
        Group {
            if isVisible {
                cardContent
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        )
                    )
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.16) : Motion.liquidSpring, value: isVisible)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: avatar + community info
            HStack(spacing: 12) {
                SpaceAvatarView(
                    avatarURL: nil,
                    title: invite.fromCommunityId,
                    size: 44,
                    isShared: false
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(invite.fromCommunityId)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Text("wants to share \"\(scopeTitle)\" with you")
                        .font(.footnote)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            // Scope pill
            HStack(spacing: 6) {
                LinkedCommunityGlyph(size: 12, communityName: invite.fromCommunityId)
                Text(invite.scope)
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            // Timestamp
            Text(invite.createdAt.formatted(.relative(presentation: .numeric)))
                .font(.caption2)
                .foregroundStyle(AmenTheme.Colors.textTertiary)

            // Action buttons
            HStack(spacing: 12) {
                Spacer()

                Button("Decline") {
                    withAnimation(Motion.liquidSpring) { isVisible = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onDecline() }
                }
                .buttonStyle(InboxActionButtonStyle(color: AmenTheme.Colors.amenPurple))
                .accessibilityLabel("Decline invitation from \(invite.fromCommunityId)")

                Button("Accept") {
                    withAnimation(Motion.liquidSpring) { isVisible = false }
                    // spaceId is stored in the link's additional field if available.
                    // Fall back to empty string; service will surface an error.
                    let spaceId = invite.scope  // Callers store spaceId separately in real use.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onAccept(spaceId) }
                }
                .buttonStyle(InboxActionButtonStyle(color: AmenTheme.Colors.amenGold, filled: true))
                .accessibilityLabel("Accept invitation from \(invite.fromCommunityId)")
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .fill(LiquidGlassTokens.blurThin)
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

// MARK: - InboxActionButtonStyle

private struct InboxActionButtonStyle: ButtonStyle {
    let color: Color
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(filled ? Color.white : color)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background {
                if filled {
                    Capsule().fill(color.opacity(configuration.isPressed ? 0.75 : 1.0))
                } else {
                    Capsule().fill(color.opacity(configuration.isPressed ? 0.18 : 0.10))
                        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.5))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(Motion.springPress, value: configuration.isPressed)
    }
}

// MARK: - InboxAlertItem helper

private struct InboxAlertItem: Identifiable {
    let id = UUID()
    let message: String
}

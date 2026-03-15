//
//  ChatIdentityCard.swift
//  AMENAPP
//
//  First-time chat identity card, enhanced request banner,
//  outgoing pending state, and context source banner.
//  Designed for AMEN Liquid Glass design language.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Follow Relationship

enum ChatFollowRelationship: Equatable {
    case mutual               // "You follow each other"
    case theyFollowYou        // "Follows you"
    case youFollowThem        // "You follow them"
    case noFollowRelationship // "You don't follow each other"
    case loading

    var label: String {
        switch self {
        case .mutual:               return "You follow each other"
        case .theyFollowYou:        return "Follows you"
        case .youFollowThem:        return "You follow them"
        case .noFollowRelationship: return "You don't follow each other"
        case .loading:              return ""
        }
    }

    var icon: String {
        switch self {
        case .mutual:               return "person.2.fill"
        case .theyFollowYou:        return "person.crop.circle.badge.checkmark"
        case .youFollowThem:        return "person.crop.circle.badge.plus"
        case .noFollowRelationship: return "person.crop.circle"
        case .loading:              return "person.crop.circle"
        }
    }
}

// MARK: - Chat Identity Card
// Shown at the top of the message list for first-time / request conversations.
// Collapses once there are meaningful messages.

struct ChatIdentityCard: View {
    let conversation: ChatConversation
    let followRelationship: ChatFollowRelationship
    let isFollowLoading: Bool
    let onViewProfile: () -> Void
    let onFollow: () -> Void   // nil-safe: only active when follow action is available
    var overridePhotoURL: String? = nil  // Live-fetched photo, takes precedence over stale conversation doc

    // Computed follow button label
    private var followButtonLabel: String {
        switch followRelationship {
        case .mutual:               return "Following"
        case .youFollowThem:        return "Following"
        case .theyFollowYou:        return "Follow Back"
        case .noFollowRelationship: return "Follow"
        case .loading:              return "Follow"
        }
    }

    private var showFollowButton: Bool {
        followRelationship == .theyFollowYou || followRelationship == .noFollowRelationship
    }

    var body: some View {
        VStack(spacing: 20) {
            // Avatar
            avatarView
                .frame(width: 76, height: 76)

            // Name + username + bio
            identityText

            // Follow relationship badge
            if followRelationship != .loading {
                relationshipBadge
            }

            // Action row
            actionRow
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: Avatar

    @ViewBuilder
    private var avatarView: some View {
        ZStack {
            let effectivePhotoURL = (overridePhotoURL?.isEmpty == false ? overridePhotoURL : nil)
                                 ?? conversation.profilePhotoURL
            if let photoURL = effectivePhotoURL,
               !photoURL.isEmpty,
               let url = URL(string: photoURL) {
                CachedAsyncImage(
                    url: url,
                    content: { image in
                        image.resizable().scaledToFill()
                            .frame(width: 76, height: 76)
                            .clipShape(Circle())
                    },
                    placeholder: {
                        fallbackAvatar
                    }
                )
            } else {
                fallbackAvatar
            }
        }
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            conversation.avatarColor.opacity(0.75),
                            conversation.avatarColor.opacity(0.50)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 76, height: 76)
            Text(conversation.initials)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: Identity Text

    private var identityText: some View {
        VStack(spacing: 5) {
            // Display name
            Text(conversation.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            // Username
            if let username = conversation.otherUserUsername, !username.isEmpty {
                Text("@\(username)")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            // Bio preview (one line)
            if let bio = conversation.otherUserBio, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: Relationship Badge

    private var relationshipBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: followRelationship.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(followRelationship.label)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8))
        )
    }

    // MARK: Action Row

    private var actionRow: some View {
        HStack(spacing: 12) {
            // View Profile — always available
            Button(action: onViewProfile) {
                VStack(spacing: 5) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.75))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
                        )
                    Text("View Profile")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Follow / Follow Back — only shown when relevant
            if showFollowButton {
                Button(action: onFollow) {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: 44, height: 44)
                            if isFollowLoading {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.75)
                            } else {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        }
                        Text(followButtonLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isFollowLoading)
            }
        }
    }
}

// MARK: - Chat Source Banner
// Shown below identity card or at top of messages, only when source != .direct

struct ChatSourceBanner: View {
    let source: ConversationSource

    var body: some View {
        if source != .direct && !source.label.isEmpty {
            HStack(spacing: 7) {
                Image(systemName: source.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(source.label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7))
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Chat Request Banner (Enhanced)
// Replaces the existing basic messageRequestBanner.
// Shown when status == "pending" AND the current user is NOT the requester (incoming).

struct ChatRequestBanner: View {
    let conversation: ChatConversation
    let followRelationship: ChatFollowRelationship
    let isFollowLoading: Bool
    let isAccepting: Bool
    let isDeclining: Bool
    let onViewProfile: () -> Void
    let onFollow: () -> Void
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onRestrict: () -> Void
    let onBlock: () -> Void
    let onReport: () -> Void

    @State private var showMoreMenu = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                // Identity row
                identityRow

                // Follow relationship
                if followRelationship != .loading {
                    HStack(spacing: 5) {
                        Image(systemName: followRelationship.icon)
                            .font(.system(size: 11, weight: .medium))
                        Text(followRelationship.label)
                            .font(.system(size: 12, weight: .regular))
                    }
                    .foregroundStyle(.secondary)
                }

                // Source context
                if conversation.source != .direct, !conversation.source.label.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: conversation.source.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(conversation.source.label)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.ultraThinMaterial))
                }

                // Primary action row
                primaryActions

                // Secondary safety note
                safetyNote
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 0.5),
            alignment: .bottom
        )
        .confirmationDialog("More Options", isPresented: $showMoreMenu, titleVisibility: .visible) {
            Button("Restrict", action: onRestrict)
            Button("Block \(conversation.name)", role: .destructive, action: onBlock)
            Button("Report", role: .destructive, action: onReport)
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Identity Row

    private var identityRow: some View {
        HStack(spacing: 14) {
            // Avatar
            Group {
                if let photoURL = conversation.profilePhotoURL,
                   !photoURL.isEmpty,
                   let url = URL(string: photoURL) {
                    CachedAsyncImage(
                        url: url,
                        content: { image in
                            image.resizable().scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                        },
                        placeholder: {
                            requestAvatarFallback
                        }
                    )
                } else {
                    requestAvatarFallback
                }
            }

            // Name + username
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                if let username = conversation.otherUserUsername, !username.isEmpty {
                    Text("@\(username)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // View profile + overflow
            HStack(spacing: 8) {
                Button(action: onViewProfile) {
                    Text("Profile")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showMoreMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var requestAvatarFallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [conversation.avatarColor.opacity(0.75), conversation.avatarColor.opacity(0.50)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)
            Text(conversation.initials)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: Primary Actions

    private var primaryActions: some View {
        HStack(spacing: 10) {
            // Decline
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onDecline()
            } label: {
                HStack(spacing: 6) {
                    if isDeclining {
                        ProgressView()
                            .tint(Color(red: 0.7, green: 0.1, blue: 0.1))
                            .scaleEffect(0.8)
                    } else {
                        Text("Delete")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundStyle(Color(red: 0.75, green: 0.15, blue: 0.15))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.95, green: 0.88, blue: 0.88))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(red: 0.75, green: 0.15, blue: 0.15).opacity(0.15), lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(isAccepting || isDeclining)

            // Accept
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onAccept()
            } label: {
                HStack(spacing: 6) {
                    if isAccepting {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Text("Accept")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary)
                )
            }
            .buttonStyle(.plain)
            .disabled(isAccepting || isDeclining)
        }
    }

    // MARK: Safety Note

    private var safetyNote: some View {
        HStack(spacing: 5) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 10))
            Text("Review before accepting. You can always block or report.")
                .font(.system(size: 11, weight: .regular))
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

// MARK: - Outgoing Pending Banner
// Shown when the current user sent the request and it hasn't been accepted yet.

struct ChatOutgoingPendingBanner: View {
    let conversation: ChatConversation

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Message request sent")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text("\(conversation.name) will see your message once they accept.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
                )
        )
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

// MARK: - Empty Chat Scaffold
// Shown for a completely empty conversation (no messages yet).

struct ChatEmptyState: View {
    let conversation: ChatConversation
    let followRelationship: ChatFollowRelationship

    private var emptyPrompt: String {
        switch followRelationship {
        case .mutual:
            return "Start the conversation."
        case .theyFollowYou:
            return "They follow you. Say hello."
        case .youFollowThem:
            return "You follow \(conversation.name.components(separatedBy: " ").first ?? "them"). Break the ice."
        case .noFollowRelationship, .loading:
            return "Send a message request to \(conversation.name.components(separatedBy: " ").first ?? "them")."
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(emptyPrompt)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - System Message Row
// Used for event notifications inside the message thread (request accepted, follow, etc.)

struct ChatSystemMessageRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

// DiscussionRoomView.swift
// AMEN App — Community OS / Discussion OS (A6)
//
// Full discussion room view for structured rooms that can be anchored on any canonical object.
// This is distinct from the legacy DiscussionThreadView which handles post-level comment threads.
// DiscussionRoomView renders rooms of type DiscussionRoom (CommunityOS/Discussion/DiscussionModels.swift).
//
// Feature flag gate: AMENFeatureFlags.shared.communityOSDiscussionEnabled
// Design contract (C3): system colors, 28pt continuous cards, AmenShadow.card spec.

import SwiftUI

// MARK: - DiscussionCommentRow (stub)

/// Placeholder row for a discussion comment.
/// Replace with the full CommentRow from DiscussionThreadView once the models are unified.
private struct DiscussionCommentRow: View {
    let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Participant \(index)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .label))

                Text("This is a placeholder comment row for the discussion room. Real comments will be loaded from Firestore.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Comment from Participant \(index)")
    }
}

// MARK: - DiscussionRoomView

/// Full discussion room view with provenance banner, room type chip, thread list, and composer.
/// Gated by `AMENFeatureFlags.shared.communityOSDiscussionEnabled`.
struct DiscussionRoomView: View {

    let room: DiscussionRoom

    @State private var commentText = ""
    @State private var isLocked: Bool
    @State private var showFollowUpPrompt = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(room: DiscussionRoom) {
        self.room = room
        _isLocked = State(initialValue: room.isLocked)
    }

    var body: some View {
        guard AMENFeatureFlags.shared.communityOSDiscussionEnabled else {
            return AnyView(featureUnavailableView)
        }
        return AnyView(mainContent)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            provenanceSection
                            roomTypeChip
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                            if showFollowUpPrompt {
                                DiscussionFollowUpPrompt(
                                    prompt: "The conversation on \"\(room.title)\" has new activity.",
                                    onAccept: { showFollowUpPrompt = false },
                                    onDismiss: { showFollowUpPrompt = false }
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : .opacity.combined(with: .move(edge: .top))
                                )
                            }

                            summaryCard

                            if isLocked {
                                lockedBanner
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 6)
                            }

                            threadContent

                            Color.clear.frame(height: 88).id("bottom")
                        }
                    }
                }

                if !isLocked {
                    composerBar
                }
            }
            .navigationTitle(room.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Close discussion room")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    askBereanButton
                }
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: showFollowUpPrompt)
    }

    // MARK: - Provenance Section

    @ViewBuilder
    private var provenanceSection: some View {
        if let prov = room.provenance {
            DiscussionProvenanceBanner(
                provenance: prov,
                onTap: nil // Caller can inject navigation via onTap once source routing is wired
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Room Type Chip

    private var roomTypeChip: some View {
        HStack(spacing: 5) {
            Image(systemName: room.discussionType.systemImage)
                .font(.system(size: 11, weight: .regular))
            Text(room.discussionType.displayName)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.10), in: Capsule())
        .accessibilityLabel("Room type: \(room.discussionType.displayName)")
    }

    // MARK: - Summary Card

    @ViewBuilder
    private var summaryCard: some View {
        if let summary = room.summaryText, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Overview", systemImage: "text.quote")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))

                Text(summary)
                    .font(.callout)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.07), radius: 24, x: 0, y: 5)
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Locked Banner

    private var lockedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Text("This discussion is locked. No new messages can be posted.")
                .font(.footnote)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
        )
    }

    // MARK: - Thread Content

    @ViewBuilder
    private var threadContent: some View {
        if room.threadCount == 0 {
            emptyState
        } else {
            // Placeholder rows — replace with real Firestore-backed list when wired
            ForEach(0..<min(room.threadCount, 5), id: \.self) { index in
                DiscussionCommentRow(index: index + 1)
                Divider()
                    .padding(.leading, 58)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
            Text("Be the first to start the conversation.")
                .font(.callout)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No messages yet. Be the first to start the conversation.")
    }

    // MARK: - Ask Berean Button

    private var askBereanButton: some View {
        Button {
            // Berean integration hook — connects to BereanOSHubView / Berean callable
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11))
                Text("Ask Berean")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.accentColor)
        }
        .accessibilityLabel("Ask Berean AI about this discussion")
    }

    // MARK: - Composer Bar

    private var composerBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField(composerPlaceholder, text: $commentText, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(uiColor: .label))
                    .tint(Color.accentColor)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemFill))
                    )
                    .accessibilityLabel("Add to this discussion")

                sendButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .padding(.bottom, 4)
        }
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.5))
                        .frame(height: 0.5),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var composerPlaceholder: String {
        switch room.discussionType {
        case .prayer:    return "Share a prayer…"
        case .bibleStudy: return "Share your insight…"
        case .mentorship: return "Ask or share…"
        default:         return "Share your perspective…"
        }
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            guard !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            // Wire to Firestore write via DiscussionRoomService (to be built in Phase 1)
            commentText = ""
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(
                    commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color(uiColor: .tertiaryLabel)
                        : Color.accentColor
                )
        }
        .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .frame(width: 36, height: 36)
        .accessibilityLabel("Send message")
    }

    // MARK: - Feature Unavailable State

    private var featureUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
            Text("Discussion rooms are coming soon.")
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Discussion rooms feature is not yet available.")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("With provenance") {
    DiscussionRoomView(
        room: DiscussionRoom(
            id: "room_001",
            title: "What does faith mean in action?",
            discussionType: .bibleStudy,
            hostId: "uid_host",
            participantIds: ["uid_host", "uid_a", "uid_b"],
            audience: "space_members",
            threadCount: 3,
            summaryText: "This discussion explores practical expressions of faith in everyday decisions, anchored in James 2:14–26.",
            provenance: SpawnProvenance(
                sourceType: "post",
                sourceRef: "/posts/abc123",
                sourceOwnerId: "uid_host",
                intent: "discuss",
                createdAt: Date()
            ),
            isLocked: false,
            createdAt: Date()
        )
    )
}

#Preview("Locked, no provenance") {
    DiscussionRoomView(
        room: DiscussionRoom(
            id: "room_002",
            title: "Sunday Recap — February 2026",
            discussionType: .church,
            hostId: "uid_pastor",
            participantIds: ["uid_pastor"],
            audience: "church_only",
            threadCount: 0,
            summaryText: nil,
            provenance: nil,
            isLocked: true,
            createdAt: Date()
        )
    )
}
#endif

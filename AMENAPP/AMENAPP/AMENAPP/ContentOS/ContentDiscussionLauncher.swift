// ContentDiscussionLauncher.swift
// AMENAPP — ContentOS
//
// Thin orchestrator. Any view in Amen calls:
//
//   .contentDiscussionSheet(launcher: launcher)
//
// then triggers:
//
//   launcher.present(card: myCard, requestorIsCreator: ...)
//
// The launcher decides whether to show the approval sheet, a discussion room,
// the post composer, or the Church Notes save confirmation.

import SwiftUI

// MARK: - Launcher

@MainActor
final class ContentDiscussionLauncher: ObservableObject {

    @Published var isPresented = false
    @Published private(set) var pendingCard: ContentCard?
    @Published private(set) var requestorIsCreator       = false
    @Published private(set) var requestorIsSpaceAdmin    = false
    @Published private(set) var requestorIsChurchAdmin   = false
    @Published private(set) var requestorIsTrustedMember = false

    // Sheet routing state
    @Published var showDiscussionRoom   = false
    @Published var showApprovalSheet    = false
    @Published var discussionRoomConfig: DiscussionRoomConfig?

    struct DiscussionRoomConfig: Identifiable {
        let id = UUID()
        let objectId: String
        let objectTitle: String
        let roomType: ObjectDiscussionRoom.ObjectDiscussionRoomType
    }

    // MARK: - Present

    func present(
        card: ContentCard,
        requestorIsCreator: Bool       = false,
        requestorIsSpaceAdmin: Bool    = false,
        requestorIsChurchAdmin: Bool   = false,
        requestorIsTrustedMember: Bool = false
    ) {
        guard AMENFeatureFlags.shared.contentOSEnabled else { return }

        pendingCard               = card
        self.requestorIsCreator       = requestorIsCreator
        self.requestorIsSpaceAdmin    = requestorIsSpaceAdmin
        self.requestorIsChurchAdmin   = requestorIsChurchAdmin
        self.requestorIsTrustedMember = requestorIsTrustedMember
        isPresented = true
    }

    // MARK: - Handle Action from Sheet

    func handleAction(_ action: ContentAction) {
        guard let card = pendingCard else { return }

        switch action {
        case .discussInSpace, .discussInConnect:
            discussionRoomConfig = DiscussionRoomConfig(
                objectId:    card.sourceId,
                objectTitle: card.title.isEmpty ? card.sourceType.displayName : card.title,
                roomType:    .discussion
            )
            showDiscussionRoom = true

        case .createPrayerRoom:
            discussionRoomConfig = DiscussionRoomConfig(
                objectId:    card.sourceId,
                objectTitle: card.title.isEmpty ? "Prayer" : card.title,
                roomType:    .prayer
            )
            showDiscussionRoom = true

        case .createStudy, .createEventFollowUp:
            discussionRoomConfig = DiscussionRoomConfig(
                objectId:    card.sourceId,
                objectTitle: card.title.isEmpty ? card.sourceType.displayName : card.title,
                roomType:    .studyGroup
            )
            showDiscussionRoom = true

        case .saveToChurchNotes:
            Task {
                try? await ContentForwardingService.shared.saveToChurchNotes(card: card)
            }

        default:
            break
        }

        isPresented = false
    }
}

// MARK: - View Modifier

struct ContentDiscussionSheetModifier: ViewModifier {
    @ObservedObject var launcher: ContentDiscussionLauncher

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $launcher.isPresented) {
                if let card = launcher.pendingCard {
                    ContentApprovalSheet(
                        card: card,
                        requestorIsCreator:       launcher.requestorIsCreator,
                        requestorIsSpaceAdmin:    launcher.requestorIsSpaceAdmin,
                        requestorIsChurchAdmin:   launcher.requestorIsChurchAdmin,
                        requestorIsTrustedMember: launcher.requestorIsTrustedMember,
                        onAction: { launcher.handleAction($0) },
                        onDismiss: { launcher.isPresented = false }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
                }
            }
            .sheet(item: $launcher.discussionRoomConfig) { config in
                AmenObjectDiscussionRoomView(
                    objectId:    config.objectId,
                    objectTitle: config.objectTitle,
                    roomType:    config.roomType,
                    existingRoom: nil
                )
            }
    }
}

extension View {
    func contentDiscussionSheet(launcher: ContentDiscussionLauncher) -> some View {
        modifier(ContentDiscussionSheetModifier(launcher: launcher))
    }
}

// MARK: - Convenience: Content Card Builder

extension ContentCard {

    /// Builds a ContentCard from a Covenant post's raw fields.
    /// Caller provides sensitivity score; defaults to safe (0.0) if unknown.
    static func from(
        id: String,
        title: String,
        body: String,
        sourceType: ContentSourceType,
        sourceSurface: ContentSurface,
        creatorId: String,
        creatorDisplayName: String?,
        audience: ContentAudience,
        isAnonymous: Bool,
        hasPrayerContent: Bool = false,
        isPaidContent: Bool = false,
        isDM: Bool = false,
        isChurchInternal: Bool = false,
        sensitivityScore: Double = 0.0
    ) -> ContentCard {
        ContentCard(
            id:                 id,
            title:              title,
            body:               body,
            sourceType:         sourceType,
            sourceSurface:      sourceSurface,
            sourceId:           id,
            originalAudience:   audience,
            creatorId:          creatorId,
            creatorDisplayName: isAnonymous ? nil : creatorDisplayName,
            sensitivityScore:   sensitivityScore,
            hasPrayerContent:   hasPrayerContent,
            hasChildContent:    false,
            hasLocationData:    false,
            hasMinors:          false,
            isAnonymous:        isAnonymous,
            isPaidContent:      isPaidContent,
            isDM:               isDM,
            isChurchInternal:   isChurchInternal,
            createdAt:          Date(),
            expiresAt:          nil,
            moderationState:    .safe,
            discussionStatus:   .none,
            attributionRules:   ContentAttributionRules(
                requiresAttribution: audience != .publicFeed,
                allowsAnonymous:     isAnonymous,
                allowsQuoteOnly:     audience.isRestricted,
                expiresAfterDays:    nil
            )
        )
    }
}

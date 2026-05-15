import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@Suite("Smart Share")
@MainActor
struct SmartShareTests {
    private let payloadFactory = SharePayloadFactory()
    private let linkBuilder = ShareDeepLinkBuilder()

    private func makeEntity(
        id: String = "entity_1",
        type: ShareableEntityType = .discoverResult,
        visibility: ShareEntityVisibility = .public,
        title: String = "Daily Encouragement",
        preview: String = "This reminded me to stay grounded in grace.",
        sourceSurface: String = "test"
    ) -> ShareableEntity {
        ShareableEntity(
            id: id,
            entityType: type,
            authorId: "author_1",
            authorName: "Steph",
            authorUsername: "steph",
            authorInitials: "ST",
            authorPhotoURL: "https://example.com/avatar.jpg",
            visibility: visibility,
            title: title,
            previewText: preview,
            mediaPreviewURL: nil,
            route: ShareRouteDescriptor(
                path: "\(type.rawValue)/\(id)",
                webFallbackPath: "\(type.rawValue)/\(id)",
                metadata: ["id": id]
            ),
            externallyShareable: visibility == .public,
            attributionPolicy: .required,
            sourceSurface: sourceSurface,
            linkedPostId: nil,
            linkedChurchNoteId: nil,
            churchId: type == .churchProfile ? "church_1" : nil,
            churchName: type == .churchProfile ? "Grace Church" : nil,
            groupId: type == .group ? "group_1" : nil,
            prayerCircleId: type == .prayerRequest ? "prayer_1" : nil,
            verseReference: type == .verse ? "Romans 8:28" : nil,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
    }

    @Test("Share intent destinations map to daily-use actions")
    func shareIntentDestinationMapping() {
        #expect(ShareIntent.addToNotes.destinationType == .notes)
        #expect(ShareIntent.remindMeLater.destinationType == .reminder)
        #expect(ShareIntent.reflectPrivately.destinationType == .privateReflection)
        #expect(ShareIntent.saveForLater.destinationType == .collection)
        #expect(ShareIntent.createPrayerShare.destinationType == .prayerCircle)
        #expect(ShareIntent.createDiscussion.destinationType == .discussion)
    }

    @Test("Church note entities resolve to church note preview mode")
    func churchNoteContextMode() {
        let entity = makeEntity(type: .churchNote)
        #expect(entity.shareContentType == .churchNote)
        #expect(entity.contextMode == .churchNotePreview)
    }

    @Test("Prayer entities resolve to prayer-sensitive mode")
    func prayerContextMode() {
        let entity = makeEntity(type: .prayerRequest, visibility: .prayerCircleOnly)
        #expect(entity.shareContentType == .prayerRequest)
        #expect(entity.contextMode == .prayerSensitive)
    }

    @Test("Payload includes attribution when smart context is enabled")
    func payloadWithSmartContext() {
        let entity = makeEntity(type: .verse, title: "Romans 8:28", preview: "God works all things together for good.")
        let payload = payloadFactory.makePayload(
            for: entity,
            options: .default(for: .versePost),
            smartContextEnabled: true
        )

        #expect(payload.text.contains("Shared from AMEN by Steph"))
        #expect(payload.deepLink.absoluteString == "amen://verse/entity_1")
        #expect(payload.externalItems.count >= 2)
    }

    @Test("Payload downgrades when smart context is disabled")
    func payloadWithoutSmartContext() {
        let entity = makeEntity(type: .discoverResult)
        let payload = payloadFactory.makePayload(
            for: entity,
            options: .default(for: .resource),
            smartContextEnabled: false
        )

        #expect(payload.text.contains(entity.previewText))
        #expect(!payload.text.contains("Shared from AMEN by Steph"))
    }

    @Test("Canonical and web fallback links use entity routes")
    func deepLinkGeneration() {
        let entity = makeEntity(id: "abc123", type: .profile)
        #expect(linkBuilder.canonicalURL(for: entity).absoluteString == "amen://profile/abc123")
        #expect(linkBuilder.webFallbackURL(for: entity).absoluteString == "https://amenapp.com/profile/abc123")
    }

    @Test("Target fallback initials never return an empty string")
    func targetFallbackInitials() {
        let target = SmartShareTarget(
            id: "user_1",
            targetType: .person,
            displayName: "",
            username: "amen-user",
            photoURL: nil,
            subtitle: "Direct share",
            badgeReason: nil,
            score: 0,
            reasons: [],
            isOnline: false,
            isVerified: false,
            churchAffiliation: nil,
            conversation: nil,
            user: nil
        )

        #expect(target.fallbackInitials == "AM")
        #expect(target.imageURL == nil)
    }

    @Test("Share router produces profile entities with correct surface")
    func shareRouterProfileEntity() {
        let entity = ShareRouter.entityForProfile(
            id: "user_7",
            displayName: "AMEN Creator",
            username: "amen_creator",
            bio: "Creator bio",
            imageURL: "https://example.com/profile.png",
            sourceSurface: "user_profile"
        )

        #expect(entity.entityType == .profile)
        #expect(entity.sourceSurface == "user_profile")
        #expect(entity.authorPhotoURL == "https://example.com/profile.png")
    }
}
#endif

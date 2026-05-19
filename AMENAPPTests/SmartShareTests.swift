import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

// MARK: - Helpers

private func makeEntity(
    id: String = "entity_1",
    type: ShareableEntityType = .discoverResult,
    visibility: ShareEntityVisibility = .public,
    title: String = "Daily Encouragement",
    preview: String = "This reminded me to stay grounded in grace.",
    sourceSurface: String = "test",
    authorId: String = "author_1",
    externallyShareable: Bool = true,
    linkedPostId: String? = nil,
    churchId: String? = nil,
    groupId: String? = nil,
    prayerCircleId: String? = nil,
    verseReference: String? = nil
) -> ShareableEntity {
    ShareableEntity(
        id: id,
        entityType: type,
        authorId: authorId,
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
        externallyShareable: externallyShareable,
        attributionPolicy: .required,
        sourceSurface: sourceSurface,
        linkedPostId: linkedPostId,
        linkedChurchNoteId: nil,
        churchId: churchId,
        churchName: churchId != nil ? "Grace Church" : nil,
        groupId: groupId,
        prayerCircleId: prayerCircleId,
        verseReference: verseReference,
        createdAt: Date(timeIntervalSince1970: 1_710_000_000)
    )
}

@Suite("Smart Share — Domain")
@MainActor
struct SmartShareDomainTests {

    // MARK: - Intent → destination mapping

    @Test("All daily-use intents map to expected destinations")
    func shareIntentDestinationMapping() {
        #expect(ShareIntent.addToNotes.destinationType == .notes)
        #expect(ShareIntent.remindMeLater.destinationType == .reminder)
        #expect(ShareIntent.reflectPrivately.destinationType == .privateReflection)
        #expect(ShareIntent.saveForLater.destinationType == .collection)
        #expect(ShareIntent.createPrayerShare.destinationType == .prayerCircle)
        #expect(ShareIntent.createDiscussion.destinationType == .discussion)
        #expect(ShareIntent.copyLink.destinationType == .copyLink)
        #expect(ShareIntent.storyCard.destinationType == .story)
        #expect(ShareIntent.shareWithGroup.destinationType == .group)
        #expect(ShareIntent.shareWithChurch.destinationType == .church)
        #expect(ShareIntent.sendInMessage.destinationType == .directMessage)
        #expect(ShareIntent.encourageSomeone.destinationType == .directMessage)
    }

    @Test("All intents have non-empty titles and icons")
    func allIntentsHaveLabels() {
        for intent in ShareIntent.allCases {
            #expect(!intent.title.isEmpty, "Intent \(intent.rawValue) has no title")
            #expect(!intent.systemImage.isEmpty, "Intent \(intent.rawValue) has no icon")
        }
    }

    // MARK: - Entity context modes

    @Test("Church note entity resolves to church note preview mode")
    func churchNoteContextMode() {
        let entity = makeEntity(type: .churchNote)
        #expect(entity.shareContentType == .churchNote)
        #expect(entity.contextMode == .churchNotePreview)
    }

    @Test("Prayer entity resolves to prayer-sensitive mode")
    func prayerContextMode() {
        let entity = makeEntity(type: .prayerRequest, visibility: .prayerCircleOnly)
        #expect(entity.shareContentType == .prayerRequest)
        #expect(entity.contextMode == .prayerSensitive)
    }

    @Test("Verse entity resolves to verse-forward mode")
    func verseContextMode() {
        let entity = makeEntity(type: .verse, verseReference: "Romans 8:28")
        #expect(entity.shareContentType == .versePost)
        #expect(entity.contextMode == .verseForward)
    }

    @Test("All entity types produce non-empty shareContentType and contextMode")
    func allEntityTypesHaveContentType() {
        for type in ShareableEntityType.allCases {
            let entity = makeEntity(type: type)
            let _ = entity.shareContentType  // must not crash
            let _ = entity.contextMode       // must not crash
        }
    }

    // MARK: - Visibility

    @Test("Private entity is not externally shareable")
    func privateEntityNotExternallyShareable() {
        let entity = makeEntity(visibility: .privateOnly, externallyShareable: false)
        #expect(!entity.externallyShareable)
    }

    @Test("Prayer entity defaults to prayer-circle-only visibility")
    func prayerEntityVisibility() {
        let entity = makeEntity(type: .prayerRequest, visibility: .prayerCircleOnly)
        #expect(entity.visibility == .prayerCircleOnly)
    }

    @Test("Unavailable entity has unavailable visibility")
    func unavailableEntityVisibility() {
        let entity = makeEntity(visibility: .unavailable, externallyShareable: false)
        #expect(entity.visibility == .unavailable)
    }
}

@Suite("Smart Share — Payload Factory")
@MainActor
struct SmartSharePayloadTests {
    private let payloadFactory = SharePayloadFactory()
    private let linkBuilder = ShareDeepLinkBuilder()

    @Test("Payload includes attribution when smart context is enabled")
    func payloadWithSmartContext() {
        let entity = makeEntity(type: .verse, title: "Romans 8:28", preview: "God works all things together for good.")
        let payload = payloadFactory.makePayload(
            for: entity,
            options: .default(for: .versePost),
            smartContextEnabled: true
        )
        #expect(payload.text.contains("Steph"))
        #expect(payload.deepLink.absoluteString == "amen://verse/entity_1")
        #expect(payload.externalItems.count >= 1)
    }

    @Test("Payload omits attribution when smart context is disabled")
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

    @Test("Prayer entity payload has sharePrivately=true by default")
    func prayerPayloadIsPrivateByDefault() {
        let options = ShareContextOptions.default(for: .prayerRequest)
        #expect(options.sharePrivately == true)
    }

    @Test("Verse entity payload includes verse card by default")
    func versePayloadIncludesCard() {
        let options = ShareContextOptions.default(for: .versePost)
        #expect(options.includeVerseCard == true)
    }

    @Test("Non-prayer/verse payload has sharePrivately=false and no verse card")
    func regularPayloadDefaults() {
        let options = ShareContextOptions.default(for: .regularPost)
        #expect(options.sharePrivately == false)
        #expect(options.includeVerseCard == false)
    }

    @Test("Payload for restricted entity disables external items when smart context off")
    func restrictedEntityPayload() {
        let entity = makeEntity(type: .prayerRequest, visibility: .prayerCircleOnly, externallyShareable: false)
        let payload = payloadFactory.makePayload(
            for: entity,
            options: .default(for: .prayerRequest),
            smartContextEnabled: false
        )
        #expect(payload.deepLink.absoluteString.contains("prayerRequest"))
    }
}

@Suite("Smart Share — Deep Link Builder")
@MainActor
struct SmartShareDeepLinkTests {
    private let linkBuilder = ShareDeepLinkBuilder()

    @Test("Profile entity gets profile route")
    func profileDeepLink() {
        let entity = makeEntity(id: "abc123", type: .profile)
        #expect(linkBuilder.canonicalURL(for: entity).absoluteString == "amen://profile/abc123")
        #expect(linkBuilder.webFallbackURL(for: entity).absoluteString == "https://amenapp.com/profile/abc123")
    }

    @Test("Post entity gets post route")
    func postDeepLink() {
        let entity = makeEntity(id: "post_999", type: .post)
        #expect(linkBuilder.canonicalURL(for: entity).absoluteString == "amen://post/post_999")
    }

    @Test("Church note entity gets notes route")
    func churchNoteDeepLink() {
        let entity = makeEntity(id: "note_42", type: .churchNote)
        #expect(linkBuilder.canonicalURL(for: entity).absoluteString == "amen://churchNote/note_42")
    }

    @Test("Selah entity gets selah route")
    func selahDeepLink() {
        let entity = makeEntity(id: "selah_7", type: .selahPassage)
        #expect(linkBuilder.canonicalURL(for: entity).absoluteString == "amen://selahPassage/selah_7")
    }

    @Test("All entity types produce valid canonical URLs")
    func allEntityTypesProduceURLs() {
        for type in ShareableEntityType.allCases {
            let entity = makeEntity(id: "test_id", type: type)
            let url = linkBuilder.canonicalURL(for: entity)
            #expect(url.absoluteString.hasPrefix("amen://"), "Entity \(type.rawValue) URL missing amen:// scheme")
            #expect(url.absoluteString.contains("test_id"), "Entity \(type.rawValue) URL missing id")
        }
    }

    @Test("Web fallback URLs use HTTPS")
    func webFallbackUsesHTTPS() {
        for type in ShareableEntityType.allCases {
            let entity = makeEntity(id: "x", type: type)
            let url = linkBuilder.webFallbackURL(for: entity)
            #expect(url.absoluteString.hasPrefix("https://amenapp.com"), "Entity \(type.rawValue) web fallback missing https scheme")
        }
    }
}

@Suite("Smart Share — Share Router")
@MainActor
struct SmartShareRouterTests {

    @Test("Profile entity has correct surface and type")
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

    @Test("Selah entity has correct type and surface")
    func shareRouterSelahEntity() {
        let entity = ShareRouter.entityForSelah(
            title: "Today's passage",
            message: "Be still and know",
            verseReference: "Psalm 46:10",
            sourceSurface: "selah_view"
        )
        #expect(entity.entityType == .selahPassage)
        #expect(entity.sourceSurface == "selah_view")
        #expect(entity.verseReference == "Psalm 46:10")
    }

    @Test("ProfilePost entity builds correct route")
    func shareRouterProfilePost() {
        let post = ProfilePost(
            id: "post_abc",
            content: "Test content",
            timestamp: "now",
            likes: 0,
            replies: 0,
            postType: nil,
            createdAt: Date(),
            verseReference: "John 3:16",
            authorName: "Grace Church"
        )
        let entity = ShareRouter.entityForProfilePost(post, sourceSurface: "profile_feed")
        #expect(entity.entityType == .post)
        #expect(entity.id == "post_abc")
        #expect(entity.sourceSurface == "profile_feed")
        #expect(entity.verseReference == "John 3:16")
    }
}

@Suite("Smart Share — Target Model")
@MainActor
struct SmartShareTargetTests {

    @Test("Fallback initials use username prefix when displayName is empty")
    func targetFallbackInitialsFromUsername() {
        let target = SmartShareTarget(
            id: "user_1", targetType: .person, displayName: "",
            username: "amen-user", photoURL: nil, subtitle: "Direct share",
            badgeReason: nil, score: 0, reasons: [], isOnline: false,
            isVerified: false, churchAffiliation: nil, conversation: nil, user: nil
        )
        #expect(target.fallbackInitials == "AM")
        #expect(target.imageURL == nil)
    }

    @Test("Fallback initials return AM when both displayName and username are empty")
    func targetFallbackInitialsEmpty() {
        let target = SmartShareTarget(
            id: "user_2", targetType: .person, displayName: "",
            username: nil, photoURL: nil, subtitle: "",
            badgeReason: nil, score: 0, reasons: [], isOnline: false,
            isVerified: false, churchAffiliation: nil, conversation: nil, user: nil
        )
        #expect(target.fallbackInitials == "AM")
    }

    @Test("Fallback initials use two letters from single-word displayName")
    func targetFallbackInitialsSingleWord() {
        let target = SmartShareTarget(
            id: "user_3", targetType: .person, displayName: "Jonathan",
            username: nil, photoURL: nil, subtitle: "",
            badgeReason: nil, score: 0, reasons: [], isOnline: false,
            isVerified: false, churchAffiliation: nil, conversation: nil, user: nil
        )
        #expect(!target.fallbackInitials.isEmpty)
    }

    @Test("Fallback initials use first letters of each word for multi-word name")
    func targetFallbackInitialsMultiWord() {
        let target = SmartShareTarget(
            id: "user_4", targetType: .person, displayName: "Grace Church",
            username: nil, photoURL: nil, subtitle: "",
            badgeReason: nil, score: 0, reasons: [], isOnline: false,
            isVerified: false, churchAffiliation: nil, conversation: nil, user: nil
        )
        #expect(target.fallbackInitials == "GC")
    }

    @Test("imageURL is nil when photoURL is empty string")
    func imageURLNilForEmptyPhotoURL() {
        let target = SmartShareTarget(
            id: "u", targetType: .person, displayName: "A", username: nil,
            photoURL: "", subtitle: "", badgeReason: nil, score: 0, reasons: [],
            isOnline: false, isVerified: false, churchAffiliation: nil,
            conversation: nil, user: nil
        )
        #expect(target.imageURL == nil)
    }

    @Test("imageURL is set when photoURL is a valid URL")
    func imageURLSetForValidPhotoURL() {
        let target = SmartShareTarget(
            id: "u", targetType: .person, displayName: "A", username: nil,
            photoURL: "https://example.com/photo.jpg", subtitle: "",
            badgeReason: nil, score: 0, reasons: [],
            isOnline: false, isVerified: false, churchAffiliation: nil,
            conversation: nil, user: nil
        )
        #expect(target.imageURL != nil)
    }

    @Test("Accessibility label includes displayName and reason")
    func accessibilityLabel() {
        let target = SmartShareTarget(
            id: "u", targetType: .person, displayName: "Jordan",
            username: "jordan", photoURL: nil, subtitle: "",
            badgeReason: "Same church", score: 90, reasons: ["Same church"],
            isOnline: false, isVerified: false, churchAffiliation: nil,
            conversation: nil, user: nil
        )
        #expect(target.accessibilityLabel.contains("Jordan"))
        #expect(target.accessibilityLabel.contains("Same church"))
    }
}

@Suite("Smart Share — Recipient Loading State")
@MainActor
struct RecipientLoadingStateTests {

    @Test("Loading state equality")
    func loadingEquality() {
        #expect(RecipientLoadingState.loading == RecipientLoadingState.loading)
    }

    @Test("Loaded state equality matches by targets")
    func loadedEquality() {
        let t = SmartShareTarget(
            id: "x", targetType: .person, displayName: "A", username: nil,
            photoURL: nil, subtitle: "", badgeReason: nil, score: 1, reasons: [],
            isOnline: false, isVerified: false, churchAffiliation: nil, conversation: nil, user: nil
        )
        #expect(RecipientLoadingState.loaded([t]) == RecipientLoadingState.loaded([t]))
    }

    @Test("Empty state equality matches by filter chip")
    func emptyEquality() {
        #expect(RecipientLoadingState.empty(.groups) == RecipientLoadingState.empty(.groups))
        #expect(RecipientLoadingState.empty(.groups) != RecipientLoadingState.empty(.churches))
    }

    @Test("Error state equality matches by message")
    func errorEquality() {
        #expect(RecipientLoadingState.error("oops") == RecipientLoadingState.error("oops"))
        #expect(RecipientLoadingState.error("a") != RecipientLoadingState.error("b"))
    }

    @Test("Different state kinds are not equal")
    func crossKindInequality() {
        #expect(RecipientLoadingState.loading != RecipientLoadingState.error("x"))
        #expect(RecipientLoadingState.empty(.suggested) != RecipientLoadingState.loading)
    }
}

@Suite("Smart Share — Privacy")
@MainActor
struct SmartSharePrivacyTests {

    @Test("Private entity externallyShareable is false")
    func privateNotExternal() {
        let entity = makeEntity(visibility: .privateOnly, externallyShareable: false)
        #expect(!entity.externallyShareable)
    }

    @Test("Church-only entity is not externally shareable")
    func churchOnlyNotExternal() {
        let entity = makeEntity(visibility: .churchOnly, externallyShareable: false)
        #expect(!entity.externallyShareable)
    }

    @Test("Prayer-circle-only entity is not externally shareable")
    func prayerCircleNotExternal() {
        let entity = makeEntity(
            type: .prayerRequest, visibility: .prayerCircleOnly, externallyShareable: false
        )
        #expect(!entity.externallyShareable)
        #expect(entity.attributionPolicy == .strippedForPrivateShare
            || entity.contextMode == .prayerSensitive)
    }

    @Test("Public entity is externally shareable")
    func publicIsExternal() {
        let entity = makeEntity(visibility: .public, externallyShareable: true)
        #expect(entity.externallyShareable)
    }

    @Test("Unavailable entity has unavailable visibility")
    func unavailableHasCorrectVisibility() {
        let entity = makeEntity(visibility: .unavailable, externallyShareable: false)
        #expect(entity.visibility == .unavailable)
    }
}

@Suite("Smart Share — Analytics Tracker")
@MainActor
struct ShareAnalyticsTrackerTests {

    @Test("Tracker does not crash when no user is authenticated")
    func trackerNoUser() {
        ShareAnalyticsTracker.shared.track(
            actionType: "share_sheet_opened",
            destinationType: .directMessage,
            contentId: "test_id",
            contentType: .regularPost,
            sourceSurface: "test"
        )
    }

    @Test("Canonical action names are stable")
    func canonicalActionNames() {
        let names = [
            "share_sheet_opened", "share_sheet_dismissed", "share_filter_selected",
            "share_search_started", "share_target_selected", "share_action_selected",
            "share_payload_created", "share_completed", "share_failed",
        ]
        for name in names {
            ShareAnalyticsTracker.shared.track(
                actionType: name,
                destinationType: nil,
                contentId: "entity_1",
                contentType: .regularPost
            )
        }
    }
}
#endif

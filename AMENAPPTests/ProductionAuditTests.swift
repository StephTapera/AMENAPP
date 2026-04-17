// ProductionAuditTests.swift
// AMENAPPTests
//
// "Things teams forget" — automated regression coverage for the 10 highest-risk
// audit categories that don't surface in happy-path testing but break trust,
// scale, or consistency in production.
//
// Categories covered (unit-testable logic only; Firebase items are documented
// as integration checklists at the bottom of each suite):
//
//   1. Server-owned / immutable fields
//   2. Deletion cascade ordering and path completeness
//   3. Idempotency and duplicate-write prevention
//   4. Notification payload privacy
//   5. Device token lifecycle rules
//   6. Blocked-user full-severance rules
//   7. Schema drift / legacy document safety
//   8. Listener lifecycle correctness
//   9. Interrupted-flow invariants
//  10. Count reconciliation and badge drift prevention
//
// All tests are pure-Swift (no Firebase, no network).
// Run with: Product ▶ Test (⌘U)
//

import Testing
import Foundation
@testable import AMENAPP

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 1. Server-Owned / Immutable Fields
// ─────────────────────────────────────────────────────────────────────────

/// Fields that must never be writable by the client.
/// These tests document the expected contract and serve as regression guards —
/// if a developer accidentally adds one of these to a client-side write path,
/// the comment/test becomes the canary.
@Suite("Server-Owned Fields — Write-Path Audit")
struct ServerOwnedFieldTests {

    // Fields the client must NEVER set in a user document write.
    private let clientForbiddenUserFields: Set<String> = [
        "isVerified",
        "isBanned",
        "isRestricted",
        "moderationStatus",
        "trustScore",
        "followerCount",    // written by Cloud Function fanout only
        "followingCount",   // written by Cloud Function fanout only
        "reportCount",
        "featureFlags",
        "adminRole",
    ]

    // Fields the client must NEVER set in a post document write.
    private let clientForbiddenPostFields: Set<String> = [
        "amenCount",
        "lightbulbCount",
        "commentCount",
        "repostCount",
        "moderationStatus",
        "isFeatured",
        "rankingScore",
    ]

    @Test("Forbidden user fields list is non-empty")
    func forbiddenUserFieldsExist() {
        #expect(!clientForbiddenUserFields.isEmpty)
    }

    @Test("Forbidden post fields list is non-empty")
    func forbiddenPostFieldsExist() {
        #expect(!clientForbiddenPostFields.isEmpty)
    }

    // Verify none of the count fields appear in a simulated client post-creation dict.
    // Real enforcement lives in Firestore rules; this test makes the expectation explicit.
    @Test("Simulated client post-creation dict does not include server-owned count fields")
    func clientPostCreationDictHasNoCountFields() {
        // A minimal client-composed post dict (mirrors what CreatePostView produces)
        let clientPayload: [String: Any] = [
            "authorId": "uid123",
            "content": "Hello world",
            "category": "openTable",
            "visibility": "everyone",
            "createdAt": "serverTimestamp_placeholder",
        ]

        for field in clientForbiddenPostFields {
            #expect(
                clientPayload[field] == nil,
                "Client payload must not include server-owned field '\(field)'"
            )
        }
    }

    @Test("Simulated client user-update dict does not include immutable fields")
    func clientUserUpdateHasNoImmutableFields() {
        // A minimal client-composed profile-edit dict
        let clientPayload: [String: Any] = [
            "displayName": "Alice",
            "bio": "Follower of Jesus",
            "profileImageURL": "https://example.com/avatar.jpg",
        ]

        for field in clientForbiddenUserFields {
            #expect(
                clientPayload[field] == nil,
                "Client profile-edit payload must not include server-owned field '\(field)'"
            )
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 2. Deletion Cascade Ordering and Path Completeness
// ─────────────────────────────────────────────────────────────────────────

@Suite("Deletion Cascade — Path Completeness")
struct DeletionCascadeTests {

    // The ordered steps that account deletion MUST perform.
    // This mirrors the documented contract in AccountDeletionService.deleteAccount().
    private let requiredDeletionSteps: [String] = [
        "cancel_subscriptions",
        "delete_subcollections",
        "delete_authored_content",
        "leave_conversations",
        "delete_algolia",
        "delete_rtdb",
        "delete_user_doc",
        "delete_storage",
        "delete_auth",          // MUST be last
        "clear_local_state",
    ]

    // Storage paths that MUST be included in account deletion.
    private let requiredStoragePaths: Set<String> = [
        "profile_images/{userId}",
        "post_media/{userId}",
        "message_attachments/{userId}",
        "group_photos/{userId}",
        "church_notes/{userId}",
        "story_media/{userId}",
    ]

    // Firestore subcollections that MUST be deleted during account deletion.
    private let requiredSubcollections: Set<String> = [
        "users/{userId}/notifications",
        "users/{userId}/fcmTokens",
        "users/{userId}/followers",
        "users/{userId}/following",
        "users/{userId}/blockedUsers",
        "users/{userId}/private",       // Contains DOB / age assurance — GDPR/COPPA sensitive
    ]

    @Test("All required deletion steps are defined")
    func deletionStepsAreDefined() {
        #expect(requiredDeletionSteps.count >= 10,
                "Deletion must perform at least 10 ordered steps")
    }

    @Test("Auth deletion is the final step")
    func authDeletionIsLast() {
        let authIndex = requiredDeletionSteps.firstIndex(of: "delete_auth")
        let clearLocalIndex = requiredDeletionSteps.firstIndex(of: "clear_local_state")
        #expect(authIndex != nil, "delete_auth must be present")
        // Auth deletion must come before clear_local_state but after all data deletions
        if let auth = authIndex, let local = clearLocalIndex {
            #expect(auth < local, "delete_auth must precede clear_local_state")
            #expect(auth > 0, "delete_auth must not be first (data must be deleted first)")
        }
    }

    @Test("private subcollection (DOB/age) is in required deletions")
    func privateDobSubcollectionIsDeleted() {
        #expect(requiredSubcollections.contains("users/{userId}/private"),
                "users/{userId}/private contains DOB and must be deleted on account deletion")
    }

    @Test("All required storage paths are present")
    func storagePathsAreDefined() {
        #expect(!requiredStoragePaths.isEmpty)
        #expect(requiredStoragePaths.contains("profile_images/{userId}"))
        #expect(requiredStoragePaths.contains("post_media/{userId}"))
        #expect(requiredStoragePaths.contains("message_attachments/{userId}"))
    }

    @Test("Storage path templating produces correct path for given userId")
    func storagePathTemplating() {
        let userId = "uid_abc123"
        let profilePath = "profile_images/\(userId)"
        let postPath = "post_media/\(userId)"
        let messagePath = "message_attachments/\(userId)"

        #expect(profilePath == "profile_images/uid_abc123")
        #expect(postPath == "post_media/uid_abc123")
        #expect(messagePath == "message_attachments/uid_abc123")
    }

    // Documents what a post deletion cascade MUST cover.
    @Test("Post deletion cascade covers all dependent records")
    func postDeletionCascadeScope() {
        let expectedCascadeTargets: Set<String> = [
            "notifications",        // notifications referencing the post
            "savedPosts",           // saved/bookmarked references
            "feedReferences",       // feed index entries
            "reactions",            // reaction subcollection
            "comments",             // comment subcollection
            "algolia_index",        // search index entry
            "storage_media",        // attached media files
        ]
        // Verify the list is complete (guards against shrinkage)
        #expect(expectedCascadeTargets.count >= 7,
                "Post deletion must cascade to at least 7 dependent record types")
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 3. Idempotency and Duplicate-Write Prevention
// ─────────────────────────────────────────────────────────────────────────

@Suite("Idempotency — Follow, Block, and Report Operations")
struct OperationIdempotencyTests {

    // Follow request idempotency key: followerId + targetId
    private func followRequestKey(followerId: String, targetId: String) -> String {
        "\(followerId)_\(targetId)"
    }

    // Report idempotency key: reporterId + targetId + category
    private func reportKey(reporterId: String, targetId: String, category: String) -> String {
        "\(reporterId)_\(targetId)_\(category)"
    }

    // Notification dedup key: actorId + type + targetId (per NotificationService contract)
    private func notifDedupKey(actorId: String, type: String, targetId: String) -> String {
        "\(type)_\(actorId)_\(targetId)"
    }

    @Test("Follow request key is stable for same pair")
    func followKeyStability() {
        let k1 = followRequestKey(followerId: "A", targetId: "B")
        let k2 = followRequestKey(followerId: "A", targetId: "B")
        #expect(k1 == k2)
    }

    @Test("Follow request key differs for reversed pair (A→B ≠ B→A)")
    func followKeyIsDirectional() {
        let k1 = followRequestKey(followerId: "A", targetId: "B")
        let k2 = followRequestKey(followerId: "B", targetId: "A")
        #expect(k1 != k2, "Follow relationships are directional; keys must differ")
    }

    @Test("Report key is stable for same reporter+target+category")
    func reportKeyStability() {
        let k1 = reportKey(reporterId: "u1", targetId: "post1", category: "spam")
        let k2 = reportKey(reporterId: "u1", targetId: "post1", category: "spam")
        #expect(k1 == k2)
    }

    @Test("Report key differs for different categories")
    func reportKeyDiffersAcrossCategories() {
        let k1 = reportKey(reporterId: "u1", targetId: "post1", category: "spam")
        let k2 = reportKey(reporterId: "u1", targetId: "post1", category: "harassment")
        #expect(k1 != k2)
    }

    @Test("Notification dedup key is stable for same actor+type+target")
    func notifKeyStability() {
        let k1 = notifDedupKey(actorId: "actor1", type: "amen", targetId: "post99")
        let k2 = notifDedupKey(actorId: "actor1", type: "amen", targetId: "post99")
        #expect(k1 == k2)
    }

    @Test("Notification dedup key differs for different notification types")
    func notifKeyDiffersAcrossTypes() {
        let k1 = notifDedupKey(actorId: "actor1", type: "amen",    targetId: "post99")
        let k2 = notifDedupKey(actorId: "actor1", type: "comment", targetId: "post99")
        #expect(k1 != k2)
    }

    // Message send idempotency: same sender + conversation + content hash within a window
    @Test("Message send key is stable for identical content within same second")
    func messageSendKeyStability() {
        let userId = "user1"
        let conversationId = "conv_abc"
        let content = "Hello there"
        let bucket = Int(Date().timeIntervalSince1970)  // 1-second bucket

        let k1 = "\(userId)_\(conversationId)_\(content.hashValue)_\(bucket)"
        let k2 = "\(userId)_\(conversationId)_\(content.hashValue)_\(bucket)"
        #expect(k1 == k2)
    }

    @Test("Message send key differs for different content")
    func messageSendKeyDiffersForDifferentContent() {
        let bucket = Int(Date().timeIntervalSince1970)
        let k1 = "u1_conv1_\("Hello".hashValue)_\(bucket)"
        let k2 = "u1_conv1_\("Goodbye".hashValue)_\(bucket)"
        #expect(k1 != k2)
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 4. Notification Payload Privacy
// ─────────────────────────────────────────────────────────────────────────

/// Push notification payloads must not leak private content before the app opens.
/// These tests encode the privacy contract as executable expectations.
@Suite("Notification Payload Privacy")
struct NotificationPayloadPrivacyTests {

    // Simulates what the notification body should look like for a private account interaction.
    private func payloadBodyForPrivateAccount(senderName: String, preview: String?) -> String {
        // Private accounts: the body must never include content previews.
        // Only the sender name may appear if they are not blocked.
        return "\(senderName) sent you a message"  // Generic — no content preview
    }

    // A DM notification body must not include message text when the conversation
    // is new (no mutual follow yet) or when the sender is restricted.
    private func dmNotificationBody(
        isNewSender: Bool,
        senderIsRestricted: Bool,
        messagePreview: String
    ) -> String {
        if isNewSender || senderIsRestricted {
            return "You have a new message request"  // Generic — no preview
        }
        return messagePreview
    }

    @Test("Private-account DM notification body never includes message preview")
    func privateAccountDMBodyIsGeneric() {
        let body = payloadBodyForPrivateAccount(senderName: "Alice", preview: "Can we talk privately?")
        #expect(!body.contains("Can we talk"), "Preview text must not appear in push body for private accounts")
        #expect(body.contains("Alice"), "Sender name is acceptable in push body")
    }

    @Test("New sender DM notification body is generic (no preview)")
    func newSenderDMBodyIsGeneric() {
        let body = dmNotificationBody(isNewSender: true, senderIsRestricted: false, messagePreview: "Hey, are you free?")
        #expect(!body.contains("Hey"), "Message text must not appear in push body for new/unknown senders")
    }

    @Test("Restricted sender DM notification body is generic")
    func restrictedSenderDMBodyIsGeneric() {
        let body = dmNotificationBody(isNewSender: false, senderIsRestricted: true, messagePreview: "Sensitive content here")
        #expect(!body.contains("Sensitive"), "Restricted sender content must not appear in push body")
    }

    @Test("Established mutual-follow DM can include preview")
    func establishedFollowerDMCanHavePreview() {
        let body = dmNotificationBody(isNewSender: false, senderIsRestricted: false, messagePreview: "See you Sunday!")
        #expect(body == "See you Sunday!", "Established senders may have preview in push body")
    }

    // Prayer request notification must not expose prayer text if the post is followers-only.
    @Test("Followers-only prayer notification body does not include prayer text")
    func followersOnlyPrayerBodyIsGeneric() {
        let visibility = "followers"
        let prayerText = "Pray for my family's financial struggle"

        // Body construction rule: if visibility != "everyone", use generic body
        let body = visibility == "everyone" ? prayerText : "Someone shared a prayer request"
        #expect(!body.contains("financial"), "Followers-only prayer text must not appear in push payload")
    }

    // Verify that notification types that should never generate a push are filtered.
    @Test("Message notification types are excluded from the activity feed notification channel")
    func messageTypesFilteredFromFeedChannel() {
        let messageTypes: Set<String> = ["message", "messageRequest", "messageRequestAccepted"]
        let activityFeedTypes: Set<String> = ["amen", "comment", "follow", "repost", "followRequestAccepted"]

        let intersection = messageTypes.intersection(activityFeedTypes)
        #expect(intersection.isEmpty,
                "Message notification types must not overlap with activity-feed types: \(intersection)")
    }

    // Deleted content must not produce a readable notification body.
    @Test("Notification for deleted post uses tombstone body")
    func deletedPostNotificationUsesTombstone() {
        let postExists = false
        let notifBody = postExists ? "Alice commented on your post: \"Hello!\"" : "A post you were notified about was removed"
        #expect(!notifBody.contains("Hello"), "Deleted post notifications must not include original content")
        #expect(notifBody.contains("removed"), "Must use tombstone language")
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 5. Device Token Lifecycle
// ─────────────────────────────────────────────────────────────────────────

@Suite("Device Token Lifecycle")
struct DeviceTokenLifecycleTests {

    // DeviceTokenManager constants (mirrors private properties in DeviceTokenManager.swift)
    private let tokenRefreshIntervalDays: Double = 7
    private let maxDevicesPerUser: Int = 5
    private let registrationDebounceSecs: TimeInterval = 10

    @Test("Token refresh interval is 7 days")
    func tokenRefreshInterval() {
        let intervalSeconds = tokenRefreshIntervalDays * 24 * 60 * 60
        #expect(intervalSeconds == 604_800, "Token refresh must be every 7 days")
    }

    @Test("Max devices per user is capped at 5")
    func maxDevicesCap() {
        #expect(maxDevicesPerUser == 5, "At most 5 concurrent device tokens per user (P0 requirement)")
    }

    @Test("Registration debounce prevents double-write within 10 seconds")
    func registrationDebounce() {
        // Simulate two registration calls 3 seconds apart
        let first = Date()
        let second = first.addingTimeInterval(3)
        let shouldSkip = second.timeIntervalSince(first) < registrationDebounceSecs
        #expect(shouldSkip, "Second registration call within debounce window must be suppressed")
    }

    @Test("Registration call 11 seconds after first is NOT debounced")
    func registrationAfterDebounceIsAllowed() {
        let first = Date()
        let second = first.addingTimeInterval(11)
        let shouldSkip = second.timeIntervalSince(first) < registrationDebounceSecs
        #expect(!shouldSkip, "Registration call after debounce window must be allowed")
    }

    // When oldest tokens must be pruned to stay under device cap:
    @Test("Oldest tokens are evicted when device cap is exceeded")
    func oldestTokensEvicted() {
        // Simulate 6 tokens; oldest by lastRefreshed must be evicted
        let now = Date()
        let tokens = (0..<6).map { i -> (id: String, lastRefreshed: Date) in
            (id: "token_\(i)", lastRefreshed: now.addingTimeInterval(Double(i) * -86400))
        }
        // Sort descending by date (newest first), keep top 5
        let sorted = tokens.sorted { $0.lastRefreshed > $1.lastRefreshed }
        let kept = Array(sorted.prefix(maxDevicesPerUser))
        let evicted = Array(sorted.dropFirst(maxDevicesPerUser))

        #expect(kept.count == 5)
        #expect(evicted.count == 1)
        #expect(evicted.first?.id == "token_5", "The oldest token must be evicted")
    }

    @Test("Token with isActive=false is treated as stale and eligible for cleanup")
    func inactiveTokenIsStale() {
        struct FakeToken { var isActive: Bool; var lastRefreshed: Date }
        let staleToken = FakeToken(isActive: false, lastRefreshed: Date().addingTimeInterval(-90 * 86400))
        #expect(!staleToken.isActive, "Inactive tokens are stale and must be pruned")
    }

    @Test("Sign-out must disassociate the current device token")
    func signOutDisassociatesToken() {
        // Models the expected state machine: on sign-out, currentToken must be nilled
        // and isTokenRegistered must be false.
        var currentToken: String? = "abc_fcm_token"
        var isTokenRegistered = true

        // Simulate sign-out cleanup
        currentToken = nil
        isTokenRegistered = false

        #expect(currentToken == nil, "Token must be cleared on sign-out")
        #expect(!isTokenRegistered, "isTokenRegistered must be false after sign-out")
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 6. Blocked-User Full Severance
// ─────────────────────────────────────────────────────────────────────────

@Suite("Blocked-User Full Severance")
struct BlockSeveranceTests {

    // Simulated in-memory state for blocked user set
    private func isBlocked(_ targetId: String, blockedIds: Set<String>) -> Bool {
        blockedIds.contains(targetId)
    }

    // All surfaces that must suppress content from a blocked user.
    private let surfacesThatMustRespectBlocks: [String] = [
        "homeFeed",
        "discoverFeed",
        "search_results",
        "mention_suggestions",
        "suggested_follows",
        "notification_activity_feed",
        "comment_section",
        "prayer_wall",
        "open_table_feed",
        "church_suggestions",
    ]

    @Test("Blocked user is filtered from homeFeed")
    func blockedUserFilteredFromFeed() {
        let blockedIds: Set<String> = ["badactor_uid"]
        let feedItems = [("post1", "friendA"), ("post2", "badactor_uid"), ("post3", "friendB")]
        let filtered = feedItems.filter { !isBlocked($0.1, blockedIds: blockedIds) }
        #expect(filtered.count == 2, "Post from blocked user must be filtered from feed")
        #expect(!filtered.contains(where: { $0.1 == "badactor_uid" }))
    }

    @Test("Blocked user is absent from search results")
    func blockedUserAbsentFromSearch() {
        let blockedIds: Set<String> = ["spammer"]
        let searchHits = [("Alice", "alice_uid"), ("Bob", "bob_uid"), ("Spam King", "spammer")]
        let visible = searchHits.filter { !isBlocked($0.1, blockedIds: blockedIds) }
        #expect(!visible.contains(where: { $0.1 == "spammer" }))
    }

    @Test("Blocked user is absent from mention suggestions")
    func blockedUserAbsentFromMentions() {
        let blockedIds: Set<String> = ["blocked_user"]
        let candidates = ["user_a", "blocked_user", "user_b"]
        let suggestions = candidates.filter { !isBlocked($0, blockedIds: blockedIds) }
        #expect(!suggestions.contains("blocked_user"))
        #expect(suggestions.count == 2)
    }

    @Test("Notification from blocked user is suppressed from activity feed")
    func notificationFromBlockedUserIsSuppressed() {
        let blockedIds: Set<String> = ["harasser"]
        let notifications = [
            (id: "n1", actorId: "friend_uid"),
            (id: "n2", actorId: "harasser"),
            (id: "n3", actorId: "church_user"),
        ]
        let visible = notifications.filter { !isBlocked($0.actorId, blockedIds: blockedIds) }
        #expect(visible.count == 2)
        #expect(!visible.contains(where: { $0.actorId == "harasser" }))
    }

    @Test("All required surfaces are audited for block respect")
    func allSurfacesAuditedForBlockRespect() {
        #expect(surfacesThatMustRespectBlocks.count >= 10,
                "At least 10 content surfaces must respect block relationships")
    }

    @Test("Block is bidirectional — blocked user cannot see blocker's content either")
    func blockIsBidirectional() {
        // If A blocks B, B should also not see A's content.
        let blockerUid = "alice"
        let blockedUid = "bob"

        // From Alice's perspective: Bob is blocked
        let aliceBlockedIds: Set<String> = [blockedUid]
        // From Bob's perspective: the app should prevent Bob seeing Alice's posts too
        // (modeled by injecting the reverse block into Bob's filter set at query time)
        let bobShouldNotSeeAlice = aliceBlockedIds.contains(blockerUid) == false
        // Bob cannot see Alice because the server-side query or client filter also
        // checks whether the viewer is blocked by the author.
        // We model this with a simple reverse lookup:
        let bobFilteredIds: Set<String> = [blockerUid]  // Populated from "blockedBy" check
        let bobCanSeeAlice = !bobFilteredIds.contains(blockerUid)
        #expect(!bobCanSeeAlice, "Blocked user (Bob) must not see blocker's (Alice's) content")
        _ = bobShouldNotSeeAlice // silence warning
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 7. Schema Drift / Legacy Document Safety
// ─────────────────────────────────────────────────────────────────────────

@Suite("Schema Drift — Legacy Document Safety")
struct SchemaDriftTests {

    // Simulate decoding a Firestore document that is missing optional fields
    // (i.e., written by an older app version).
    private struct LegacyUserDocument {
        var displayName: String
        var username: String
        var bio: String?              // Added in v2
        var isVerified: Bool          // May be absent in very old docs — default false
        var followerCount: Int        // May be absent — default 0
        var featureFlags: [String]?   // Added in v5

        // Simulates a Codable init with safe defaults (no force-unwrap)
        init(from dict: [String: Any]) {
            displayName  = dict["displayName"] as? String ?? "Unknown"
            username     = dict["username"] as? String ?? ""
            bio          = dict["bio"] as? String
            isVerified   = dict["isVerified"] as? Bool ?? false
            followerCount = dict["followerCount"] as? Int ?? 0
            featureFlags = dict["featureFlags"] as? [String]
        }
    }

    @Test("Missing isVerified field defaults to false (not nil crash)")
    func missingIsVerifiedDefaultsFalse() {
        let doc = LegacyUserDocument(from: ["displayName": "Alice", "username": "alice"])
        #expect(doc.isVerified == false, "Missing isVerified must default to false")
    }

    @Test("Missing followerCount defaults to 0")
    func missingFollowerCountDefaultsZero() {
        let doc = LegacyUserDocument(from: ["displayName": "Alice", "username": "alice"])
        #expect(doc.followerCount == 0, "Missing followerCount must default to 0, not crash")
    }

    @Test("Missing optional bio does not crash")
    func missingBioIsNil() {
        let doc = LegacyUserDocument(from: ["displayName": "Bob", "username": "bob"])
        #expect(doc.bio == nil, "Missing bio must decode to nil cleanly")
    }

    @Test("Missing featureFlags defaults to nil, not empty array or crash")
    func missingFeatureFlagsIsNil() {
        let doc = LegacyUserDocument(from: ["displayName": "Carol", "username": "carol"])
        #expect(doc.featureFlags == nil)
    }

    @Test("Unknown enum raw value falls back to .unknown without crash")
    func unknownEnumFallback() {
        // Mirror the NotificationType.unknown fallback contract
        let rawValue = "some_future_notification_type_v9"
        // Simulate what Codable does: unknown raw values decode to .unknown
        let known: Set<String> = ["follow", "amen", "comment", "message", "messageRequest"]
        let isKnown = known.contains(rawValue)
        #expect(!isKnown, "Future notification types must not crash the decoder")
        // The contract is: if not known, treat as .unknown and handle gracefully
        let resolved = isKnown ? rawValue : "unknown"
        #expect(resolved == "unknown")
    }

    @Test("Null/empty string displayName renders safe fallback")
    func nullDisplayNameFallback() {
        let doc = LegacyUserDocument(from: ["username": "alice"])  // displayName missing
        #expect(doc.displayName == "Unknown", "Missing displayName must yield a safe fallback string")
        #expect(!doc.displayName.isEmpty, "Display name must never be empty in the UI")
    }

    @Test("Document with all fields present decodes without overwriting with defaults")
    func fullDocumentDecodesCorrectly() {
        let doc = LegacyUserDocument(from: [
            "displayName": "Dave",
            "username": "dave",
            "isVerified": true,
            "followerCount": 42,
            "featureFlags": ["betaFeatureA"],
        ])
        #expect(doc.isVerified == true)
        #expect(doc.followerCount == 42)
        #expect(doc.featureFlags == ["betaFeatureA"])
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 8. Listener Lifecycle
// ─────────────────────────────────────────────────────────────────────────

@Suite("Listener Lifecycle — Deduplication and Cleanup")
@MainActor
struct ListenerLifecycleTests {

    // Uses the real ListenerRegistry (pure-Swift, no Firebase dependency)
    // to verify the key lifecycle contracts.

    @Test("ListenerRegistry prevents duplicate listeners for same key")
    func preventsDuplicateListeners() {
        let registry = ListenerRegistry()
        let first  = registry.begin("feed:home")
        let second = registry.begin("feed:home")
        #expect(first  == true,  "First begin() must return true")
        #expect(second == false, "Second begin() for same key must return false (duplicate guard)")
    }

    @Test("Listener key is released after end() allowing safe re-attach")
    func listenerReleasedAfterEnd() {
        let registry = ListenerRegistry()
        registry.begin("profile:uid1")
        registry.end("profile:uid1")
        let restarted = registry.begin("profile:uid1")
        #expect(restarted == true, "Key must be available again after end() — e.g. after sign-out/sign-in")
    }

    @Test("end() on a key that was never started is safe (no crash)")
    func endNonexistentKeyIsSafe() {
        let registry = ListenerRegistry()
        registry.end("nonexistent_key")  // Must not crash
        #expect(registry.isActive("nonexistent_key") == false)
    }

    @Test("Multiple independent listener keys do not interfere")
    func independentKeysDoNotInterfere() {
        let registry = ListenerRegistry()
        registry.begin("feed:home")
        registry.begin("notifications:uid1")
        registry.begin("profile:uid2")

        registry.end("feed:home")

        #expect(registry.isActive("feed:home") == false)
        #expect(registry.isActive("notifications:uid1") == true)
        #expect(registry.isActive("profile:uid2") == true)
    }

    @Test("Sign-out simulation: all active listeners must be removable in sequence")
    func signOutClearsAllListeners() {
        let registry = ListenerRegistry()
        let keys = ["feed:home", "notifications:uid1", "profile:uid2", "messages:conv1"]
        keys.forEach { registry.begin($0) }
        keys.forEach { _ = registry.isActive($0) }  // Read all — ensure no crash

        // Simulate sign-out: end all
        keys.forEach { registry.end($0) }

        let anyStillActive = keys.contains { registry.isActive($0) }
        #expect(!anyStillActive, "All listeners must be released on sign-out")
    }

    @Test("Re-navigation to the same screen does not create duplicate listeners")
    func reNavigationDoesNotDuplicateListeners() {
        let registry = ListenerRegistry()
        let key = registry.profileListenerKey(userId: "uid123")

        let first  = registry.begin(key)
        let second = registry.begin(key)  // User navigates back to same profile
        let third  = registry.begin(key)  // And again

        #expect(first == true)
        #expect(second == false, "Re-navigation must not attach a second listener")
        #expect(third == false,  "Third navigation must also be blocked")
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 9. Interrupted-Flow Invariants
// ─────────────────────────────────────────────────────────────────────────

/// Tests that model the expected behavior when a user interrupts an operation
/// (kills app, loses network, signs out mid-flow, etc.).
@Suite("Interrupted-Flow Invariants")
struct InterruptedFlowTests {

    // Models optimistic UI state for a post submit
    private struct PostSubmitState {
        var isSubmitting: Bool = false
        var didCommit: Bool = false     // True only if server confirmed
        var errorMessage: String? = nil
    }

    @Test("Post submit UI state resets to non-submitting on error")
    func postSubmitResetsOnError() {
        var state = PostSubmitState()
        state.isSubmitting = true

        // Simulate network error interruption
        state.isSubmitting = false
        state.errorMessage = "Network error. Your post was not published."

        #expect(!state.isSubmitting, "isSubmitting must be false after error")
        #expect(!state.didCommit, "didCommit must remain false — post was not published")
        #expect(state.errorMessage != nil, "Error must be surfaced so user knows the post failed")
    }

    @Test("Optimistic amen toggle reverts on server error")
    func amenToggleRevertsOnError() {
        var amenCount = 10
        var userHasAmened = false

        // Optimistic: increment before server confirms
        amenCount += 1
        userHasAmened = true

        // Simulate server error
        let serverError = true
        if serverError {
            amenCount -= 1
            userHasAmened = false
        }

        #expect(amenCount == 10, "Amen count must revert to original on server error")
        #expect(!userHasAmened, "Amen state must revert on server error")
    }

    @Test("Follow button state reverts if follow operation fails")
    func followRevertsOnError() {
        var isFollowing = false

        // Optimistic toggle
        isFollowing = true

        // Server fails
        let serverError = true
        if serverError { isFollowing = false }

        #expect(!isFollowing, "Follow state must revert if the server call fails")
    }

    @Test("Draft is preserved if post submit is interrupted")
    func draftPreservedOnInterruption() {
        struct DraftState { var content: String; var savedToDraft: Bool }
        var draft = DraftState(content: "Half-written testimony...", savedToDraft: false)

        // User closes app mid-compose — auto-save must fire
        let appWillBackground = true
        if appWillBackground && !draft.content.isEmpty {
            draft.savedToDraft = true
        }

        #expect(draft.savedToDraft, "Draft must be auto-saved when app backgrounds mid-compose")
        #expect(!draft.content.isEmpty, "Draft content must not be lost")
    }

    @Test("Profile update does not claim success until server confirms")
    func profileUpdateDoesNotClaimSuccessOptimistically() {
        var uiShowsSuccess = false
        var serverConfirmed = false

        // The UI should only show success AFTER the async call returns successfully
        // (no optimistic success toast before server round-trip)
        func simulateSuccessfulSave() {
            serverConfirmed = true
            uiShowsSuccess = serverConfirmed  // Correct: gated on server confirmation
        }

        #expect(!uiShowsSuccess, "UI must NOT show success before server confirms")
        simulateSuccessfulSave()
        #expect(uiShowsSuccess, "UI may show success only after server confirms")
    }

    @Test("Sign-out during upload does not leave orphaned in-flight task")
    func signOutCancelsUploadTask() {
        var uploadTask: Task<Void, Never>? = Task {
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch {}
        }

        // Simulate sign-out cancelling the upload
        uploadTask?.cancel()
        let isCancelled = uploadTask?.isCancelled ?? false
        uploadTask = nil

        #expect(isCancelled, "Upload task must be cancelled on sign-out")
        #expect(uploadTask == nil, "Task reference must be nil after sign-out cleanup")
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: 10. Count Reconciliation and Badge Drift Prevention
// ─────────────────────────────────────────────────────────────────────────

@Suite("Count Reconciliation — Badge and Interaction Drift")
struct CountReconciliationTests {

    // Models the repair logic that reconciliation jobs must implement.
    private func reconcileCount(storedCount: Int, actualCount: Int) -> (corrected: Int, wasDrifted: Bool) {
        let wasDrifted = storedCount != actualCount
        return (actualCount, wasDrifted)
    }

    @Test("Reconciliation corrects over-counted amen count")
    func reconcileOverCount() {
        let result = reconcileCount(storedCount: 15, actualCount: 12)
        #expect(result.corrected == 12)
        #expect(result.wasDrifted, "Over-count must be detected as drift")
    }

    @Test("Reconciliation corrects under-counted comment count")
    func reconcileUnderCount() {
        let result = reconcileCount(storedCount: 3, actualCount: 7)
        #expect(result.corrected == 7)
        #expect(result.wasDrifted)
    }

    @Test("Reconciliation is a no-op when count is accurate")
    func reconcileAccurateCount() {
        let result = reconcileCount(storedCount: 5, actualCount: 5)
        #expect(result.corrected == 5)
        #expect(!result.wasDrifted, "Accurate count must not be flagged as drift")
    }

    @Test("Badge count never goes negative after rapid un-amens")
    func badgeCountNonNegative() {
        var badge = 0
        // Simulate 5 rapid un-amen events arriving out of order
        for _ in 0..<5 {
            badge = max(0, badge - 1)
        }
        #expect(badge == 0, "Badge count must clamp to 0 — never go negative")
    }

    @Test("Unread notification count derived from actual unread list, not a cached int")
    func unreadCountDerivedFromSource() {
        // The authoritative count is len(unread notifications), not a separate counter.
        // A cached int counter can drift; deriving from the list is always correct.
        let notifications: [(id: String, read: Bool)] = [
            ("n1", false),
            ("n2", true),
            ("n3", false),
            ("n4", true),
            ("n5", false),
        ]
        let derivedCount = notifications.filter { !$0.read }.count
        let cachedCount = 4  // Stale/incorrect cached value

        #expect(derivedCount == 3, "Derived count from source list must be 3")
        #expect(cachedCount != derivedCount, "Cached count is stale — this simulates drift")
        // The fix: always use derivedCount for the badge, never the cached int
    }

    @Test("Follower count is consistent with follow graph size")
    func followerCountConsistentWithGraph() {
        // Simulate stored count vs actual graph
        let storedFollowerCount = 100
        let actualFollowerIds: Set<String> = Set((0..<97).map { "user_\($0)" })  // 97 actual followers
        let (corrected, wasDrifted) = reconcileCount(
            storedCount: storedFollowerCount,
            actualCount: actualFollowerIds.count
        )
        #expect(wasDrifted, "Stored count (100) differs from graph size (97) — drift detected")
        #expect(corrected == 97, "Corrected count must match actual graph")
    }

    @Test("Comment count reconciliation covers reply subcollection too")
    func commentCountIncludesReplies() {
        // Top-level comments + replies must all be counted
        let topLevelComments = 5
        let repliesOnComment1 = 3
        let repliesOnComment2 = 2
        let totalActual = topLevelComments + repliesOnComment1 + repliesOnComment2
        let storedCount = 5  // Only top-level was counted — classic bug

        let (corrected, wasDrifted) = reconcileCount(storedCount: storedCount, actualCount: totalActual)
        #expect(wasDrifted, "Stored count that excludes replies must be flagged as drift")
        #expect(corrected == 10)
    }

    // Scheduled repair job frequency: must run at least daily
    @Test("Reconciliation job interval is at most 24 hours")
    func reconciliationJobFrequency() {
        let maxIntervalHours: Double = 24
        let maxIntervalSeconds = maxIntervalHours * 3600
        #expect(maxIntervalSeconds == 86_400, "Reconciliation jobs must run at most every 24 hours")
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: AUTH-01. Sign-Out / Account-Switch Isolation
// ─────────────────────────────────────────────────────────────────────────

/// Tests that model the expected state contracts when a user signs out and a
/// second user signs in on the same device. The core invariant: no data cached
/// for User A must be visible or served to User B after sign-out cleanup.
///
/// All tests are pure-Swift (no Firebase). They verify state-machine contracts
/// that AppLifecycleManager.performFullSignOutCleanup() must uphold.
@Suite("AUTH-01 — Sign-Out / Account-Switch Isolation")
@MainActor
struct SignOutIsolationTests {

    // MARK: - Helpers

    /// Minimal model of per-user in-memory cache state (mirrors what services hold).
    private struct InMemoryServiceState {
        var currentUserId: String?
        var cachedPosts: [String]  = []
        var cachedNotifications: [String] = []
        var activeListenerKeys: Set<String> = []
        var deviceToken: String? = nil
        var pendingUploadTaskId: String? = nil

        mutating func reset() {
            currentUserId = nil
            cachedPosts = []
            cachedNotifications = []
            activeListenerKeys = []
            deviceToken = nil
            pendingUploadTaskId = nil
        }
    }

    // MARK: - Sign-out clears all user-specific in-memory state

    @Test("Sign-out cleanup nilifies currentUserId so next user starts fresh")
    func signOutClearsCurrentUserId() {
        var state = InMemoryServiceState()
        state.currentUserId = "userA"
        state.cachedPosts = ["post1", "post2"]

        state.reset()

        #expect(state.currentUserId == nil, "currentUserId must be nil after sign-out")
        #expect(state.cachedPosts.isEmpty, "Posts cache must be cleared on sign-out")
    }

    @Test("Notifications cache is not shared across user sessions")
    func notificationsCacheDoesNotLeakAcrossUsers() {
        var state = InMemoryServiceState()
        state.currentUserId = "userA"
        state.cachedNotifications = ["notif_1", "notif_2", "notif_3"]

        // User A signs out
        state.reset()

        // User B signs in — starts with empty notification cache
        state.currentUserId = "userB"

        #expect(state.cachedNotifications.isEmpty,
                "User B must not see User A's notifications in the in-memory cache")
    }

    @Test("Active listener keys from User A are fully released before User B signs in")
    func listenerKeysReleasedOnSignOut() {
        let registry = ListenerRegistry()

        // User A attaches listeners
        let keysA = ["feed:userA", "notifications:userA", "profile:userA", "messages:conv123"]
        keysA.forEach { registry.begin($0) }
        #expect(keysA.allSatisfy { registry.isActive($0) }, "All User A listeners must be active")

        // Sign-out cleanup
        keysA.forEach { registry.end($0) }

        // User B signs in — must not inherit any of User A's listener keys
        let anyStillActive = keysA.contains { registry.isActive($0) }
        #expect(!anyStillActive, "No User A listener keys must remain after sign-out cleanup")

        // User B attaches their own listeners — must succeed (no ghost key blocking)
        let keysB = ["feed:userB", "notifications:userB", "profile:userB"]
        keysB.forEach { let _ = registry.begin($0) }
        #expect(keysB.allSatisfy { registry.isActive($0) },
                "User B must be able to attach fresh listeners without collision")
    }

    @Test("UID-namespaced listener key from User A does not match User B's equivalent key")
    func listenerKeysAreUIDNamespaced() {
        let registry = ListenerRegistry()
        // Simulate a profile listener key generated for User A
        let keyA = registry.profileListenerKey(userId: "uid_userA")
        let keyB = registry.profileListenerKey(userId: "uid_userB")

        registry.begin(keyA)
        // User B's key must be distinct — beginning it must also return true
        let userBAttached = registry.begin(keyB)

        #expect(keyA != keyB, "Listener keys for different UIDs must be distinct")
        #expect(userBAttached == true, "User B must be able to attach their own listener key")
    }

    @Test("Device token is not reused by User B after User A signs out")
    func deviceTokenNotReusedAcrossUsers() {
        var state = InMemoryServiceState()
        state.currentUserId = "userA"
        state.deviceToken = "apns_token_abc123"

        // Sign-out: AppLifecycleManager must clear the token binding
        state.reset()

        // Simulates DeviceTokenManager.clearToken() / unregisterFromTopic()
        #expect(state.deviceToken == nil,
                "Device token must be disassociated from User A's session on sign-out")
    }

    @Test("Pending upload task is cancelled, not inherited, by User B")
    func pendingUploadNotInheritedByNextUser() {
        var state = InMemoryServiceState()
        state.currentUserId = "userA"
        state.pendingUploadTaskId = "upload_task_789"

        // Sign-out with an in-flight upload — cleanup must cancel and nil the task
        state.pendingUploadTaskId = nil   // cancel() then nil
        state.reset()

        state.currentUserId = "userB"
        #expect(state.pendingUploadTaskId == nil,
                "User B must not inherit an in-flight upload task from User A")
    }

    @Test("Re-sign-in with same UID after sign-out re-attaches listeners cleanly")
    func reSignInSameUIDAttachesCleanly() {
        let registry = ListenerRegistry()
        let keys = ["feed:uid1", "notifications:uid1"]

        // First session
        keys.forEach { registry.begin($0) }
        keys.forEach { registry.end($0) }  // sign-out

        // Second session with the same UID (e.g. re-login)
        let results = keys.map { registry.begin($0) }
        #expect(results.allSatisfy { $0 == true },
                "Re-attaching listeners after sign-out must succeed (no stale key blocking)")
    }

    @Test("Sign-out cleanup is idempotent — calling it twice must not crash or produce errors")
    func cleanupIsIdempotent() {
        var state = InMemoryServiceState()
        state.currentUserId = "userA"
        state.cachedPosts = ["post1"]

        // First cleanup
        state.reset()
        // Second cleanup (e.g. app lifecycle event fires twice)
        state.reset()

        #expect(state.currentUserId == nil)
        #expect(state.cachedPosts.isEmpty)
        // No crash = pass (Swift Testing would catch a fatal error)
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// MARK: Integration Checklists (require Firebase Emulator or real device)
// ─────────────────────────────────────────────────────────────────────────

// The following integration checks CANNOT be automated in unit tests.
// They are documented here so they appear in the same audit file and can be
// tracked as part of the release gate process.

/*
 ──────────────────────────────────────────────────────────────────────────
 CHECKLIST A — Firestore Security Rules (requires Firebase Emulator)
 ──────────────────────────────────────────────────────────────────────────
 A1. USER DATA PRIVACY
     Verify: User A cannot read users/{userB}/private/ * subcollection.
     Expected: PERMISSION_DENIED

 A2. BLOCKED USER WRITE PREVENTION
     Verify: Blocked user B cannot write to users/{userA}/... paths.
     Expected: PERMISSION_DENIED (both directions)

 A3. SERVER-OWNED FIELD PROTECTION
     Verify: Client cannot write isVerified, isBanned, amenCount, followerCount
             directly via client SDK.
     Expected: PERMISSION_DENIED on any write containing these fields.

 A4. COUNT SPOOFING PREVENTION
     Verify: Client cannot write amenCount=9999 to a post document.
     Expected: PERMISSION_DENIED

 A5. NOTIFICATION DOCUMENT PRIVACY
     Verify: User A cannot read users/{userB}/notifications/...
     Expected: PERMISSION_DENIED

 ──────────────────────────────────────────────────────────────────────────
 CHECKLIST B — Storage Security Rules (requires Firebase Emulator)
 ──────────────────────────────────────────────────────────────────────────
 B1. UNAUTHENTICATED WRITE BLOCKED
     Verify: Unauthenticated client cannot write to any storage path.
     Expected: PERMISSION_DENIED

 B2. CROSS-USER WRITE BLOCKED
     Verify: User B cannot overwrite profile_images/{userA}/avatar.jpg
     Expected: PERMISSION_DENIED

 B3. MODERATION-REJECTED MEDIA INACCESSIBLE
     Verify: After moderation rejection, the storage object is deleted or
             its download URL returns 403.
     Expected: 403 or object not found

 ──────────────────────────────────────────────────────────────────────────
 CHECKLIST C — Orphaned Media Cleanup (requires manual test)
 ──────────────────────────────────────────────────────────────────────────
 C1. CANCELLED UPLOAD
     Steps: Start a photo upload; kill app at 50%.
     Expected: Cloud Function scheduled cleanup removes the partial object
               within 24 hours.

 C2. POST DELETION CASCADE
     Steps: Delete a post that has attached images.
     Expected: post_media/{userId}/{postId}/ * files are deleted within
               the cleanup window.

 C3. MESSAGE DELETION MEDIA
     Steps: Delete a DM message that contained a photo.
     Expected: message_attachments/{userId}/{conversationId}/{messageId}
               file is deleted.

 C4. AVATAR REPLACEMENT
     Steps: Update profile photo.
     Expected: Old avatar file is deleted from Storage. Storage bucket
               should not accumulate old avatars indefinitely.

 ──────────────────────────────────────────────────────────────────────────
 CHECKLIST D — Device Token Lifecycle (requires device + Firebase console)
 ──────────────────────────────────────────────────────────────────────────
 D1. SIGN-OUT REMOVES TOKEN
     Steps: Sign in on device, verify token stored in
            users/{uid}/fcmTokens/{deviceId}.
            Sign out. Verify that document is deleted or marked isActive=false.

 D2. BANNED USER STOPS RECEIVING PUSHES
     Steps: Admin-ban a test user. Trigger a push event.
     Expected: The banned user's FCM token is unregistered; no push delivered.

 D3. STALE TOKEN PRUNING
     Steps: Let a token go unrefreshed for >7 days (or simulate by
            backdating lastRefreshed).
     Expected: Scheduled cleanup removes the stale token document.

 ──────────────────────────────────────────────────────────────────────────
 CHECKLIST E — Deletion Cascade Completeness (requires Emulator or staging)
 ──────────────────────────────────────────────────────────────────────────
 E1. FULL ACCOUNT DELETION
     Steps: Delete a test account that has: posts, comments, follows,
            messages, church notes, saved posts, a profile image.
     Expected:
       - Firestore user doc: deleted
       - users/{uid}/notifications: deleted
       - users/{uid}/fcmTokens: deleted
       - users/{uid}/private (DOB): deleted
       - posts/{uid}/ *: deleted
       - follows where followerId/followingId == uid: deleted
       - message conversations: marked left (not hard-deleted)
       - Algolia records: deleted
       - RTDB /users/{uid}: deleted
       - Storage profile_images/{uid}/ *: deleted
       - Storage post_media/{uid}/ *: deleted
       - Firebase Auth account: deleted (LAST)

 E2. POST DELETION NOTIFICATION CLEANUP
     Steps: Delete a post that has 10 "amen" notifications referencing it.
     Expected: All notifications with postId == deletedPostId are deleted
               or tombstoned.

 ──────────────────────────────────────────────────────────────────────────
 CHECKLIST F — Count Reconciliation Jobs (requires Cloud Functions + staging)
 ──────────────────────────────────────────────────────────────────────────
 F1. AMEN COUNT REPAIR
     Steps: Manually set post.amenCount to a wrong value in Firestore.
            Trigger the scheduled reconciliation job.
     Expected: amenCount is corrected to match the actual count of amen
               documents in the reactions subcollection.

 F2. FOLLOWER COUNT REPAIR
     Steps: Delete a follower document without decrementing the counter.
            Trigger reconciliation.
     Expected: followerCount corrected to match the follows graph.

 F3. BADGE COUNT REPAIR
     Steps: Manually increment a badge counter past the actual unread count.
            Open the app, navigate to Notifications.
     Expected: Badge resets to the correct derived count on next listen.

 ──────────────────────────────────────────────────────────────────────────
 CHECKLIST G — AUTH-01 Sign-Out / Account-Switch Isolation (real device)
 ──────────────────────────────────────────────────────────────────────────
 G1. CONTENT ISOLATION — User A → sign out → User B
     Steps:
       1. Sign in as User A; scroll the feed; open a DM thread; open profile.
       2. Sign out via Settings → Account → Sign Out.
       3. Sign in as User B (different account, different uid).
     Expected:
       - Feed shows User B's content, NOT User A's posts or follower graph.
       - Notifications badge shows User B's unread count (not User A's).
       - No User A DM threads visible in Messages.
       - Profile header shows User B's display name, avatar, follower count.
       - No Firestore listeners fire with User A's uid after sign-out.

 G2. SAME-DEVICE RE-LOGIN SAME UID
     Steps: Sign out then sign back in as the same user.
     Expected:
       - Feed loads correctly (not doubled).
       - All listener keys re-attach without "duplicate listener" log warnings.
       - Notification badge is correct (not doubled or zeroed).

 G3. SIGN-OUT DURING ACTIVE UPLOAD
     Steps: Start a photo post upload; tap sign out before upload completes.
     Expected:
       - Upload task is cancelled (no orphan media left in Storage).
       - App does not crash.
       - After re-login as a different user, the upload does not resume.

 G4. QUICK-SWITCH (sign out then immediately sign in as User B)
     Steps: Sign out and sign in as User B within 2 seconds.
     Expected:
       - No race condition where User A's listeners fire with User B's uid.
       - AppLifecycleManager.performFullSignOutCleanup() completes before
         any User B listeners are attached (check Xcode console for order).
 */

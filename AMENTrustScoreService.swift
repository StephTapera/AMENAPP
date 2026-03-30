//
//  AMENTrustScoreService.swift
//  AMENAPP
//
//  User trust scoring for messaging access control.
//
//  Trust Score determines:
//    - Whether a user can initiate DMs
//    - Whether messages arrive as direct delivery or message requests
//    - DM rate limits
//    - Which contact tier applies
//
//  Score: 0–100
//    90–100  → Verified / Trusted          (full access)
//    70–89   → Good standing               (full access, fast delivery)
//    50–69   → New / Unverified            (message requests to unknown users)
//    25–49   → At-risk                     (message requests only, rate limited)
//    0–24    → Restricted                  (can only reply to existing conversations)
//
//  Score Factors:
//    + Account age                    (up to +20)
//    + Profile completeness           (up to +15)
//    + Human verification badge       (up to +20)
//    + Mutual follow relationships    (up to +15)
//    + Positive engagement history    (up to +10)
//    - Safety violations              (up to -50)
//    - Reports received               (up to -30)
//    - Spam patterns                  (up to -20)
//    - New account (< 7 days)         (-15 flat)
//
//  Rate Limits by Trust Score:
//    90+     → 200 new DMs/day,  unlimited messages in existing convs
//    70–89   → 100 new DMs/day,  unlimited messages in existing convs
//    50–69   → 20 new DMs/day,   200 messages/hour in existing convs
//    25–49   → 5 new DMs/day,    50 messages/hour in existing convs
//    0–24    → reply-only (no new DM initiation)

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - Trust Score Record

struct AMENTrustRecord: Codable {
    let uid: String
    var score: Int                          // 0–100
    var tier: TrustTier
    var accountAgeDays: Int
    var isProfileComplete: Bool
    var isHumanVerified: Bool
    var safetyViolationCount: Int
    var reportCount: Int
    var spamScore: Int                      // 0–100
    var lastUpdated: Date
    var isMessagingRestricted: Bool
    var newDMsInitiatedToday: Int
    var dailyResetDate: Date

    enum TrustTier: String, Codable {
        case verified  = "verified"
        case good      = "good"
        case new       = "new"
        case atRisk    = "at_risk"
        case restricted = "restricted"
    }
}

// MARK: - DM Rate Limit Check Result

enum DMRateLimitResult {
    case allowed
    case exceeded(message: String)
    case replyOnly(message: String)
}

// MARK: - AMENTrustScoreService

@MainActor
final class AMENTrustScoreService: ObservableObject {

    static let shared = AMENTrustScoreService()
    private init() {}

    @Published private(set) var isLoaded = false

    private let db = Firestore.firestore()
    private var cachedRecords: [String: AMENTrustRecord] = [:]

    // MARK: - Load Trust Record

    func trustRecord(for uid: String) async -> AMENTrustRecord {
        if let cached = cachedRecords[uid], Date().timeIntervalSince(cached.lastUpdated) < 300 {
            return cached
        }

        do {
            let doc = try await db.collection("trustRecords").document(uid).getDocument()
            if let data = doc.data(),
               let record = try? Firestore.Decoder().decode(AMENTrustRecord.self, from: data) {
                cachedRecords[uid] = record
                return record
            }
        } catch {}

        // Default for new / unknown accounts
        return AMENTrustRecord(
            uid: uid,
            score: 30,
            tier: .new,
            accountAgeDays: 0,
            isProfileComplete: false,
            isHumanVerified: false,
            safetyViolationCount: 0,
            reportCount: 0,
            spamScore: 0,
            lastUpdated: Date(),
            isMessagingRestricted: false,
            newDMsInitiatedToday: 0,
            dailyResetDate: Date()
        )
    }

    // MARK: - Rate Limit Enforcement

    func checkRateLimit(for uid: String, isNewConversation: Bool) async -> DMRateLimitResult {
        let record = await trustRecord(for: uid)

        // Restricted tier — reply only
        if record.tier == .restricted || record.isMessagingRestricted {
            return .replyOnly(message: "Your account is currently restricted to replying to existing conversations.")
        }

        if isNewConversation {
            let limit = newConversationLimit(for: record.tier)
            if record.newDMsInitiatedToday >= limit {
                return .exceeded(message: "You've reached your daily limit for new conversations. Try again tomorrow.")
            }
        }

        return .allowed
    }

    private func newConversationLimit(for tier: AMENTrustRecord.TrustTier) -> Int {
        switch tier {
        case .verified:   return 200
        case .good:       return 100
        case .new:        return 20
        case .atRisk:     return 5
        case .restricted: return 0
        }
    }

    // MARK: - Increment DM Counter

    func recordNewConversationInitiated(by uid: String) async {
        try? await db.collection("trustRecords").document(uid).updateData([
            "newDMsInitiatedToday": FieldValue.increment(Int64(1))
        ])
        if var cached = cachedRecords[uid] {
            cached.newDMsInitiatedToday += 1
            cachedRecords[uid] = cached
        }
    }

    // MARK: - Contact Tier Determination

    /// Determines the relationship tier between two users for messaging access.
    func contactTier(between senderUID: String, and recipientUID: String) async -> ContactTier {
        // Check block status first — always wins
        let isBlocked = await checkBlocked(senderUID: senderUID, recipientUID: recipientUID)
        if isBlocked { return .blocked }

        // Check mutual follow
        let (senderFollowsRecipient, recipientFollowsSender) = await checkFollowRelationship(
            senderUID: senderUID,
            recipientUID: recipientUID
        )

        if senderFollowsRecipient && recipientFollowsSender {
            return .mutual
        }
        if senderFollowsRecipient {
            return .followed
        }
        return .unknown
    }

    private func checkBlocked(senderUID: String, recipientUID: String) async -> Bool {
        do {
            let doc = try await db.collection("users").document(recipientUID)
                .collection("blockedUsers").document(senderUID).getDocument()
            return doc.exists
        } catch {
            return false
        }
    }

    private func checkFollowRelationship(
        senderUID: String,
        recipientUID: String
    ) async -> (senderFollowsRecipient: Bool, recipientFollowsSender: Bool) {
        async let senderFollows = db.collection("following").document(senderUID)
            .collection("userFollowing").document(recipientUID).getDocument()
        async let recipientFollows = db.collection("following").document(recipientUID)
            .collection("userFollowing").document(senderUID).getDocument()

        do {
            let (sf, rf) = try await (senderFollows, recipientFollows)
            return (sf.exists, rf.exists)
        } catch {
            return (false, false)
        }
    }

    // MARK: - Apply Safety Violation Penalty

    func applySafetyPenalty(to uid: String, severity: Int) async {
        // severity: 1 = minor warn, 2 = block trigger, 3 = hard violation (CSAM/trafficking)
        let penaltyMap = [1: 5, 2: 15, 3: 50]
        let penalty = penaltyMap[severity] ?? 5

        try? await db.collection("trustRecords").document(uid).updateData([
            "safetyViolationCount": FieldValue.increment(Int64(1)),
            "score": FieldValue.increment(Int64(-penalty))
        ])

        if severity == 3 {
            // Immediate messaging restriction for critical violations
            try? await db.collection("trustRecords").document(uid).updateData([
                "isMessagingRestricted": true,
                "tier": AMENTrustRecord.TrustTier.restricted.rawValue
            ])
        }

        cachedRecords.removeValue(forKey: uid)
    }

    // MARK: - Score Computation (Cloud Function triggers this; client reads result)

    /// Triggers a server-side trust score recomputation.
    /// The actual calculation runs in a Cloud Function to prevent gaming.
    func requestScoreRecompute(for uid: String) async {
        try? await db.collection("trustScoreQueue").document(uid).setData([
            "requestedAt": FieldValue.serverTimestamp(),
            "uid": uid
        ])
        cachedRecords.removeValue(forKey: uid)
    }
}

// MARK: - Message Request Model

/// A message request from an unknown or unverified contact.
struct AMENMessageRequest: Identifiable, Codable {
    let id: String
    let conversationId: String
    let fromUID: String
    let fromDisplayName: String
    let fromProfileImageURL: String?
    let previewText: String?          // NEVER shown from actual message — only metadata
    let requestedAt: Date
    var status: RequestStatus

    /// Important: previewText must NEVER contain the actual message body
    /// since messages are E2E encrypted. Only show sender identity + timestamp.

    enum RequestStatus: String, Codable {
        case pending  = "pending"
        case accepted = "accepted"
        case declined = "declined"
        case blocked  = "blocked"
    }
}

// MARK: - Secure Push Notification Stub

/// Ensures push notifications NEVER contain plaintext message content.
/// Actual notification body is only "New message" — content shown only after in-app decryption.
struct AMENSecurePushPayload: Codable {
    let aps: APS
    let conversationId: String
    let senderUID: String
    /// NO messageText, NO encryptedPayload in push payload.
    /// The app fetches and decrypts the message after receiving the silent push.

    struct APS: Codable {
        let alert: Alert
        let badge: Int
        let sound: String
        let contentAvailable: Int

        struct Alert: Codable {
            /// Always generic — never the actual message content.
            let title: String       // e.g. "New message"
            let body: String        // e.g. "You have a new message"
        }

        enum CodingKeys: String, CodingKey {
            case alert
            case badge
            case sound
            case contentAvailable = "content-available"
        }
    }
}

import Foundation
import FirebaseFirestore

// MARK: - Channel Class
//
// Two deliberate security classes — NOT the same code path with a flag.
// - communal:  server-readable; GUARDIAN + Berean operate here
// - sacred:    near-E2E encrypted; adult-only; no AI can read this
// - monitored: forced communal when one participant isMinor (non-negotiable)

enum ChannelClass: String, Codable {
    case communal
    case sacred
    case monitored
}

// MARK: - Channel

struct AmenChannel: Codable, Identifiable {
    @DocumentID var id: String?
    var channelClass: ChannelClass
    var participantUids: [String]       // sorted; empty for group channels
    var groupId: String?                // set for communal group channels
    var discipleshipPairId: String?     // set for discipleship 1:1 channels
    var createdAt: Date
    var lastMessageAt: Date?
    var lastMessagePreview: String?     // always nil for sacred channels — server cannot see content

    enum CodingKeys: String, CodingKey {
        case id, channelClass, participantUids, groupId, discipleshipPairId
        case createdAt, lastMessageAt, lastMessagePreview
    }
}

// MARK: - Communal Message

struct CommunalMessage: Codable, Identifiable {
    @DocumentID var id: String?
    var channelId: String
    var senderId: String
    var text: String
    var createdAt: Date
    // Guardian Cloud Function sets this true (allow/allow_with_support) or false (block/escalate).
    // Listeners filter to isDelivered == true so blocked messages never appear to others.
    var isDelivered: Bool
    var guardianDecision: GuardianDecision?
    var supportResourcesAttached: Bool
    var prayerRequestId: String?        // set by Berean if a prayer request was extracted
    var scriptureRefs: [String]         // verse references detected by Berean, e.g. ["Romans 8:28"]

    enum CodingKeys: String, CodingKey {
        case id, channelId, senderId, text, createdAt, isDelivered
        case guardianDecision, supportResourcesAttached, prayerRequestId, scriptureRefs
    }
}

// MARK: - Sacred Message (ciphertext only — server never sees plaintext)

struct SacredMessage: Codable, Identifiable {
    @DocumentID var id: String?
    var channelId: String
    var senderId: String
    var ciphertextBase64: String
    var nonceBase64: String
    var tagBase64: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, channelId, senderId, ciphertextBase64, nonceBase64, tagBase64, createdAt
    }
}

// MARK: - Guardian Decision

enum GuardianDecision: String, Codable {
    case allow
    case allowWithSupport = "allow_with_support"
    case block
    case escalate
}

// MARK: - Sealed Payload (in-memory only; never stored as a struct in Firestore)

struct SealedPayload {
    let ciphertext: Data
    let nonce: Data
    let tag: Data
}

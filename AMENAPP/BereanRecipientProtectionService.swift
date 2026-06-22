// BereanRecipientProtectionService.swift
// AMENAPP
//
// Protects recipient dignity before harm escalates.
// Invisible until needed. Quiet, calm, non-shaming.

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Recipient Risk Class

enum RecipientRiskClass: String {
    case safe                = "safe"
    case mildForwardness     = "mild_forwardness"
    case boundaryPressure    = "boundary_pressure"
    case sexualPersistence   = "sexual_persistence"
    case coerciveBehavior    = "coercive_behavior"
}

// MARK: - Comfort State

struct RecipientComfortState {
    var riskClass: RecipientRiskClass = .safe
    var showComfortShield: Bool = false        // show the shield pill to recipient
    var blurIncomingMedia: Bool = false        // blur unsolicited media
    var requireMediaApproval: Bool = false     // require tap to view
    var slowSenderReplies: Bool = false        // add delivery delay to sender
    var senderImagesSuspended: Bool = false

    // Signals tracked (no raw message storage)
    var unreciprocatedComplimentCount: Int = 0
    var unansweredMessageRatio: Double = 0
    var pictureRequestCount: Int = 0
    var escalationSlope: Double = 0            // rate of risk increase
    var recipientDiscomfortTaps: Int = 0       // times recipient tapped "I'm uncomfortable"
}

// MARK: - Boundary Message

struct BoundaryMessage: Identifiable {
    let id = UUID()
    let text: String

    static let presets: [BoundaryMessage] = [
        BoundaryMessage(text: "Hey, I'd prefer to keep this respectful."),
        BoundaryMessage(text: "I'm not comfortable with this direction."),
        BoundaryMessage(text: "Let's keep things appropriate.")
    ]
}

// MARK: - Media Consent Request

struct MediaConsentRequest: Identifiable {
    let id: String
    let senderId: String
    let mediaType: String      // "image", "video"
    let riskLevel: Double      // 0.0 – 1.0 from content classifier
    let isBlurred: Bool
    let timestamp: Date
}

// MARK: - Recipient Signal

enum RecipientSignal {
    case unreciprocatedCompliment
    case pictureRequest
    case unansweredMessage
    case recipientDiscomfort     // user tapped "I'm uncomfortable"
    case mediaDeclined
    case escalationDetected
    case conversationIgnored
}

// MARK: - Service

@MainActor
final class BereanRecipientProtectionService: ObservableObject {

    static let shared = BereanRecipientProtectionService()

    @Published var comfortState: RecipientComfortState = RecipientComfortState()
    @Published var pendingMediaRequests: [MediaConsentRequest] = []
    @Published var showComfortShieldFor: String? = nil   // conversationId

    private lazy var db = Firestore.firestore()

    private init() {}

    // MARK: - Signal Tracking

    func trackSignal(_ signal: RecipientSignal, in conversationId: String) {
        switch signal {
        case .unreciprocatedCompliment:
            comfortState.unreciprocatedComplimentCount += 1
        case .pictureRequest:
            comfortState.pictureRequestCount += 1
        case .unansweredMessage:
            let unanswered = Double(comfortState.unansweredMessageRatio * 10) + 1
            comfortState.unansweredMessageRatio = unanswered / max(unanswered + 1, 1)
        case .recipientDiscomfort:
            comfortState.recipientDiscomfortTaps += 1
        case .mediaDeclined:
            comfortState.requireMediaApproval = true
        case .escalationDetected:
            comfortState.escalationSlope += 0.2
        case .conversationIgnored:
            comfortState.unansweredMessageRatio = min(comfortState.unansweredMessageRatio + 0.1, 1.0)
        }

        // Re-evaluate risk class
        let newClass = evaluateRisk(for: conversationId)
        let previous = comfortState.riskClass
        comfortState.riskClass = newClass

        // Activate comfort shield when risk crosses mild threshold
        if newClass != .safe && previous == .safe {
            comfortState.showComfortShield = true
            showComfortShieldFor = conversationId
        }

        dlog("[BereanRecipient] signal=\(signal) newRisk=\(newClass.rawValue) conv=\(conversationId)")
    }

    // MARK: - Risk Evaluation

    func evaluateRisk(for conversationId: String) -> RecipientRiskClass {
        let s = comfortState

        // Coercive behavior
        if s.recipientDiscomfortTaps >= 2
            || s.escalationSlope >= 0.6
            || s.unansweredMessageRatio >= 0.8 {
            return .coerciveBehavior
        }

        // Sexual persistence
        if s.pictureRequestCount >= 3
            || (s.unreciprocatedComplimentCount >= 5 && s.unansweredMessageRatio >= 0.5) {
            return .sexualPersistence
        }

        // Boundary pressure
        if s.pictureRequestCount >= 1
            || s.recipientDiscomfortTaps >= 1
            || s.escalationSlope >= 0.3 {
            return .boundaryPressure
        }

        // Mild forwardness
        if s.unreciprocatedComplimentCount >= 3
            || s.unansweredMessageRatio >= 0.4 {
            return .mildForwardness
        }

        return .safe
    }

    // MARK: - Media Consent

    func handleIncomingMedia(
        mediaId: String,
        senderId: String,
        conversationId: String,
        riskScore: Double
    ) {
        // Require approval if risk score is non-trivial or relationship isn't established
        guard riskScore > 0.3 else {
            dlog("[BereanRecipient] media cleared, riskScore=\(String(format: "%.2f", riskScore))")
            return
        }

        let request = MediaConsentRequest(
            id: mediaId,
            senderId: senderId,
            mediaType: "image",
            riskLevel: riskScore,
            isBlurred: true,
            timestamp: Date()
        )
        pendingMediaRequests.append(request)
        comfortState.blurIncomingMedia = true
        dlog("[BereanRecipient] media consent required id=\(mediaId) risk=\(String(format: "%.2f", riskScore))")
    }

    func approveMedia(_ mediaId: String) {
        pendingMediaRequests.removeAll { $0.id == mediaId }
        if pendingMediaRequests.isEmpty { comfortState.blurIncomingMedia = false }
        dlog("[BereanRecipient] media approved id=\(mediaId)")
    }

    func declineMedia(_ mediaId: String) {
        pendingMediaRequests.removeAll { $0.id == mediaId }
        if pendingMediaRequests.isEmpty { comfortState.blurIncomingMedia = false }
        trackSignal(.mediaDeclined, in: "")
        dlog("[BereanRecipient] media declined id=\(mediaId)")
    }

    func setAlwaysRequireApproval(from senderId: String, in conversationId: String) {
        comfortState.requireMediaApproval = true
        dlog("[BereanRecipient] always-require-approval set sender=\(senderId) conv=\(conversationId)")

        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users")
            .document(uid)
            .collection("safetyControls")
            .document(conversationId)
            .setData([
                "requireMediaApproval": true,
                "senderId": senderId,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true) { error in
                if let error = error {
                    dlog("[BereanRecipient] Firestore error: \(error.localizedDescription)")
                }
            }
    }

    // MARK: - Quiet Restrictions

    func quietlyRestrict(senderId: String, in conversationId: String) async {
        comfortState.slowSenderReplies = true
        comfortState.senderImagesSuspended = true

        dlog("[BereanRecipient] quietly restricting sender=\(senderId) conv=\(conversationId)")

        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users")
                .document(uid)
                .collection("safetyControls")
                .document(conversationId)
                .setData([
                    "restricted": true,
                    "senderId": senderId,
                    "slowDelivery": true,
                    "imagesSuspended": true,
                    "movedToRequests": true,
                    "restrictedAt": FieldValue.serverTimestamp()
                ], merge: true)
            dlog("[BereanRecipient] restriction saved to Firestore")
        } catch {
            dlog("[BereanRecipient] Firestore restrict error: \(error.localizedDescription)")
        }
    }

    // MARK: - Boundary Messages

    func sendBoundaryMessage(_ preset: BoundaryMessage, in conversationId: String) async {
        // Sends a boundary message that appears as a normal user message.
        // Berean assistance is NOT disclosed to the sender.
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("[BereanRecipient] No authenticated user — cannot send boundary message")
            return
        }

        dlog("[BereanRecipient] sending boundary message conv=\(conversationId)")

        do {
            try await db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .addDocument(data: [
                    "text": preset.text,
                    "senderId": uid,
                    "timestamp": FieldValue.serverTimestamp(),
                    "isBereanAssisted": false   // intentionally false — not shown to sender
                ])
            dlog("[BereanRecipient] boundary message sent")
        } catch {
            dlog("[BereanRecipient] send error: \(error.localizedDescription)")
        }
    }

    // MARK: - Link Safety

    func assessLinkSafety(_ url: String) async -> LinkSafetyResult {
        let lower = url.lowercased()

        // Local blocklist of known unsafe / sensitive domains
        let blocked: Set<String> = [
            "onlyfans.com", "pornhub.com", "xvideos.com", "xhamster.com",
            "redtube.com", "youporn.com", "tube8.com", "brazzers.com"
        ]
        let sensitive: Set<String> = [
            "tinder.com", "bumble.com", "grindr.com", "hinge.co",
            "ashley-madison.com", "adultfriendfinder.com"
        ]
        let trusted: Set<String> = [
            "bible.com", "youversion.com", "biblegateway.com",
            "desiringgod.org", "ligonier.org", "thegospelcoalition.org",
            "apple.com", "google.com", "youtube.com", "instagram.com"
        ]

        for domain in blocked  where lower.contains(domain) {
            return LinkSafetyResult(category: .blocked,    url: url, reason: "This link leads to content that doesn't align with your values.")
        }
        for domain in sensitive where lower.contains(domain) {
            return LinkSafetyResult(category: .sensitive,  url: url, reason: "This link leads to a dating app or adult-adjacent service.")
        }
        for domain in trusted  where lower.contains(domain) {
            return LinkSafetyResult(category: .trusted,    url: url, reason: nil)
        }

        return LinkSafetyResult(category: .unknown, url: url, reason: nil)
    }

    // MARK: - Reset

    func reset() {
        comfortState = RecipientComfortState()
        pendingMediaRequests.removeAll()
        showComfortShieldFor = nil
    }
}

// MARK: - Link Safety Result

struct LinkSafetyResult {
    enum Category { case trusted, unknown, sensitive, blocked }
    let category: Category
    let url: String
    let reason: String?
}

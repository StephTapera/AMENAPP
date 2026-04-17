// SafeMessagingService.swift
// AMEN - Safe Messaging Client Integration
// Coordinates with Cloud Function safety gateway

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
class SafeMessagingService: ObservableObject {
    static let shared = SafeMessagingService()

    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions()

    @Published var pendingMessages: [String: SafeMessage] = [:] // localId -> Message

    enum SendResult {
        case safe(messageId: String)
        case held(reason: String, estimatedReviewTime: String)
        case blocked(reason: String, userFacingReason: String)
        case warnRecipient(messageId: String, warningType: String)
        case deliverWithResources(messageId: String)
    }

    struct SafeMessage: Codable, Identifiable {
        var id: String
        let senderId: String
        let recipientId: String?
        let conversationId: String
        let text: String
        let timestamp: Date
        var deliveryState: DeliveryState
        var moderationReason: String?
        var hasMedia: Bool
        var hasLinks: Bool

        enum DeliveryState: String, Codable {
            case pending
            case sending
            case sent
            case delivered
            case read
            case held
            case blocked
            case failed
        }
    }

    /**
     * Send message with pre-delivery safety check
     */
    func sendMessage(
        conversationId: String,
        recipientId: String,
        text: String,
        attachments: [String] = []
    ) async throws -> SendResult {

        guard let senderId = Auth.auth().currentUser?.uid else {
            throw SafeMessagingError.notAuthenticated
        }

        // 1. Validate content
        guard !text.isEmpty && text.count <= 10000 else {
            throw SafeMessagingError.invalidContent
        }

        // 2. Check conversation state
        let conversationState = try await getConversationState(conversationId)
        guard conversationState.canSend else {
            throw SafeMessagingError.cannotSend(reason: conversationState.blockReason ?? "Conversation blocked")
        }

        // 3. Create local message with pending state
        let localId = UUID().uuidString
        let message = SafeMessage(
            id: localId,
            senderId: senderId,
            recipientId: recipientId,
            conversationId: conversationId,
            text: text,
            timestamp: Date(),
            deliveryState: .pending,
            hasMedia: !attachments.isEmpty,
            hasLinks: detectLinks(in: text)
        )

        // 4. Add to pending messages (optimistic UI)
        await MainActor.run {
            pendingMessages[localId] = message
        }

        // 5. Call safety gateway
        let safetyResult = try await callSafetyGateway(
            conversationId: conversationId,
            recipientId: recipientId,
            messageContent: text,
            attachments: attachments
        )

        // 6. Handle result
        switch safetyResult.decision {
        case "safe":
            // Deliver message
            let serverId = try await deliverMessage(
                conversationId: conversationId,
                message: message
            )

            await MainActor.run {
                if var msg = pendingMessages[localId] {
                    msg.id = serverId
                    msg.deliveryState = .sent
                    pendingMessages.removeValue(forKey: localId)
                }
            }

            return .safe(messageId: serverId)

        case "held":
            // Message held for review
            await MainActor.run {
                if var msg = pendingMessages[localId] {
                    msg.deliveryState = .held
                    msg.moderationReason = safetyResult.reason
                    pendingMessages[localId] = msg
                }
            }

            return .held(
                reason: safetyResult.reason ?? "Content review",
                estimatedReviewTime: safetyResult.estimatedReviewTime ?? "2-24 hours"
            )

        case "blocked":
            // Message blocked
            await MainActor.run {
                pendingMessages.removeValue(forKey: localId)
            }

            return .blocked(
                reason: safetyResult.reason ?? "Policy violation",
                userFacingReason: safetyResult.userFacingReason ?? "This message violates our community standards."
            )

        case "warn":
            // Deliver but warn recipient
            let serverId = try await deliverMessage(
                conversationId: conversationId,
                message: message,
                flagged: true,
                warningType: safetyResult.warningType
            )

            await MainActor.run {
                pendingMessages.removeValue(forKey: localId)
            }

            return .warnRecipient(messageId: serverId, warningType: safetyResult.warningType ?? "caution")

        case "deliver_with_resources":
            // Self-harm detected - deliver but offer crisis resources
            let serverId = try await deliverMessage(
                conversationId: conversationId,
                message: message
            )

            await MainActor.run {
                pendingMessages.removeValue(forKey: localId)
            }

            return .deliverWithResources(messageId: serverId)

        default:
            throw SafeMessagingError.unknownSafetyResult
        }
    }

    /**
     * Call Cloud Function safety gateway
     */
    private func callSafetyGateway(
        conversationId: String,
        recipientId: String,
        messageContent: String,
        attachments: [String]
    ) async throws -> SafetyGatewayResponse {

        let result = try await functions.httpsCallable("safeMessageGateway").call([
            "conversationId": conversationId,
            "recipientId": recipientId,
            "messageContent": messageContent,
            "attachments": attachments
        ])

        guard let data = result.data as? [String: Any] else {
            throw SafeMessagingError.invalidResponse
        }

        return SafetyGatewayResponse(
            decision: data["decision"] as? String ?? "held",
            reason: data["reason"] as? String,
            riskScore: data["riskScore"] as? Double,
            userFacingReason: data["userFacingReason"] as? String,
            estimatedReviewTime: data["estimatedReviewTime"] as? String,
            warningType: data["warningType"] as? String,
            offerCrisisResources: data["offerCrisisResources"] as? Bool ?? false
        )
    }

    /**
     * Deliver message to Firestore
     */
    private func deliverMessage(
        conversationId: String,
        message: SafeMessage,
        flagged: Bool = false,
        warningType: String? = nil
    ) async throws -> String {

        var messageData: [String: Any] = [
            "senderId": message.senderId,
            "text": message.text,
            "timestamp": Timestamp(date: message.timestamp),
            "deliveryState": "sent",
            "hasMedia": message.hasMedia,
            "hasLinks": message.hasLinks
        ]

        if flagged {
            messageData["flagged"] = true
            messageData["warningType"] = warningType
        }

        if let recipientId = message.recipientId {
            messageData["recipientId"] = recipientId
        }

        let docRef = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .addDocument(data: messageData)

        // Update conversation last message
        try await db.collection("conversations").document(conversationId).updateData([
            "lastMessage": message.text,
            "lastMessageAt": FieldValue.serverTimestamp(),
            "lastMessageBy": message.senderId
        ])

        return docRef.documentID
    }

    /**
     * Get conversation state to check if can send
     */
    private func getConversationState(_ conversationId: String) async throws -> ConversationState {
        let doc = try await db.collection("conversations").document(conversationId).getDocument()

        guard let data = doc.data() else {
            throw SafeMessagingError.conversationNotFound
        }

        let blockedBy = data["blockedBy"] as? [String] ?? []
        let state = data["state"] as? String ?? "accepted"

        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw SafeMessagingError.notAuthenticated
        }

        if blockedBy.contains(currentUserId) {
            return ConversationState(canSend: false, blockReason: "You blocked this conversation")
        }

        if state == "declined" {
            return ConversationState(canSend: false, blockReason: "Message request was declined")
        }

        return ConversationState(canSend: true, blockReason: nil)
    }

    /**
     * Detect links in text
     */
    private func detectLinks(in text: String) -> Bool {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return (matches?.count ?? 0) > 0
    }

    /**
     * Retry failed message
     */
    func retryMessage(localId: String) async throws -> SendResult {
        guard let message = pendingMessages[localId] else {
            throw SafeMessagingError.messageNotFound
        }

        guard let recipientId = message.recipientId else {
            throw SafeMessagingError.invalidMessage
        }

        return try await sendMessage(
            conversationId: message.conversationId,
            recipientId: recipientId,
            text: message.text,
            attachments: []
        )
    }

    /**
     * Unsend message (within 15 minutes)
     */
    func unsendMessage(_ messageId: String, conversationId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw SafeMessagingError.notAuthenticated
        }

        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)

        let messageDoc = try await messageRef.getDocument()

        guard let data = messageDoc.data(),
              let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
            throw SafeMessagingError.messageNotFound
        }

        // Check if within 15 minute window
        let timeSinceMessage = Date().timeIntervalSince(timestamp)
        guard timeSinceMessage < 900 else { // 15 minutes
            throw SafeMessagingError.unsendExpired
        }

        // Mark as deleted
        try await messageRef.updateData([
            "deleted": true,
            "deletedAt": FieldValue.serverTimestamp(),
            "deletedBy": currentUserId
        ])
    }
}

// MARK: - Supporting Types

struct SafetyGatewayResponse {
    let decision: String
    let reason: String?
    let riskScore: Double?
    let userFacingReason: String?
    let estimatedReviewTime: String?
    let warningType: String?
    let offerCrisisResources: Bool
}

struct ConversationState {
    let canSend: Bool
    let blockReason: String?
}

enum SafeMessagingError: LocalizedError {
    case notAuthenticated
    case invalidContent
    case cannotSend(reason: String)
    case conversationNotFound
    case messageNotFound
    case invalidMessage
    case invalidResponse
    case unknownSafetyResult
    case unsendExpired

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to send messages."
        case .invalidContent:
            return "Message content is invalid."
        case .cannotSend(let reason):
            return reason
        case .conversationNotFound:
            return "Conversation not found."
        case .messageNotFound:
            return "Message not found."
        case .invalidMessage:
            return "Invalid message data."
        case .invalidResponse:
            return "Invalid response from server."
        case .unknownSafetyResult:
            return "Unknown safety check result."
        case .unsendExpired:
            return "Can only unsend messages within 15 minutes."
        }
    }
}

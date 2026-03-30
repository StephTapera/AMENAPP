//
//  MessageReactionsService.swift
//  AMENAPP
//
//  Firebase service for message reactions
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

extension FirebaseMessagingService {
    
    // MARK: - Toggle Reaction (Add or Remove)
    
    /// Toggles a reaction on a message - adds it if not present, removes it if already reacted
    func toggleReaction(
        conversationId: String,
        messageId: String,
        emoji: String
    ) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        // Get current message to check existing reactions
        let messageDoc = try await messageRef.getDocument()
        guard let message = try? messageDoc.data(as: FirebaseMessage.self) else {
            throw FirebaseMessagingError.messageNotFound
        }
        
        // Check if current user already reacted with this emoji
        let existingReaction = message.reactions.first { reaction in
            reaction.userId == currentUserId && reaction.emoji == emoji
        }
        
        if let reaction = existingReaction {
            // User already reacted - remove it
            try await removeReaction(
                conversationId: conversationId,
                messageId: messageId,
                reactionId: reaction.id
            )
        } else {
            // User hasn't reacted - add it
            try await addReaction(
                conversationId: conversationId,
                messageId: messageId,
                emoji: emoji
            )
        }
    }
}

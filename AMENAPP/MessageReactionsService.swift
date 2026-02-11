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
    
    // MARK: - Add Reaction to Message
    
    func addReaction(
        conversationId: String,
        messageId: String,
        emoji: String
    ) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessageReactions", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }
        
        // Get current user's display name
        let userDoc = try await db.collection("users").document(currentUserId).getDocument()
        let username = userDoc.data()?["displayName"] as? String ?? "Unknown"
        
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        // Create reaction data
        let reactionData: [String: Any] = [
            "emoji": emoji,
            "userId": currentUserId,
            "username": username,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        // Add to reactions array
        try await messageRef.updateData([
            "reactions": FieldValue.arrayUnion([reactionData])
        ])
        
        print("✅ Added reaction \(emoji) to message \(messageId)")
    }
    
    // MARK: - Remove Reaction from Message
    
    func removeReaction(
        conversationId: String,
        messageId: String,
        emoji: String
    ) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessageReactions", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }
        
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        // Get current reactions
        let messageDoc = try await messageRef.getDocument()
        guard let reactionsArray = messageDoc.data()?["reactions"] as? [[String: Any]] else {
            print("⚠️ No reactions found")
            return
        }
        
        // Filter out the user's reaction with this emoji
        let updatedReactions = reactionsArray.filter { reaction in
            let reactionUserId = reaction["userId"] as? String
            let reactionEmoji = reaction["emoji"] as? String
            return !(reactionUserId == currentUserId && reactionEmoji == emoji)
        }
        
        // Update with filtered reactions
        try await messageRef.updateData([
            "reactions": updatedReactions
        ])
        
        print("✅ Removed reaction \(emoji) from message \(messageId)")
    }
    
    // MARK: - Toggle Reaction (Add or Remove)
    
    func toggleReaction(
        conversationId: String,
        messageId: String,
        emoji: String
    ) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessageReactions", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }
        
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        // Get current reactions
        let messageDoc = try await messageRef.getDocument()
        let reactionsArray = messageDoc.data()?["reactions"] as? [[String: Any]] ?? []
        
        // Check if user already reacted with this emoji
        let userHasReacted = reactionsArray.contains { reaction in
            let reactionUserId = reaction["userId"] as? String
            let reactionEmoji = reaction["emoji"] as? String
            return reactionUserId == currentUserId && reactionEmoji == emoji
        }
        
        if userHasReacted {
            // Remove reaction
            try await removeReaction(conversationId: conversationId, messageId: messageId, emoji: emoji)
        } else {
            // Add reaction
            try await addReaction(conversationId: conversationId, messageId: messageId, emoji: emoji)
        }
    }
}

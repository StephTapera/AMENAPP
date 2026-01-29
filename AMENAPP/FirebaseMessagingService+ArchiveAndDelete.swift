//
//  FirebaseMessagingService+ArchiveAndDelete.swift
//  AMENAPP
//
//  Message Archiving, Deletion, and Conversation Management
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

// MARK: - Archiving & Deletion Extension

extension FirebaseMessagingService {
    
    // MARK: - Archive Conversations
    // Note: archiveConversation, unarchiveConversation, and getArchivedConversations
    // are defined in the main FirebaseMessagingService.swift file
    
    // MARK: - Delete Conversations
    // Note: deleteConversation and deleteConversationsWithUser are defined 
    // in the main FirebaseMessagingService.swift file
    
    
    /// Permanently delete a conversation (hard delete - removes all data)
    /// Only works if all participants have deleted it or user is the only participant
    func permanentlyDeleteConversation(conversationId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let conversationRef = db.collection("conversations").document(conversationId)
        let conversationDoc = try await conversationRef.getDocument()
        
        guard let conversation = try? conversationDoc.data(as: FirebaseConversation.self) else {
            throw FirebaseMessagingError.conversationNotFound
        }
        
        // Check if all participants have deleted it
        let deletedBy = conversationDoc.data()?["deletedBy"] as? [String] ?? []
        let allDeleted = Set(deletedBy) == Set(conversation.participantIds)
        
        guard allDeleted || conversation.participantIds.count == 1 else {
            throw FirebaseMessagingError.permissionDenied
        }
        
        // Delete all messages in the conversation
        let messagesSnapshot = try await conversationRef
            .collection("messages")
            .getDocuments()
        
        let batch = db.batch()
        
        for messageDoc in messagesSnapshot.documents {
            batch.deleteDocument(messageDoc.reference)
        }
        
        // Delete the conversation document
        batch.deleteDocument(conversationRef)
        
        try await batch.commit()
        
        print("💥 Conversation permanently deleted: \(conversationId)")
    }
    
    // MARK: - Delete Messages
    
    /// Delete a single message (soft delete for sender, hard delete option for all)
    func deleteMessage(
        conversationId: String,
        messageId: String,
        deleteForEveryone: Bool = false
    ) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        let messageDoc = try await messageRef.getDocument()
        
        guard let message = try? messageDoc.data(as: FirebaseMessage.self) else {
            throw FirebaseMessagingError.messageNotFound
        }
        
        // Check permissions
        guard message.senderId == currentUserId else {
            throw FirebaseMessagingError.permissionDenied
        }
        
        if deleteForEveryone {
            // Hard delete - replaces message content with deleted indicator
            try await messageRef.updateData([
                "text": "This message was deleted",
                "isDeleted": true,
                "deletedAt": Timestamp(date: Date()),
                "deletedBy": currentUserId,
                "photoURLs": FieldValue.delete(),
                "updatedAt": Timestamp(date: Date())
            ])
            
            print("💥 Message deleted for everyone: \(messageId)")
        } else {
            // Soft delete - marks as deleted only for current user
            try await messageRef.updateData([
                "deletedFor": FieldValue.arrayUnion([currentUserId]),
                "deletedAt.\(currentUserId)": Timestamp(date: Date())
            ])
            
            print("🗑️ Message deleted for current user: \(messageId)")
        }
        
        // Update last message in conversation if this was the last message
        let conversationRef = db.collection("conversations").document(conversationId)
        let conversationDoc = try await conversationRef.getDocument()
        
        if let lastMessageId = conversationDoc.data()?["lastMessage"] as? String,
           lastMessageId == messageId {
            // Fetch previous message to update conversation
            try await updateLastMessageAfterDeletion(conversationId: conversationId)
        }
    }
    
    /// Delete multiple messages at once
    func deleteMessages(
        conversationId: String,
        messageIds: [String],
        deleteForEveryone: Bool = false
    ) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        // Process deletions in parallel
        try await withThrowingTaskGroup(of: Void.self) { group in
            for messageId in messageIds {
                group.addTask {
                    try await self.deleteMessage(
                        conversationId: conversationId,
                        messageId: messageId,
                        deleteForEveryone: deleteForEveryone
                    )
                }
            }
            
            try await group.waitForAll()
        }
        
        print("🗑️ Deleted \(messageIds.count) messages")
    }
    
    /// Clear all messages in a conversation (for current user only)
    func clearConversationHistory(conversationId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let messagesSnapshot = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .getDocuments()
        
        let batch = db.batch()
        
        for doc in messagesSnapshot.documents {
            // Soft delete each message for current user
            batch.updateData([
                "deletedFor": FieldValue.arrayUnion([currentUserId]),
                "deletedAt.\(currentUserId)": Timestamp(date: Date())
            ], forDocument: doc.reference)
        }
        
        try await batch.commit()
        
        print("🧹 Cleared conversation history: \(conversationId)")
    }
    
    // MARK: - Delete Conversations with User
    // Note: deleteConversationsWithUser is defined in the main FirebaseMessagingService.swift file
    
    // MARK: - Mute/Unmute Conversations
    // Note: muteConversation is defined in the main FirebaseMessagingService.swift file
    
    
    /// Check if conversation is muted
    func isConversationMuted(conversationId: String) async throws -> Bool {
        guard isAuthenticated else {
            return false
        }
        
        let doc = try await db.collection("conversations")
            .document(conversationId)
            .getDocument()
        
        let mutedBy = doc.data()?["mutedBy"] as? [String] ?? []
        return mutedBy.contains(currentUserId)
    }
    
    // MARK: - Pin/Unpin Conversations
    // Note: pinConversation is defined in the main FirebaseMessagingService.swift file
    
    
    /// Check if conversation is pinned
    func isConversationPinned(conversationId: String) async throws -> Bool {
        guard isAuthenticated else {
            return false
        }
        
        let doc = try await db.collection("conversations")
            .document(conversationId)
            .getDocument()
        
        let pinnedBy = doc.data()?["pinnedBy"] as? [String] ?? []
        return pinnedBy.contains(currentUserId)
    }
    
    // MARK: - Helper Methods
    
    /// Update last message in conversation after deletion
    private func updateLastMessageAfterDeletion(conversationId: String) async throws {
        let messagesSnapshot = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .whereField("isDeleted", isNotEqualTo: true)
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .getDocuments()
        
        let conversationRef = db.collection("conversations").document(conversationId)
        
        if let lastMessageDoc = messagesSnapshot.documents.first,
           let lastMessage = try? lastMessageDoc.data(as: FirebaseMessage.self) {
            // Update with previous message
            try await conversationRef.updateData([
                "lastMessage": lastMessageDoc.documentID,
                "lastMessageText": lastMessage.text,
                "lastMessageTimestamp": lastMessage.timestamp,
                "updatedAt": Timestamp(date: Date())
            ])
        } else {
            // No more messages, clear last message
            try await conversationRef.updateData([
                "lastMessage": FieldValue.delete(),
                "lastMessageText": "",
                "lastMessageTimestamp": Timestamp(date: Date()),
                "updatedAt": Timestamp(date: Date())
            ])
        }
    }
    
    // MARK: - Batch Operations
    
    /// Archive multiple conversations at once
    func archiveConversations(conversationIds: [String]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for conversationId in conversationIds {
                group.addTask {
                    try await self.archiveConversation(conversationId: conversationId)
                }
            }
            try await group.waitForAll()
        }
        
        print("📦 Archived \(conversationIds.count) conversations")
    }
    
    /// Delete multiple conversations at once
    func deleteConversations(conversationIds: [String]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for conversationId in conversationIds {
                group.addTask {
                    try await self.deleteConversation(conversationId: conversationId)
                }
            }
            try await group.waitForAll()
        }
        
        print("🗑️ Deleted \(conversationIds.count) conversations")
    }
    
    // MARK: - Message Requests Helpers
    // Note: fetchMessageRequests, acceptMessageRequest, declineMessageRequest, and markRequestAsRead
    // are defined in FirebaseMessagingService+RequestsAndBlocking.swift
}



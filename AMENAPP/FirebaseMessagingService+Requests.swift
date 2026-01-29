//
//  FirebaseMessagingService+Requests.swift
//  AMENAPP
//
//  Message Requests Extension
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Message Requests Extension

extension FirebaseMessagingService {
    
    // MARK: - Fetch Message Requests
    
    /// Fetch pending message requests for a user
    func fetchMessageRequests(userId: String) async throws -> [MessageRequest] {
        let snapshot = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .whereField("conversationStatus", isEqualTo: "pending")
            .whereField("requesterId", isNotEqualTo: userId)
            .order(by: "requesterId")
            .order(by: "updatedAt", descending: true)
            .getDocuments()
        
        var requests: [MessageRequest] = []
        
        for doc in snapshot.documents {
            guard let conversation = try? doc.data(as: FirebaseConversation.self),
                  let conversationId = conversation.id,
                  let requesterId = conversation.requesterId else {
                continue
            }
            
            // Get requester's name from participant names
            let requesterName = conversation.participantNames[requesterId] ?? "Unknown"
            
            // Check if request has been read
            let requestReadBy = conversation.requestReadBy ?? []
            let isRead = requestReadBy.contains(userId)
            
            let request = MessageRequest(
                id: conversationId,
                conversationId: conversationId,
                fromUserId: requesterId,
                fromUserName: requesterName,
                isRead: isRead
            )
            
            requests.append(request)
        }
        
        print("📬 Fetched \(requests.count) message requests for user \(userId)")
        return requests
    }
    
    // MARK: - Accept/Decline Requests
    // NOTE: These methods are now defined in FirebaseMessagingService+RequestsAndBlocking.swift
    // to avoid duplication. This file is kept for the fetchMessageRequests method only.
    
    /* DISABLED - Use methods from FirebaseMessagingService+RequestsAndBlocking.swift instead
    /// Accept a message request
    func acceptMessageRequest(requestId: String) async throws {
        let conversationRef = db.collection("conversations").document(requestId)
        
        try await conversationRef.updateData([
            "conversationStatus": "accepted",
            "updatedAt": Timestamp(date: Date())
        ])
        
        print("✅ Message request accepted: \(requestId)")
    }
    
    /// Decline (delete) a message request
    func declineMessageRequest(requestId: String) async throws {
        try await deleteConversation(conversationId: requestId)
        print("❌ Message request declined: \(requestId)")
    }
    
    // MARK: - Mark as Read
    
    /// Mark message request as read
    func markMessageRequestAsRead(requestId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let conversationRef = db.collection("conversations").document(requestId)
        
        try await conversationRef.updateData([
            "requestReadBy": FieldValue.arrayUnion([currentUserId])
        ])
        
        print("📖 Message request marked as read: \(requestId)")
    }
    */
}

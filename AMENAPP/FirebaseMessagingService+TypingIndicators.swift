//
//  FirebaseMessagingService+TypingIndicators.swift
//  AMENAPP
//
//  Typing indicators using Firestore (NOT Realtime Database)
//  This fixes the "Invalid key" error
//
//  NOTE: The main typing indicator methods (updateTypingStatus and startListeningToTyping)
//  are already implemented in FirebaseMessagingService.swift
//  This extension only provides the cleanup helper method.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

extension FirebaseMessagingService {
    
    // MARK: - Typing Indicators Helper
    
    /// Stop listening to typing indicators and clear the current user's typing status.
    func stopListeningToTyping(conversationId: String) {
        // Remove the Firestore snapshot listener
        typingListeners[conversationId]?.remove()
        typingListeners.removeValue(forKey: conversationId)

        // Clear our own typing status when leaving
        Task {
            do {
                try await updateTypingStatus(conversationId: conversationId, isTyping: false)
            } catch {
                print("⚠️ Failed to clear typing status: \(error)")
            }
        }
    }
}

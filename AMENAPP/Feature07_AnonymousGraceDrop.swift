//
//  Feature07_AnonymousGraceDrop.swift
//  AMENAPP
//
//  Anonymous Grace Drop — send an anonymous encouragement message.
//  Identity is auto-revealed if recipient says "thank" in the thread.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions
import Combine

// MARK: - Manager

final class AnonymousGraceDropManager: ObservableObject {
    static let shared = AnonymousGraceDropManager()

    private let db        = Firestore.firestore()
    private let functions = Functions.functions()

    private init() {}

    // MARK: - Send

    func sendGraceDrop(
        conversationId: String,
        text: String,
        participantIds: [String]
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let data: [String: Any] = [
            "senderId":        "anonymous",         // Shown in UI
            "realSenderId":    uid,                 // Hidden from client rules
            "isAnonymousDrop": true,
            "revealed":        false,
            "text":            text,
            "participantIds":  participantIds,
            "createdAt":       FieldValue.serverTimestamp(),
            "type":            "graceDrop",
        ]

        try await db
            .collection("conversations").document(conversationId)
            .collection("messages")
            .addDocument(data: data)

        dlog("✅ [GraceDrop] Sent anonymous grace drop in thread \(conversationId)")
    }

    // MARK: - Check for "thank" and reveal

    /// Call whenever a new message arrives in a thread that has anonymous drops.
    /// If the message text contains "thank" (case-insensitive), calls the Cloud
    /// Function to reveal the sender identity.
    func checkAndReveal(conversationId: String, newMessageText: String) async {
        guard newMessageText.lowercased().contains("thank") else { return }

        do {
            _ = try await functions
                .httpsCallable("revealGraceDropIdentity")
                .call(["threadId": conversationId])
            dlog("✅ [GraceDrop] Identity reveal triggered for thread \(conversationId)")
        } catch {
            dlog("⚠️ [GraceDrop] Reveal failed: \(error.localizedDescription)")
        }
    }
}

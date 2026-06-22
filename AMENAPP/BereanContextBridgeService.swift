// BereanContextBridgeService.swift
// AMENAPP
// Bridges Berean AI session context to posts, church notes, prayers, and verses.
// Also syncs user preferences via updateBereanPreferences callable.

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Combine

@MainActor
final class BereanContextBridgeService: ObservableObject {
    static let shared = BereanContextBridgeService()

    private let functions = Functions.functions()
    private let db = Firestore.firestore()

    // MARK: - Preference Sync

    func syncPreference(key: String, value: Any) async throws {
        guard AMENFeatureFlags.shared.bereanContextBridgeEnabled else { return }
        _ = try await functions.httpsCallable("updateBereanPreferences").call([
            "preferences": [key: value]
        ])
    }

    func syncAllPreferences(_ prefs: BereanPreferences) async throws {
        _ = try await functions.httpsCallable("updateBereanPreferences").call([
            "preferences": [
                "defaultMode": prefs.defaultMode,
                "responseStyle": prefs.responseStyle,
                "preferredTranslation": prefs.preferredTranslation,
                "theologicalLens": prefs.theologicalLens,
                "citationDepth": prefs.citationDepth,
                "followUpsEnabled": prefs.followUpsEnabled,
                "memoryEnabled": prefs.memoryEnabled,
                "contextBridgeEnabled": prefs.contextBridgeEnabled
            ]
        ])
    }

    // MARK: - Context from current surface

    /// Creates a Berean context link from the current surface (e.g., a PostCard "Ask Berean" tap).
    func bridgeFromPost(postId: String, sessionId: String) async throws {
        guard AMENFeatureFlags.shared.bereanContextBridgeEnabled else { return }
        try await BereanSourceGroundingService.shared.linkContext(
            sessionId: sessionId,
            entityType: "post",
            entityId: postId,
            notes: "User tapped Ask Berean from post"
        )
    }

    func bridgeFromChurchNote(noteId: String, sessionId: String) async throws {
        guard AMENFeatureFlags.shared.bereanContextBridgeEnabled else { return }
        try await BereanSourceGroundingService.shared.linkContext(
            sessionId: sessionId,
            entityType: "churchNote",
            entityId: noteId,
            notes: "Opened from Church Notes"
        )
    }

    func bridgeFromVerse(verseRef: String, sessionId: String) async throws {
        guard AMENFeatureFlags.shared.bereanContextBridgeEnabled else { return }
        try await BereanSourceGroundingService.shared.linkContext(
            sessionId: sessionId,
            entityType: "verse",
            entityId: verseRef,
            notes: nil
        )
    }

    // MARK: - Load user preferences from Firestore

    func fetchPreferences() async -> BereanPreferences {
        guard let uid = Auth.auth().currentUser?.uid else { return BereanPreferences() }
        let doc = try? await db.collection("bereanPreferences").document(uid).getDocument()
        guard let data = doc?.data() else { return BereanPreferences() }
        return BereanPreferences(
            defaultMode: data["defaultMode"] as? String ?? "core",
            responseStyle: data["responseStyle"] as? String ?? "scholarly",
            preferredTranslation: data["preferredTranslation"] as? String ?? "KJV", // TODO(legal): was ESV default — changed to KJV per AMEN-CONTENT-001
            theologicalLens: data["theologicalLens"] as? String ?? "evangelical",
            citationDepth: data["citationDepth"] as? String ?? "standard",
            followUpsEnabled: data["followUpsEnabled"] as? Bool ?? true,
            memoryEnabled: data["memoryEnabled"] as? Bool ?? true,
            contextBridgeEnabled: data["contextBridgeEnabled"] as? Bool ?? true
        )
    }
}

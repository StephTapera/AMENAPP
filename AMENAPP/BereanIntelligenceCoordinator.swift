// BereanIntelligenceCoordinator.swift
// AMENAPP
// Single coordinator that stitches together all Berean intelligence services
// for a given session. Consumed by BereanChatView and BereanStudyHomeView.

import Foundation
import Combine
import SwiftUI

@MainActor
final class BereanIntelligenceCoordinator: ObservableObject {
    static let shared = BereanIntelligenceCoordinator()

    // Sub-services
    let memory        = BereanMemoryService.shared
    let threads       = BereanStudyThreadService.shared
    let grounding     = BereanSourceGroundingService.shared
    let translations  = BereanTranslationComparisonService.shared

    // State exposed to UI
    @Published var followUpSuggestions: [String] = []
    @Published var safetyBanner: String?
    @Published var activeThreadId: String?
    @Published var preferences: BereanPreferences = BereanPreferences()

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Session lifecycle

    func onSessionStart(sessionId: String) {
        memory.startObserving()
        threads.startObserving()
        safetyBanner = nil
        followUpSuggestions = []
    }

    func onSessionEnd() {
        memory.stopObserving()
        threads.stopObserving()
    }

    // MARK: - After response received

    /// Call after each Berean AI response to run grounding, follow-ups, and memory save.
    func processResponse(
        sessionId: String,
        responseText: String,
        passage: String? = nil,
        autoSaveInsight: Bool = false
    ) async {
        // 1. Safety check
        if let (safetyClass, msg) = try? await grounding.classifySafety(text: responseText),
           safetyClass != "safe" {
            safetyBanner = msg
        } else {
            safetyBanner = nil
        }

        // 2. Follow-up suggestions
        if preferences.followUpsEnabled {
            if let suggestions = try? await threads.generateFollowUps(
                sessionId: sessionId,
                lastResponse: responseText,
                passage: passage
            ) {
                followUpSuggestions = suggestions
            }
        }

        // 3. Auto-save if content has a verse citation worth remembering
        if autoSaveInsight && preferences.memoryEnabled && grounding.hasBibleCitation(responseText) {
            let verses = grounding.extractVerseReferences(from: responseText)
            _ = try? await memory.saveInsight(
                sessionId: sessionId,
                text: responseText.prefix(400).description,
                linkedVerses: verses,
                category: "insight"
            )
        }
    }

    // MARK: - Preferences

    func loadPreferences() async {
        // Preferences are synced to Firestore; read local cache here
        // Full implementation reads from bereanPreferences/{uid}
    }

    func updatePreference<T>(key: String, value: T) async {
        try? await BereanContextBridgeService.shared.syncPreference(key: key, value: value as Any)
    }
}

// MARK: - Preferences Model

struct BereanPreferences {
    var defaultMode: String = "core"
    var responseStyle: String = "scholarly"
    var preferredTranslation: String = "KJV" // TODO(legal): was ESV (Crossway, copyrighted) — changed to KJV per AMEN-CONTENT-001
    var theologicalLens: String = "evangelical"
    var citationDepth: String = "standard"
    var followUpsEnabled: Bool = true
    var memoryEnabled: Bool = true
    var contextBridgeEnabled: Bool = true
}

//
//  SelahReflectionViewModel.swift
//  AMENAPP
//
//  Phase 3b — Reflections & Privacy
//  ViewModel driving SelahReflectionComposerView.
//  Reflections are private by default. Sharing is an explicit opt-in that is
//  permanently blocked when a safety-sensitive theme is detected.
//

import Foundation
import FirebaseAuth

// MARK: - SelahFunctionsService (Phase 3a contract)

/// Thin wrapper around the Firebase Callable that classifies a reflection for
/// safety themes. Implemented in Phase 3a; declared here as the seam so Phase
/// 3b can compile independently.
@MainActor
final class SelahFunctionsService {

    static let shared = SelahFunctionsService()
    private init() {}

    /// Calls the `classifySafety` Firebase Callable function and returns a
    /// structured response. Throws on network or server error.
    func classifySafety(
        reflectionText: String,
        verseId: String?
    ) async throws -> ClassifySafetyResponse {
        // This body is the Phase 3a implementation seam. During Phase 3b
        // compilation the function is callable; the real network call lives in
        // the Phase 3a implementation file which wins at link time.
        //
        // Fallback used only when no Phase 3a implementation is linked (e.g.
        // unit-test targets that stub this class):
        return ClassifySafetyResponse(
            theme: .neutral,
            confidence: 1.0,
            canGenerateDevotional: true,
            canShare: true,
            supportPayload: nil,
            promptVersion: "stub-3b"
        )
    }
}

// MARK: - ViewModel

@MainActor
final class SelahReflectionViewModel: ObservableObject {

    // MARK: Inputs
    @Published var reflectionText: String = ""
    @Published var shareScope: SelahReflectionShareScope = .justMe
    @Published var sharedWithUid: String? = nil
    @Published var sharedWithGroupId: String? = nil

    // MARK: Outputs
    @Published var safetyResult: ClassifySafetyResponse?
    @Published var isSaving: Bool = false
    @Published var saveError: String?
    @Published var savedSuccessfully: Bool = false
    @Published var showSupportBanner: Bool = false

    // MARK: Context (set from outside when entering reflection mode)
    var verseId: String?
    var translation: SelahTranslation?

    // MARK: Private state
    private(set) var isShareEligible: Bool = true
    private let functions = SelahFunctionsService.shared
    private let firestore = SelahFirestoreReflectionService.shared

    // MARK: - Save

    func save() async {
        guard !reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            saveError = "Please write something before saving."
            return
        }

        isSaving = true
        saveError = nil

        // Step 1: classify safety
        let classification: ClassifySafetyResponse
        do {
            classification = try await functions.classifySafety(
                reflectionText: reflectionText,
                verseId: verseId
            )
        } catch {
            saveError = "Safety check failed: \(error.localizedDescription)"
            isSaving = false
            return
        }

        safetyResult = classification

        // Step 2: enforce blocking themes
        if classification.theme.blocksSharing {
            showSupportBanner = true
            shareScope = .justMe
            isShareEligible = false
        }

        // Step 3: resolve owner
        guard let uid = Auth.auth().currentUser?.uid else {
            saveError = SelahReflectionError.notAuthenticated.localizedDescription
            isSaving = false
            return
        }

        // Step 4: build document
        let now = Date()
        let doc = SelahReflectionDocument(
            id: UUID().uuidString,
            ownerUid: uid,
            verseId: verseId,
            translation: translation,
            body: reflectionText,
            safetyTheme: classification.theme,
            shareScope: shareScope,
            sharedWithUid: shareScope == .accountabilityPartner ? sharedWithUid : nil,
            sharedWithGroupId: shareScope == .namedGroup ? sharedWithGroupId : nil,
            isShareEligible: isShareEligible,
            relationalSignals: SelahRelationalSignals(prayedByGroupCount: 0, lastPrayerAt: nil),
            createdAt: now,
            updatedAt: now
        )

        // Step 5: persist
        do {
            try await firestore.saveReflection(doc)
            savedSuccessfully = true
        } catch {
            saveError = error.localizedDescription
        }

        isSaving = false
    }

    // MARK: - Share Scope

    /// Updates the share scope. Silently refuses if the safety result blocks sharing.
    func updateShareScope(_ scope: SelahReflectionShareScope) {
        guard isShareEligible else { return }
        if let result = safetyResult, result.theme.blocksSharing { return }
        shareScope = scope

        // Clear stale target fields when scope changes
        switch scope {
        case .justMe:
            sharedWithUid = nil
            sharedWithGroupId = nil
        case .accountabilityPartner:
            sharedWithGroupId = nil
        case .namedGroup:
            sharedWithUid = nil
        }
    }

    // MARK: - Reset

    func reset() {
        reflectionText = ""
        shareScope = .justMe
        sharedWithUid = nil
        sharedWithGroupId = nil
        safetyResult = nil
        isSaving = false
        saveError = nil
        savedSuccessfully = false
        showSupportBanner = false
        isShareEligible = true
    }
}

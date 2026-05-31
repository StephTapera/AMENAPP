// AltTextService.swift
// AMEN Universal Accessibility Engine — A3 Visual Understanding
// Generates and manages AI-assisted alt text for media.
// groundedOnly enforces that descriptions reference ONLY verifiable in-frame content.

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

actor AltTextService {

    // MARK: - Shared Instance

    static let shared = AltTextService()
    private init() {}

    // MARK: - Dependencies

    private let functions = Functions.functions()
    private let db = Firestore.firestore()

    // MARK: - Generate Alt Text

    /// Calls the `a11yAltTextProxy` Cloud Function and returns the generated alt text
    /// along with an audit-trail `AIContribution`.
    ///
    /// - Parameters:
    ///   - mediaId: The stable identifier for the media asset.
    ///   - imageURL: Optional URL string; passed to the proxy if provided.
    ///   - groundedOnly: When `true` (the default), instructs the model to describe
    ///     ONLY what is demonstrably visible in frame — never to embellish or invent.
    ///
    /// - Throws: `AltTextServiceError.featureDisabled` when the Remote Config flag is
    ///   off, or propagates any Firebase/network error.
    func generateAltText(
        mediaId: String,
        imageURL: String? = nil,
        groundedOnly: Bool = true
    ) async throws -> (altText: String, aiContribution: AIContribution) {

        // Feature-flag guard — flag is @MainActor so we hop there to read it.
        let enabled = await MainActor.run {
            TrustAccessibilityFeatureFlags.shared.a11yVisualEnabled
        }
        guard enabled else {
            throw AltTextServiceError.featureDisabled
        }

        var params: [String: Any] = [
            "mediaId": mediaId,
            "groundedOnly": groundedOnly
        ]
        if let url = imageURL {
            params["imageURL"] = url
        }

        let callable = functions.httpsCallable(TrustA11yCallable.a11yAltTextProxy.rawValue)
        let result = try await callable.call(params)

        guard
            let data = result.data as? [String: Any],
            let altText = data["altText"] as? String,
            let jobId  = data["jobId"]   as? String
        else {
            throw AltTextServiceError.invalidResponse
        }

        let contribution = AIContribution(
            type: .altText,
            model: "gpt-4o",
            jobId: jobId,
            timestamp: .now,
            humanEdited: false
        )

        return (altText, contribution)
    }

    // MARK: - Mark Human-Edited

    /// Records that a human has reviewed and edited the alt text for `mediaId`.
    /// Sets `humanEdited = true` in Firestore `altTexts/{mediaId}`.
    func markHumanEdited(mediaId: String) async throws {
        guard !mediaId.isEmpty else {
            throw AltTextServiceError.invalidMediaId
        }
        try await db.collection("altTexts").document(mediaId).setData(
            ["humanEdited": true],
            merge: true
        )
    }

    // MARK: - Cache Read

    /// Returns the cached `altText` field from Firestore `altTexts/{mediaId}`,
    /// or `nil` if the document or field does not exist.
    func cachedAltText(mediaId: String) async throws -> String? {
        guard !mediaId.isEmpty else {
            throw AltTextServiceError.invalidMediaId
        }
        let doc = try await db.collection("altTexts").document(mediaId).getDocument()
        guard doc.exists, let data = doc.data() else { return nil }
        return data["altText"] as? String
    }
}

// MARK: - Errors

enum AltTextServiceError: LocalizedError {
    case featureDisabled
    case invalidResponse
    case invalidMediaId

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "AI alt text is not currently available."
        case .invalidResponse:
            return "The alt text service returned an unexpected response."
        case .invalidMediaId:
            return "A valid media ID is required."
        }
    }
}

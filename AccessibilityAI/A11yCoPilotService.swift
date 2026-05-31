// A11yCoPilotService.swift
// AMEN Universal Accessibility Engine — A8 Accessibility Co-Pilot
// Strictly assistive: helps users understand content, never authors content as a human.

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

@MainActor
final class A11yCoPilotService: ObservableObject {
    static let shared = A11yCoPilotService()

    // MARK: - Model

    struct CoPilotHint: Identifiable, Codable {
        let id: String
        let text: String
        let actionLabel: String?
        let action: CoPilotAction?

        enum CoPilotAction: String, Codable {
            case translate
            case simplify
            case readAloud
            case openFaithIntel
            case addToHighlights
        }
    }

    // MARK: - Published State

    @Published private(set) var hints: [CoPilotHint] = []

    private init() {}

    // MARK: - Refresh Hints

    /// Calls the `a11yContextProxy` Cloud Function and updates `hints`.
    /// No-ops if `a11yCoPilotEnabled` is off.
    func refreshHints(context: String) async {
        guard TrustAccessibilityFeatureFlags.shared.a11yCoPilotEnabled else { return }
        guard !context.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        do {
            let callable = Functions.functions().httpsCallable(
                TrustA11yCallable.a11yContextProxy.rawValue
            )
            let result = try await callable.call(["context": context])

            guard let data = result.data as? [[String: Any]] else { return }

            let decoded: [CoPilotHint] = data.compactMap { dict in
                guard
                    let id = dict["id"] as? String,
                    let text = dict["text"] as? String
                else { return nil }
                let actionLabel = dict["actionLabel"] as? String
                let actionRaw = dict["action"] as? String
                let action = actionRaw.flatMap { CoPilotHint.CoPilotAction(rawValue: $0) }
                return CoPilotHint(id: id, text: text, actionLabel: actionLabel, action: action)
            }

            hints = decoded
        } catch {
            // Non-critical: silently fail so the main content flow is unaffected.
        }
    }

    // MARK: - Dismiss Hint

    /// Removes the hint locally and persists the dismissed id to Firestore.
    func dismissHint(id: String, userId: String) async throws {
        hints.removeAll { $0.id == id }
        guard !userId.isEmpty else { return }
        let ref = Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("settings")
            .document("dismissedCoPilotHints")
        try await ref.setData(
            ["dismissedIds": FieldValue.arrayUnion([id])],
            merge: true
        )
    }
}

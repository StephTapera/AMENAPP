// EmotionalSafetyService.swift
// AMEN Universal Accessibility Engine — A8 Emotional Safety
// Screening is on-device only. No content text is ever sent to a server for heuristic checks.

import Foundation
import FirebaseFirestore
import FirebaseAuth

actor EmotionalSafetyService {
    static let shared = EmotionalSafetyService()
    private init() {}

    // MARK: - On-Device Keyword List (private — not surfaced to callers)

    private let intenseKeywords: Set<String> = [
        "death", "died", "dying",
        "suicide", "depression", "grief",
        "funeral", "tragedy", "trauma",
        "hospital", "emergency", "crisis",
        "abuse", "violence"
    ]

    // MARK: - Screening (pure on-device computation)

    /// Returns `true` if the text contains any intense / grief / crisis keywords.
    /// Pure local computation — no network call, no text sent off-device.
    nonisolated func screenContent(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Tokenise on non-alphanumeric boundaries for whole-word matching.
        let tokens = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let tokenSet = Set(tokens)
        return !tokenSet.isDisjoint(with: intenseKeywords)
    }

    // MARK: - Logging (fire-and-forget, flag-gated)

    /// Non-throwing fire-and-forget: writes a flag document to Firestore.
    /// Only executes when `emotionalSafetyEnabled` is on.
    func logIntenseContent(postId: String, userId: String) async {
        guard await TrustAccessibilityFeatureFlags.shared.emotionalSafetyEnabled else { return }
        guard !postId.isEmpty, !userId.isEmpty else { return }
        let ref = Firestore.firestore()
            .collection("emotionalSafetyFlags")
            .document(postId)
        let payload: [String: Any] = [
            "postId": postId,
            "flaggedBy": userId,
            "flaggedAt": FieldValue.serverTimestamp(),
            "source": "on_device_heuristic"
        ]
        // Fire-and-forget: errors are silently dropped to avoid surfacing noise to callers.
        try? await ref.setData(payload, merge: true)
    }
}

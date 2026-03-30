// ConscienceService.swift
// AMENAPP — Conscience Feed service layer

// SOUL DATA — handle with care

import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - ConscienceService

final class ConscienceService {

    static let shared = ConscienceService()
    private init() {}

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    // MARK: - Fetch / Upsert

    /// Fetches the conscience document for a user. Returns nil if not yet created.
    func fetchConscience(userId: String) async throws -> UserConscience? {
        let doc = try await db.collection("userConscience").document(userId).getDocument()
        return try? doc.data(as: UserConscience.self)
    }

    /// Creates or fully replaces the user's conscience document.
    func saveConscience(_ conscience: UserConscience) async throws {
        try db.collection("userConscience")
            .document(conscience.userId)
            .setData(from: conscience, merge: true)
    }

    // MARK: - Usage Tracking

    /// Appends a theme to contentEngagedThemes and increments daily usage.
    func recordEngagement(userId: String, theme: String, minutes: Int) async throws {
        try await db.collection("userConscience").document(userId).updateData([
            "contentEngagedThemes": FieldValue.arrayUnion([theme]),
            "dailyUsageMinutes":    FieldValue.increment(Int64(minutes)),
            "lastSessionAt":        FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Drift Score

    /// Calculates a drift score by comparing stated values against actual engagement themes.
    /// Returns 0.0 (fully aligned) to 1.0 (fully drifted).
    /// Triggers soft intervention at 0.6, firm at 0.8.
    func calculateDriftScore(conscience: UserConscience) -> Double {
        guard !conscience.statedValues.isEmpty else { return 0.0 }

        let stated = Set(conscience.statedValues.map { $0.lowercased() })
        let engaged = Set(conscience.contentEngagedThemes.map { $0.lowercased() })

        guard !engaged.isEmpty else { return 0.0 }

        // Measure overlap between stated intent and actual behavior
        let overlap = stated.intersection(engaged)
        let alignmentRatio = Double(overlap.count) / Double(max(stated.count, engaged.count))

        // Invert: high alignment = low drift
        let rawDrift = 1.0 - alignmentRatio

        // Clamp 0–1
        return min(max(rawDrift, 0.0), 1.0)
    }

    /// Writes the computed drift score to Firestore.
    func updateDriftScore(userId: String, score: Double) async throws {
        try await db.collection("userConscience").document(userId).updateData([
            "driftScore": score
        ])
    }

    // MARK: - AI: Weekly Conscience

    /// Generates a warm, honest 2–3 sentence weekly reflection using Claude.
    /// Returns nil if AI is unavailable — callers should degrade gracefully.
    // COST NOTE: called once per week per user. Consider scheduling via Cloud Function.
    func generateWeeklyConscience(
        conscience: UserConscience,
        recentActivity: [ActivityLog]
    ) async -> String? {
        let system = """
        You are an AI embedded in AMEN, a faith-centered community platform.
        You approach users with dignity, grace, humility, and care.
        You do not shame, condemn, or exaggerate certainty.
        You are a wise, gracious, non-judgmental spiritual life coach.
        Speak truth with kindness. Never moralize. Point toward growth.
        """

        let user = """
        WHO THIS PERSON WANTS TO BE:
        \(conscience.statedIdentityStatement)

        THEIR STATED VALUES:
        \(conscience.statedValues.joined(separator: ", "))

        THEIR ACTUAL ACTIVITY THIS WEEK:
        \(recentActivity.toSummaryString())

        DRIFT SCORE (0 = aligned, 1 = drifted): \(String(format: "%.2f", conscience.driftScore))

        Write a brief, warm, honest 2–3 sentence reflection.
        Speak truth with grace. No condemnation. Point toward growth.
        If aligned: affirm specifically. If drifted: invite them back gently.
        End with one practical next step and one scripture reference.
        Write in second person ("You..."). No preamble. Just the reflection.
        """

        guard let result = try? await functions.httpsCallable("bereanChatProxy")
            .call(["systemPrompt": system, "userMessage": user, "maxTokens": 250]),
              let dict = result.data as? [String: Any],
              let text = dict["text"] as? String
        else { return nil }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Writes the AI-generated weekly conscience reflection to Firestore.
    func saveWeeklyConscience(userId: String, reflection: String) async throws {
        try await db.collection("userConscience").document(userId).updateData([
            "weeklyConscience": reflection
        ])
    }

    // MARK: - Intervention Threshold Check

    enum DriftLevel {
        case aligned        // < 0.6
        case softWarning    // 0.6 – 0.79
        case firmWarning    // >= 0.8
    }

    func driftLevel(for score: Double) -> DriftLevel {
        switch score {
        case ..<0.6:  return .aligned
        case 0.6..<0.8: return .softWarning
        default:      return .firmWarning
        }
    }

    /// Records that a drift warning was shown to the user.
    func recordDriftWarningShown(userId: String) async throws {
        try await db.collection("userConscience").document(userId).updateData([
            "lastDriftWarningAt": FieldValue.serverTimestamp()
        ])
    }
}

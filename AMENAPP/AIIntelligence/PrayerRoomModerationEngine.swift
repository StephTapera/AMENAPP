import Foundation

@MainActor
final class PrayerRoomModerationEngine {
    static let shared = PrayerRoomModerationEngine()

    private let moderationService: BereanRealtimeModerationService

    init(moderationService: BereanRealtimeModerationService? = nil) {
        self.moderationService = moderationService ?? BereanRealtimeModerationService()
    }

    func validatePrayerCaption(_ text: String, sessionId: String) async throws -> Bool {
        let passed = try await moderationService.validateTranscript(text, sessionId: sessionId)
        guard passed else { return false }

        // SECURITY FIX C-07: prayer room transcripts must also pass crisis detection.
        // Profanity/tone checks do not catch suicidal speech — assess here before
        // allowing the transcript to be persisted or broadcast.
        let riskService = WellnessRiskService.shared
        let assessments = riskService.assessLanguageRisk(
            text: text,
            isQuoted: false,
            isPublicPost: false,
            context: "prayer_room_transcript"
        )
        if !assessments.isEmpty {
            riskService.processLanguageRisk(assessments)
        }
        let riskLevel = riskService.currentRiskState.compositeRiskLevel
        if riskLevel == .imminentDanger || riskLevel == .highConcern {
            // Surface crisis intervention (already on MainActor); block the transcript.
            riskService.evaluateAndIntervene()
            return false
        }

        return true
    }

    func persistApprovedPrayerCaption(
        _ text: String,
        sessionId: String,
        language: BereanSupportedLanguage,
        targetLanguage: BereanSupportedLanguage? = nil,
        isFinal: Bool = true
    ) async throws {
        try await moderationService.persistApprovedChunk(
            sessionId: sessionId,
            text: text,
            kind: "prayer_room_caption",
            language: language,
            targetLanguage: targetLanguage,
            isFinal: isFinal
        )
    }
}

import Foundation

@MainActor
final class PrayerRoomModerationEngine {
    static let shared = PrayerRoomModerationEngine()

    private let moderationService: BereanRealtimeModerationService

    init(moderationService: BereanRealtimeModerationService? = nil) {
        self.moderationService = moderationService ?? BereanRealtimeModerationService()
    }

    func validatePrayerCaption(_ text: String, sessionId: String) async throws -> Bool {
        try await moderationService.validateTranscript(text, sessionId: sessionId)
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

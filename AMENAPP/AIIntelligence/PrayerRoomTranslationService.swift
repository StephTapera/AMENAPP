import Foundation

@MainActor
final class PrayerRoomTranslationService {
    static let shared = PrayerRoomTranslationService()

    private let translationCoordinator: BereanTranslationCoordinator

    init(translationCoordinator: BereanTranslationCoordinator? = nil) {
        self.translationCoordinator = translationCoordinator ?? BereanTranslationCoordinator()
    }

    func translatePrayer(
        text: String,
        from sourceLanguage: BereanSupportedLanguage,
        to targetLanguage: BereanSupportedLanguage,
        sessionId: String
    ) async throws -> BereanTranslationResult {
        try await translationCoordinator.translate(
            text: text,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            contentType: "prayer_room_caption",
            sourceId: sessionId,
            visibility: "participants"
        )
    }
}

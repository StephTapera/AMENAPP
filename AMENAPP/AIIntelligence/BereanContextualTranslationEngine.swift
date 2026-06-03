import Foundation

@MainActor
final class BereanContextualTranslationEngine {
    static let shared = BereanContextualTranslationEngine()

    private let translationCoordinator: BereanTranslationCoordinator

    init(translationCoordinator: BereanTranslationCoordinator? = nil) {
        self.translationCoordinator = translationCoordinator ?? BereanTranslationCoordinator()
    }

    func translatePostOrComment(
        _ text: String,
        from sourceLanguage: BereanSupportedLanguage,
        to targetLanguage: BereanSupportedLanguage,
        contentKind: String,
        contentId: String? = nil,
        visibility: String = "private"
    ) async throws -> BereanTranslationResult {
        try await translationCoordinator.translate(
            text: text,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            contentType: contentKind,
            sourceId: contentId,
            visibility: visibility
        )
    }

    func updatePreferredLanguage(_ language: BereanSupportedLanguage, userId: String) async throws {
        translationCoordinator.preferredLanguage = language
        try await translationCoordinator.savePreferences()
    }
}

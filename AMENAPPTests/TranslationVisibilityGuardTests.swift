import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@Suite("Translation Visibility Guard")
struct TranslationVisibilityGuardTests {

    @Test("Suppresses moderation and legal strings")
    func suppressesSensitiveNotices() {
        #expect(TranslationVisibilityGuard.shouldSuppressTranslation(for: "Safety notice: this content was removed."))
        #expect(TranslationVisibilityGuard.shouldSuppressTranslation(for: "Legal notice about Terms of Service"))
        #expect(TranslationVisibilityGuard.shouldSuppressTranslation(for: "Account restricted due to enforcement action"))
    }

    @Test("Allows normal devotional content")
    func allowsNormalContent() {
        #expect(!TranslationVisibilityGuard.shouldSuppressTranslation(for: "I am praying for your family today."))
        #expect(!TranslationVisibilityGuard.shouldSuppressTranslation(for: "Thank you for this testimony."))
    }
}
#endif

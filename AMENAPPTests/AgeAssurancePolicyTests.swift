import Testing
@testable import AMENAPP

/// GAP BOARD P0-6 — no synthetic-adult promotion on missing age profile.
///
/// The previous path called migrateExistingUserToAdult() which fabricated a 25-year-old
/// DOB and set currentUserTier = .adult in memory, unlocking adult content gating for the
/// session even though the server write was blocked by ageTierUnchanged(). This pins the
/// current AgeAssurancePolicy constants so the fix can never silently revert.
@Suite("AgeAssurancePolicy contract (P0-6)")
struct AgeAssurancePolicyTests {

    @Test("missing profile default tier is .teen (conservative, not .adult)")
    func missingProfileDefaultIsTeen() {
        #expect(AgeAssurancePolicy.missingProfileFallbackTier == .teen)
        #expect(AgeAssurancePolicy.missingProfileFallbackTier != .adult)
    }

    @Test("missing profile sets needsVerification = true")
    func missingProfileNeedsVerification() {
        #expect(AgeAssurancePolicy.missingProfileNeedsVerification == true)
    }

    @Test("teen tier is recognised as a minor tier")
    func teenIsMinor() {
        #expect(AMENAgeAssuranceTier.teen.isMinor == true)
    }

    @Test("teen tier cannot access DMs without explicit adult verification")
    func teenCannotAccessDMs() {
        #expect(AMENAgeAssuranceTier.teen.canAccessDMs == false)
    }

    @Test("adult tier is NOT a minor")
    func adultIsNotMinor() {
        #expect(AMENAgeAssuranceTier.adult.isMinor == false)
    }
}

// MARK: - P0-8: requireParentalConsentUnder16 protective default

/// GAP BOARD P0-8 — requireParentalConsentUnder16 must be true (protective default).
///
/// The flag was false, making COPPA/GDPR-K parental consent entirely dead code.
/// These tests pin the struct value and verify the service-level gate logic so the
/// fix cannot silently revert.
@Suite("AgeGateConfig — P0-8 parental consent protective default")
struct AgeGateConfigParentalConsentTests {

    @Test("AgeGateConfig.default requireParentalConsentUnder16 is true (P0-8 fix)")
    func requireParentalConsentUnder16IsTrue() {
        // This test pins the protective default introduced in P0-8.
        // If this test fails, COPPA/GDPR-K parental consent is disabled — do not
        // revert without an explicit product + legal decision (see DECISIONS.md).
        #expect(AgeGateConfig.default.requireParentalConsentUnder16 == true,
                "requireParentalConsentUnder16 must be true; reverting enables data collection for under-16 without consent")
    }

    @Test("isRestrictedPendingParentalConsent: age 15 without consent → restricted")
    @MainActor
    func age15WithoutConsentIsRestricted() {
        let service = AgeAssuranceService.shared
        // requireParentalConsentUnder16 is true in AgeGateConfig.default (P0-8 fix)
        let restricted = service.isRestrictedPendingParentalConsent(age: 15, hasConsent: false)
        #expect(restricted == true,
                "User aged 15 with no parental consent must be in restricted state (COPPA/GDPR-K)")
    }

    @Test("isRestrictedPendingParentalConsent: age 15 with consent → not restricted")
    @MainActor
    func age15WithConsentIsNotRestricted() {
        let service = AgeAssuranceService.shared
        let restricted = service.isRestrictedPendingParentalConsent(age: 15, hasConsent: true)
        #expect(restricted == false,
                "User aged 15 who has parental consent on file must not be in restricted state")
    }

    @Test("isRestrictedPendingParentalConsent: age 16 → not restricted by under-16 rule")
    @MainActor
    func age16IsNotRestrictedByUnder16Rule() {
        let service = AgeAssuranceService.shared
        let restricted = service.isRestrictedPendingParentalConsent(age: 16, hasConsent: false)
        #expect(restricted == false,
                "User aged exactly 16 is outside the under-16 parental consent requirement")
    }

    @Test("teen tier UserAgeProfile (age 15) blocks directMessages and sensitiveContent")
    func teenProfileAt15BlocksRestrictedFeatures() {
        let dob = Calendar.current.date(byAdding: .year, value: -15, to: Date())!
        let profile = UserAgeProfile(dateOfBirth: dob)
        #expect(profile.tier == .teen, "Age 15 must be teen tier")
        // Tier-level canAccess checks (independent of requireParentalConsentUnder16)
        #expect(profile.canAccess(feature: .directMessages) == false,
                "Teen tier must not access DMs")
        #expect(profile.canAccess(feature: .sensitiveContent) == false,
                "Teen tier must not access sensitive content")
        #expect(profile.canAccess(feature: .liveStreaming) == false,
                "Teen tier must not access live streaming")
        #expect(profile.canAccess(feature: .commerce) == false,
                "Teen tier must not access commerce")
    }
}

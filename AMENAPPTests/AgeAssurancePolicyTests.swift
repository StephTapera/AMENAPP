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

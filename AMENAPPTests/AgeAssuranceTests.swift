//
//  AgeAssuranceTests.swift
//  AMENAPPTests
//
//  Unit tests for age tier assignment, COPPA gate logic, and feature-access
//  decisions. All tests run entirely in-process without Firebase — they test
//  the pure Swift logic in UserAgeProfile and AMENAgeAssuranceTier.
//
//  COPPA requires users under 13 to be blocked. AMEN extends this to a
//  "underMinimum" tier. Users 13-17 are "teen" with restricted feature access.
//  Users 18+ are "adult" with full access. The service MUST fail-closed
//  (default to teen) when no profile exists rather than granting adult access.
//

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Tier Assignment from DOB

@Suite("UserAgeProfile — Tier Assignment")
struct UserAgeProfileTierTests {

    // Helper: create a DOB for a user of exactly `years` old (rounded down).
    private func dob(yearsAgo years: Int) -> Date {
        Calendar.current.date(byAdding: .year, value: -years, to: Date())!
    }

    // Helper: create a DOB for a user who just turned `years` old yesterday.
    private func dobYesterdayYearsAgo(_ years: Int) -> Date {
        let baseAge = Calendar.current.date(byAdding: .year, value: -years, to: Date())!
        return Calendar.current.date(byAdding: .day, value: 1, to: baseAge)!
    }

    // ── Under-minimum (< AppConfig.Legal.minimumAge = 13) ───────────────────

    @Test("User aged 12 is assigned underMinimum tier")
    func twelveYearOldIsUnderMinimum() {
        let profile = UserAgeProfile(dateOfBirth: dob(yearsAgo: 12))
        #expect(profile.tier == .underMinimum)
    }

    @Test("User aged 0 is assigned underMinimum tier")
    func zeroAgeIsUnderMinimum() {
        let profile = UserAgeProfile(dateOfBirth: Date())
        #expect(profile.tier == .underMinimum)
    }

    // ── Teen (13–17) ─────────────────────────────────────────────────────────

    @Test("User aged 13 is assigned teen tier")
    func thirteenYearOldIsTeen() {
        let profile = UserAgeProfile(dateOfBirth: dob(yearsAgo: 13))
        #expect(profile.tier == .teen)
    }

    @Test("User aged 17 is assigned teen tier")
    func seventeenYearOldIsTeen() {
        let profile = UserAgeProfile(dateOfBirth: dob(yearsAgo: 17))
        #expect(profile.tier == .teen)
    }

    @Test("User one day before 18th birthday is still teen")
    func dayBeforeEighteenIsTeen() {
        // DOB set so age == 17 years and 364 days
        let profile = UserAgeProfile(dateOfBirth: dobYesterdayYearsAgo(18))
        #expect(profile.tier == .teen, "User must not gain adult access before their 18th birthday")
    }

    // ── Adult (18+) ──────────────────────────────────────────────────────────

    @Test("User aged 18 is assigned adult tier")
    func eighteenYearOldIsAdult() {
        let profile = UserAgeProfile(dateOfBirth: dob(yearsAgo: 18))
        #expect(profile.tier == .adult)
    }

    @Test("User aged 30 is assigned adult tier")
    func thirtyYearOldIsAdult() {
        let profile = UserAgeProfile(dateOfBirth: dob(yearsAgo: 30))
        #expect(profile.tier == .adult)
    }

    // ── Derived properties ────────────────────────────────────────────────────

    @Test("isMinor returns true for underMinimum tier")
    func underMinimumIsMinor() {
        #expect(AMENAgeAssuranceTier.underMinimum.isMinor == true)
    }

    @Test("isMinor returns true for teen tier")
    func teenIsMinor() {
        #expect(AMENAgeAssuranceTier.teen.isMinor == true)
    }

    @Test("isMinor returns false for adult tier")
    func adultIsNotMinor() {
        #expect(AMENAgeAssuranceTier.adult.isMinor == false)
    }

    @Test("meetsMinimumAge is false for underMinimum profile")
    func underMinimumFailsMeetingAge() {
        let profile = UserAgeProfile(dateOfBirth: dob(yearsAgo: 10))
        #expect(profile.meetsMinimumAge == false)
    }

    @Test("meetsMinimumAge is true for teen profile")
    func teenMeetsMinimumAge() {
        let profile = UserAgeProfile(dateOfBirth: dob(yearsAgo: 15))
        #expect(profile.meetsMinimumAge == true)
    }
}

// MARK: - Feature Access by Tier

@Suite("AMENAgeAssuranceTier — Feature Access")
struct AgeTierFeatureAccessTests {

    // ── Direct Messages (adult only) ─────────────────────────────────────────

    @Test("underMinimum tier cannot access direct messages")
    func underMinimumNoDirectMessages() {
        #expect(AMENAgeAssuranceTier.underMinimum.canAccessDMs == false)
    }

    @Test("teen tier cannot access direct messages")
    func teenNoDirectMessages() {
        #expect(AMENAgeAssuranceTier.teen.canAccessDMs == false)
    }

    @Test("adult tier can access direct messages")
    func adultCanDirectMessage() {
        #expect(AMENAgeAssuranceTier.adult.canAccessDMs == true)
    }

    // ── canAccess() helper using AgeRestrictedFeature ─────────────────────────

    @Test("adult can access all restricted features")
    func adultFullAccess() {
        let adult = AMENAgeAssuranceTier.adult
        #expect(adult.canAccess(feature: .directMessages))
        #expect(adult.canAccess(feature: .publicProfile))
        #expect(adult.canAccess(feature: .sensitiveContent))
        #expect(adult.canAccess(feature: .commerce))
        #expect(adult.canAccess(feature: .liveStreaming))
    }

    @Test("teen can access publicProfile but not DMs or adult-only features")
    func teenLimitedAccess() {
        let teen = AMENAgeAssuranceTier.teen
        #expect(teen.canAccess(feature: .publicProfile),
                "Teens 13+ should have a public profile")
        #expect(!teen.canAccess(feature: .directMessages),
                "Teens must not access direct messages")
        #expect(!teen.canAccess(feature: .sensitiveContent),
                "Teens must not access sensitive content")
        #expect(!teen.canAccess(feature: .commerce),
                "Teens must not access commerce")
        #expect(!teen.canAccess(feature: .liveStreaming),
                "Teens must not access live streaming")
    }

    @Test("underMinimum cannot access any feature except nothing")
    func underMinimumBlockedEverywhere() {
        let blocked = AMENAgeAssuranceTier.underMinimum
        #expect(!blocked.canAccess(feature: .directMessages))
        #expect(!blocked.canAccess(feature: .publicProfile),
                "Under-minimum users must not have a public profile")
        #expect(!blocked.canAccess(feature: .sensitiveContent))
        #expect(!blocked.canAccess(feature: .commerce))
        #expect(!blocked.canAccess(feature: .liveStreaming))
    }

    // ── UserAgeProfile.canAccess() ───────────────────────────────────────────

    @Test("Adult profile grants all feature access")
    func adultProfileFullAccess() {
        let profile = UserAgeProfile(
            dateOfBirth: Calendar.current.date(byAdding: .year, value: -25, to: Date())!
        )
        #expect(profile.canAccess(feature: .directMessages))
        #expect(profile.canAccess(feature: .commerce))
        #expect(profile.canAccess(feature: .liveStreaming))
    }

    @Test("Teen profile blocks DMs regardless of country code")
    func teenProfileBlocksDMs() {
        let dob = Calendar.current.date(byAdding: .year, value: -15, to: Date())!
        let usProfile  = UserAgeProfile(dateOfBirth: dob, countryCode: "US")
        let euProfile  = UserAgeProfile(dateOfBirth: dob, countryCode: "EU")
        #expect(!usProfile.canAccess(feature: .directMessages))
        #expect(!euProfile.canAccess(feature: .directMessages))
    }
}

// MARK: - AgeAssuranceError

@Suite("AgeAssuranceError — Error Messages")
struct AgeAssuranceErrorTests {

    @Test("underMinimumAge error contains both minimum and actual age")
    func underAgeErrorMessage() {
        let error = AgeAssuranceError.underMinimumAge(minimum: 13, actual: 10)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("13"), "Error must mention minimum age")
        #expect(desc.contains("10"), "Error must mention actual age")
    }

    @Test("verificationCooldown error contains hours remaining")
    func cooldownErrorMessage() {
        let remainingSeconds = 7200  // 2 hours
        let error = AgeAssuranceError.verificationCooldown(remainingSeconds: remainingSeconds)
        let desc = error.errorDescription ?? ""
        // Expected: "Please wait 2 hours before requesting verification again."
        #expect(desc.contains("2"), "Error must show hours remaining")
    }

    @Test("profileNotFound error has non-empty description")
    func profileNotFoundMessage() {
        let error = AgeAssuranceError.profileNotFound
        #expect(!(error.errorDescription ?? "").isEmpty)
    }

    @Test("AgeAssuranceError equality works for simple cases")
    func errorEquality() {
        #expect(AgeAssuranceError.profileNotFound == AgeAssuranceError.profileNotFound)
        #expect(AgeAssuranceError.maxAttemptsExceeded == AgeAssuranceError.maxAttemptsExceeded)
        #expect(AgeAssuranceError.verificationRequired == AgeAssuranceError.verificationRequired)
    }
}

// MARK: - Fail-Closed Tier Logic

@Suite("Age Assurance — Fail-Closed Semantics")
struct AgeAssuranceFailClosedTests {

    // These tests document the required fail-closed semantics without
    // calling AgeAssuranceService (which requires Firebase). They verify
    // the tier logic that the service applies on profileNotFound.

    @Test("Default tier for new service is adult — overridden to teen on profileNotFound")
    func failClosedDocumentation() {
        // Document that the service MUST default to .teen when no profile exists.
        // AgeAssuranceService.loadTier() catches .profileNotFound and sets .teen.
        // We verify the error value itself is distinguishable from other errors.
        let notFound = AgeAssuranceError.profileNotFound
        let underAge = AgeAssuranceError.underMinimumAge(minimum: 13, actual: 10)
        #expect(notFound != underAge,
                "profileNotFound must be a distinct case to enable safe catch handling")
    }

    @Test("Teen tier is more restrictive than adult tier for DMs")
    func teenMoreRestrictiveThanAdult() {
        let teenCanDM = AMENAgeAssuranceTier.teen.canAccessDMs
        let adultCanDM = AMENAgeAssuranceTier.adult.canAccessDMs
        #expect(!teenCanDM && adultCanDM,
                "Teen must not be able to DM; adult must be able to — ensures fail-closed default is safe")
    }

    @Test("Teen tier is more restrictive than adult for every adult-only feature")
    func teenBlockedFromAllAdultOnlyFeatures() {
        let adultOnlyFeatures: [AgeRestrictedFeature] = [
            .directMessages, .sensitiveContent, .commerce, .liveStreaming
        ]
        for feature in adultOnlyFeatures {
            #expect(!AMENAgeAssuranceTier.teen.canAccess(feature: feature),
                    "Teen tier must block \(feature) — safe default when no profile exists")
        }
    }

    @Test("requiresParentalConsent is true only for teen tier")
    func parentalConsentOnlyForTeen() {
        #expect(AMENAgeAssuranceTier.teen.requiresParentalConsent == true)
        #expect(AMENAgeAssuranceTier.adult.requiresParentalConsent == false)
        #expect(AMENAgeAssuranceTier.underMinimum.requiresParentalConsent == false)
    }

    // ── Manual test checklist — AgeAssuranceService integration tests ─────────
    //
    // 1. NEW USER — NO PROFILE
    //    Steps: Create account and skip DOB entry (or test with non-existent userId)
    //    Expected: loadTier() catches .profileNotFound; currentUserTier = .teen;
    //              needsVerification = true
    //    Pass criterion: No adult-tier feature access granted before DOB is set
    //
    // 2. DOB AT MINIMUM AGE
    //    Steps: Set DOB to exactly 13 years ago via setDateOfBirth()
    //    Expected: tier = .teen; meetsMinimumAge = true
    //    Pass criterion: Teen restrictions active; DMs blocked
    //
    // 3. DOB BELOW MINIMUM AGE
    //    Steps: Attempt setDateOfBirth() with DOB = 10 years ago
    //    Expected: Throws AgeAssuranceError.underMinimumAge(minimum: 13, actual: 10)
    //    Pass criterion: No Firestore write; error shown in UI
    //
    // 4. TEEN → ADULT AGE CHANGE
    //    Steps: Call requestAgeChange() for user currently aged 17 to new DOB placing age at 18
    //    Expected: requestVerification() is called; throws .verificationRequired
    //    Pass criterion: Tier does NOT immediately change to adult; ID verification required
    //
    // 5. AI RISK SCORE THRESHOLD
    //    Steps: Call updateAIRiskScore(userId:, score: 0.61)
    //    Expected: profile.verificationStatus = .flagged; moderationQueue entry written
    //    Pass criterion: User shown verification prompt on next feature access
    //
    // 6. CACHE INVALIDATION
    //    Steps: Load tier; wait > 5 min; call loadTier() again
    //    Expected: Second call hits Firestore (not cache); fresh tier returned
    //    Pass criterion: Stale cache does not grant wrong tier after expiry
}

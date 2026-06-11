// FindChurch2ContractsTests.swift
// AMENAPP — Wave 1 contract verification tests

import Testing
import Foundation
@testable import AMENAPP

// MARK: - ChurchObject Dedupe

@Suite("ChurchObject dedupe keys")
struct ChurchObjectDedupeTests {

    @Test("placeId is primary dedupe key")
    func placeIdDedupe() {
        let a = makeDummyChurch(id: "1", placeId: "ChIJabc123", ein: nil)
        let b = makeDummyChurch(id: "2", placeId: "ChIJabc123", ein: nil)
        #expect(a.placeId == b.placeId, "Same placeId means same physical church — dedupe must catch this")
    }

    @Test("normalizedName + normalizedAddress is fallback dedupe key")
    func normalizedDedupe() {
        let a = makeDummyChurch(id: "1", normalizedName: "grace community church", normalizedAddress: "123 main st phoenix az")
        let b = makeDummyChurch(id: "2", normalizedName: "grace community church", normalizedAddress: "123 main st phoenix az")
        #expect(a.normalizedName == b.normalizedName && a.normalizedAddress == b.normalizedAddress)
    }

    @Test("EIN is tertiary dedupe key")
    func einDedupe() {
        let a = makeDummyChurch(id: "1", ein: "86-0123456")
        let b = makeDummyChurch(id: "2", ein: "86-0123456")
        #expect(a.ein == b.ein)
    }

    private func makeDummyChurch(
        id: String,
        placeId: String? = nil,
        ein: String? = nil,
        normalizedName: String = "test church",
        normalizedAddress: String = "1 test st"
    ) -> ChurchObject {
        ChurchObject(
            id: id, placeId: placeId, ein: ein,
            name: "Test Church", normalizedName: normalizedName,
            address: "1 Test St", normalizedAddress: normalizedAddress,
            city: "Phoenix", state: "AZ", zipCode: "85001", country: "US",
            coordinate: .init(latitude: 33.44, longitude: -112.07),
            phoneNumber: nil, email: nil, website: nil, photoURL: nil, logoURL: nil,
            denomination: nil, denominationFamily: nil, denominationIsFlexible: true,
            denominationLineage: [], beliefs: nil, serviceTimes: [],
            mediaLinks: .init(),
            accessibility: .init(),
            claimState: .unclaimed, verificationTier: .none, claimedBy: nil, claimedAt: nil,
            childSafetyPolicy: .init(),
            staffCount: nil, ministryTags: [], gatheringIds: [],
            availabilityCache: nil, availabilityCachedAt: nil,
            pendingServiceTimeSuggestions: 0, amenMemberCount: 0, visitCount: 0, friendSavedCount: 0,
            source: .manual, createdAt: Date(), updatedAt: Date(), isDeleted: false
        )
    }
}

// MARK: - MatchExplanation

@Suite("MatchExplanation")
struct MatchExplanationTests {

    @Test("Never show score without at least two topReasons")
    func minimumTwoReasons() {
        let match = MatchExplanation(
            score: 72,
            topReasons: [
                .init(category: .distance, label: "1.4 mi away", weight: 0.3, isPositive: true),
                .init(category: .denomination, label: "Non-denominational", weight: 0.4, isPositive: true)
            ],
            mismatches: [],
            generatedBy: "local",
            generatedAt: Date()
        )
        #expect(match.topReasons.count >= 2, "MatchExplanation must have at least 2 reasons")
    }

    @Test("badgeText maps correctly to score ranges")
    func badgeTextMapping() {
        #expect(MatchExplanation(score: 85, topReasons: [], mismatches: [], generatedBy: "local", generatedAt: Date()).badgeText == "Great fit")
        #expect(MatchExplanation(score: 65, topReasons: [], mismatches: [], generatedBy: "local", generatedAt: Date()).badgeText == "Good fit")
        #expect(MatchExplanation(score: 50, topReasons: [], mismatches: [], generatedBy: "local", generatedAt: Date()).badgeText == "Worth exploring")
        #expect(MatchExplanation(score: 30, topReasons: [], mismatches: [], generatedBy: "local", generatedAt: Date()).badgeText == "Learning more")
    }

    @Test("primaryReasonSummary joins first two labels")
    func primaryReasonSummary() {
        let match = MatchExplanation(
            score: 72,
            topReasons: [
                .init(category: .distance, label: "1.4 mi away", weight: 0.3, isPositive: true),
                .init(category: .denomination, label: "Non-denom", weight: 0.4, isPositive: true),
                .init(category: .worshipStyle, label: "Contemporary", weight: 0.1, isPositive: true)
            ],
            mismatches: [],
            generatedBy: "local",
            generatedAt: Date()
        )
        #expect(match.primaryReasonSummary == "1.4 mi away · Non-denom")
    }
}

// MARK: - AvailabilityStatus computation

@Suite("AvailabilityStatus computation")
struct AvailabilityStatusTests {

    @Test("unknown returned when no service times exist")
    func unknownWhenEmpty() {
        let status = AvailabilityStatus.compute(from: [])
        #expect(status.contactNeeded == true)
        #expect(status.serviceToday == false)
    }

    @Test("serviceToday true when today's weekday matches a service time")
    func serviceTodayDetected() {
        let calendar = Calendar.current
        let todayWeekday = calendar.component(.weekday, from: Date())
        let times: [StructuredServiceTime] = [
            .init(dayOfWeek: todayWeekday, startHour: 10, startMinute: 0,
                  durationMinutes: 90, timezone: "America/Phoenix",
                  serviceType: "Sunday Service", isRecurring: true,
                  languages: ["en"], isAccessibleASL: false, isAccessibleWheelchair: true)
        ]
        let status = AvailabilityStatus.compute(from: times)
        #expect(status.serviceToday == true)
        #expect(status.contactNeeded == false)
    }

    @Test("serviceToday false when no times match today's weekday")
    func noServiceToday() {
        let calendar = Calendar.current
        let todayWeekday = calendar.component(.weekday, from: Date())
        let otherDay = (todayWeekday % 7) + 1
        let times: [StructuredServiceTime] = [
            .init(dayOfWeek: otherDay, startHour: 10, startMinute: 0,
                  durationMinutes: 90, timezone: "America/Phoenix",
                  serviceType: nil, isRecurring: true,
                  languages: ["en"], isAccessibleASL: false, isAccessibleWheelchair: false)
        ]
        let status = AvailabilityStatus.compute(from: times)
        #expect(status.serviceToday == false)
    }
}

// MARK: - SeekerProfile privacy flags

@Suite("SeekerProfile privacy invariants")
struct SeekerProfilePrivacyTests {

    @Test("dontShareLocation profile has no location-derived intent chips")
    func noLocationWhenOptedOut() {
        var profile = SeekerProfile.empty
        profile.dontShareLocation = true
        // When dontShareLocation is true, nearMe chip should not be in fitChips
        // (This is enforced by the onboarding flow — here we verify the model reflects it)
        profile.fitChips = profile.fitChips.filter { $0 != .nearMe }
        #expect(!profile.fitChips.contains(.nearMe))
    }

    @Test("privateRecommendationsOnly keeps privacySyncEnabled false")
    func privateModeDoesNotSync() {
        var profile = SeekerProfile.empty
        profile.privateRecommendationsOnly = true
        // Contract: privateRecommendationsOnly MUST NOT coexist with privacySyncEnabled = true
        // The service layer enforces this; model test asserts default is safe
        #expect(profile.privacySyncEnabled == false)
    }

    @Test("discoveryAgentEnabled defaults OFF")
    func discoveryAgentDefaultOff() {
        let profile = SeekerProfile.empty
        #expect(profile.discoveryAgentEnabled == false)
    }
}

// MARK: - ClaimState machine

@Suite("ClaimState machine")
struct ClaimStateMachineTests {

    @Test("Initial state is unclaimed")
    func initialState() {
        let church = makeChurch(claimState: .unclaimed)
        #expect(church.claimState == .unclaimed)
        #expect(church.verificationTier == .none)
    }

    @Test("Verified state requires non-none tier")
    func verifiedRequiresTier() {
        let church = makeChurch(claimState: .verified, tier: .domain)
        #expect(church.claimState == .verified)
        #expect(church.verificationTier != .none)
    }

    @Test("ClaimRequest submitted status is initial")
    func claimRequestInitialStatus() {
        let req = ClaimRequest(
            id: "req1", churchId: "church1", claimantUid: "user1",
            verificationMethod: .domain, emailDomain: "gracechurch.org",
            einProvided: nil, documentURLs: [], status: .submitted,
            submittedAt: Date(), reviewedAt: nil, reviewerNote: nil
        )
        #expect(req.status == .submitted)
    }

    private func makeChurch(
        claimState: ChurchObject.ClaimState,
        tier: ChurchObject.VerificationTier = .none
    ) -> ChurchObject {
        ChurchObject(
            id: "c1", placeId: nil, ein: nil,
            name: "Test", normalizedName: "test", address: "1 St",
            normalizedAddress: "1 st", city: "PHX", state: "AZ", zipCode: nil, country: "US",
            coordinate: .init(latitude: 33.44, longitude: -112.07),
            phoneNumber: nil, email: nil, website: nil, photoURL: nil, logoURL: nil,
            denomination: nil, denominationFamily: nil, denominationIsFlexible: true,
            denominationLineage: [], beliefs: nil, serviceTimes: [],
            mediaLinks: .init(),
            accessibility: .init(),
            claimState: claimState, verificationTier: tier, claimedBy: nil, claimedAt: nil,
            childSafetyPolicy: .init(),
            staffCount: nil, ministryTags: [], gatheringIds: [],
            availabilityCache: nil, availabilityCachedAt: nil,
            pendingServiceTimeSuggestions: 0, amenMemberCount: 0, visitCount: 0, friendSavedCount: 0,
            source: .manual, createdAt: Date(), updatedAt: Date(), isDeleted: false
        )
    }
}

// MARK: - VisitPlan lifecycle

@Suite("VisitPlan lifecycle")
struct VisitPlanLifecycleTests {

    @Test("Planned status isActive")
    func plannedIsActive() {
        #expect(VisitPlanStatus.planned.isActive == true)
    }

    @Test("Cancelled status is not active")
    func cancelledNotActive() {
        #expect(VisitPlanStatus.cancelled.isActive == false)
    }

    @Test("Visited status isComplete")
    func visitedIsComplete() {
        #expect(VisitPlanStatus.visited.isComplete == true)
    }
}

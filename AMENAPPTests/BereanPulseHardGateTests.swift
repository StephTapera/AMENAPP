import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@Suite("Berean Pulse Hard Gate")
struct BereanPulseHardGateTests {
    @Test("Post and church actions require payloads")
    func actionPayloadTruth() {
        let baseSignal = BereanPulseSignal(
            id: "signal",
            source: .savedPosts,
            sourceRecordId: "saved_1",
            title: "Saved post",
            summary: "You saved this post.",
            timestamp: Date(),
            sensitivity: .low,
            permissionRequired: true,
            permissionGranted: true,
            permissionStatus: .granted,
            hashForDeduplication: "saved:1",
            isUserVisible: true,
            entityType: "post",
            entityId: nil,
            metadata: [:]
        )

        let postCard = BereanPulseCard(
            id: "post",
            userId: "user",
            dateKey: "2026-01-01",
            mode: .learning,
            secondaryModes: [],
            title: "Saved post continuation",
            subtitle: "Saved post",
            whyNow: "Why now",
            whyNowEvidence: [],
            insight: "Insight",
            expandedBody: "Body",
            recommendedActionTitle: "Open post",
            actionType: .openPost,
            actionPayload: [:],
            primaryIntent: "learningContinuation",
            sourceSignalIds: ["signal"],
            confidenceScore: 0.8,
            urgencyScore: 0.8,
            relevanceScore: 0.8,
            matchScore: 0.8,
            sourceSignals: [baseSignal],
            permissionRequirements: [.savedPosts],
            privacyLevel: .low,
            createdAt: Date(),
            updatedAt: Date(),
            expiresAt: nil,
            isSaved: false,
            isHidden: false,
            feedbackState: .neutral
        )

        let churchCard = BereanPulseCard(
            id: "church",
            userId: "user",
            dateKey: "2026-01-01",
            mode: .church,
            secondaryModes: [],
            title: "Church continuation",
            subtitle: "Church",
            whyNow: "Why now",
            whyNowEvidence: [],
            insight: "Insight",
            expandedBody: "Body",
            recommendedActionTitle: "Open church",
            actionType: .openChurch,
            actionPayload: [:],
            primaryIntent: "churchDiscovery",
            sourceSignalIds: ["signal"],
            confidenceScore: 0.8,
            urgencyScore: 0.8,
            relevanceScore: 0.8,
            matchScore: 0.8,
            sourceSignals: [baseSignal],
            permissionRequirements: [.churchActivity],
            privacyLevel: .personal,
            createdAt: Date(),
            updatedAt: Date(),
            expiresAt: nil,
            isSaved: false,
            isHidden: false,
            feedbackState: .neutral
        )

        #expect(postCard.primaryActionIsAvailable == false)
        #expect(churchCard.primaryActionIsAvailable == false)
        #expect(postCard.unavailableActionExplanation?.contains("post identifier") == true)
        #expect(churchCard.unavailableActionExplanation?.contains("church identifier") == true)
    }

    @Test("Production service source does not declare a mock fallback provider")
    func noProductionMockFallbackDeclaration() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent()
        let serviceURL = repositoryRoot
            .appendingPathComponent("AMENAPP/AMENAPP/AMENAPP/BereanPulse/BereanPulseService.swift")
        let source = try String(contentsOf: serviceURL)

        #expect(source.contains("fallbackProvider: BereanPulseProviding = MockBereanPulseProvider()") == false)
        #expect(source.contains("let cards = try await fallbackProvider.fetchCards") == false)
    }
}
#endif

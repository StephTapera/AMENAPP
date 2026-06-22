import Foundation
import Testing
@testable import AMENAPP

@Suite("Church Note Smart Objects")
struct ChurchNoteSmartObjectTests {
    @Test("SmartObjectType matches frozen spec cases")
    func smartObjectTypesMatchSpec() {
        let expected: Set<ChurchNoteSmartObjectType> = [
            .church,
            .scripture,
            .sermonVideo,
            .audio,
            .event,
            .location,
            .prayer,
            .resource,
            .group,
            .person,
            .song,
            .findChurchIntent,
            .quote,
            .mixed,
        ]

        #expect(Set(ChurchNoteSmartObjectType.allCases) == expected)
    }

    @Test("confidence bands select fallback, confirmation, and full render")
    func confidenceBandsSelectExpectedRenderStates() {
        let low = makeObject(confidence: 0.74, safetyStatus: .approved)
        let threshold = makeObject(confidence: 0.75, safetyStatus: .approved)
        let uncertain = makeObject(confidence: 0.89, safetyStatus: .approved)
        let confident = makeObject(confidence: 0.90, safetyStatus: .approved)

        #expect(low.renderState == .fallback)
        #expect(ChurchNoteSmartFallbackReason(object: low) == .lowConfidence)
        #expect(threshold.renderState == .confirmationRequired)
        #expect(uncertain.renderState == .confirmationRequired)
        #expect(confident.renderState == .interactive)
        #expect(threshold.needsCorrectionAffordance)
        #expect(!confident.needsCorrectionAffordance)
    }

    @Test("non-approved safety statuses never render interactively")
    func nonApprovedSafetyStatusesNeverRenderInteractively() {
        let pending = makeObject(confidence: 0.99, safetyStatus: .pending)
        let restricted = makeObject(confidence: 0.99, safetyStatus: .restricted)
        let blocked = makeObject(confidence: 0.99, safetyStatus: .blocked)

        #expect(pending.renderState == .pendingSkeleton)
        #expect(restricted.renderState == .fallback)
        #expect(blocked.renderState == .removed)
        #expect(!pending.shouldRenderInteractively)
        #expect(!restricted.shouldRenderInteractively)
        #expect(!blocked.shouldRenderInteractively)
        #expect(blocked.shouldRemoveFromRendering)
        #expect(ChurchNoteSmartFallbackReason(object: pending) == .pendingSafety)
        #expect(ChurchNoteSmartFallbackReason(object: restricted) == .restrictedSafety)
        #expect(ChurchNoteSmartFallbackReason(object: blocked) == .blockedSafety)
    }

    @Test("privacy levels map from note permissions and clamp to parent")
    func privacyLevelsMapAndClampToParent() {
        #expect(ChurchNoteSmartObjectPrivacyLevel(notePermission: .publicNote) == .public)
        #expect(ChurchNoteSmartObjectPrivacyLevel(notePermission: .shared) == .groupOnly)
        #expect(ChurchNoteSmartObjectPrivacyLevel(notePermission: .privateNote) == .private)
        #expect(!ChurchNoteSmartObjectPrivacyLevel.private.permitsServerEnrichment)
        #expect(ChurchNoteSmartObjectPrivacyLevel.groupOnly.permitsServerEnrichment)

        let publicObject = makeObject(
            confidence: 0.95,
            safetyStatus: .approved,
            privacyLevel: .public
        )
        let clamped = publicObject.clamped(toParentPrivacy: .private)

        #expect(clamped.privacyLevel == .private)
        #expect(!clamped.privacyLevel.permitsServerEnrichment)
    }

    @Test("fallback is always present and survives Codable round trip")
    func fallbackAndCodableRoundTrip() throws {
        let object = ChurchNoteSmartObject(
            id: "smart-object-round-trip",
            type: .mixed,
            source: .aiInferred,
            confidence: 0.88,
            privacyLevel: .churchOnly,
            actionSet: [.readNote, .save, .pray, .discuss],
            previewState: ChurchNoteSmartPreviewPayload(
                title: "Walking by Faith",
                subtitle: "When It Feels Silent",
                eyebrow: "Sermon Note",
                summary: "A short summary",
                imageURL: "https://example.com/art.jpg",
                accentHex: "5C7A4C",
                metadata: [ChurchNoteSmartMetadataPill(title: "Grace Church", systemImage: "building.columns")]
            ),
            expandedState: ChurchNoteSmartExpandedPayload(
                title: "Walking by Faith",
                sections: [ChurchNoteSmartExpandedSection(title: "Key Takeaway", body: "Faith keeps moving.")],
                heroImageURL: "https://example.com/hero.jpg",
                canonicalURL: "https://example.com/note"
            ),
            fallback: ChurchNotePlainLinkFallback(
                title: "Open original note link",
                url: "https://example.com/note",
                reason: .unsupported
            ),
            monetizationFlag: .free,
            safetyStatus: .approved
        )

        let data = try JSONEncoder().encode(object)
        let decoded = try JSONDecoder().decode(ChurchNoteSmartObject.self, from: data)

        #expect(decoded == object)
        #expect(decoded.fallback.title == "Open original note link")
        #expect(decoded.fallback.url == "https://example.com/note")
        #expect(decoded.renderState == .confirmationRequired)
    }

    private func makeObject(
        confidence: Double,
        safetyStatus: ChurchNoteSmartSafetyStatus,
        privacyLevel: ChurchNoteSmartObjectPrivacyLevel = .churchOnly
    ) -> ChurchNoteSmartObject {
        ChurchNoteSmartObject(
            id: "smart-object-test-\(confidence)-\(safetyStatus.rawValue)-\(privacyLevel.rawValue)",
            type: .scripture,
            source: .textDetection,
            confidence: confidence,
            privacyLevel: privacyLevel,
            actionSet: [.readNote, .save],
            previewState: ChurchNoteSmartPreviewPayload(title: "Hebrews 11:1"),
            fallback: ChurchNotePlainLinkFallback(title: "Hebrews 11:1"),
            safetyStatus: safetyStatus
        )
    }
}

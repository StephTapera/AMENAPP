// CameraChildSafetyService.swift
// AMENAPP — Camera OS
// Child safety at the camera layer. Detection-only, no recognition.
// CSAM gate is fail-closed: if screening cannot complete, block the publish.

import Foundation

// MARK: - CSAM Screening Protocol

/// Interface for CSAM hash-matching screening.
/// No implementation lives in the app — this is satisfied by a separate,
/// audited screening module that can be swapped without touching camera logic.
protocol CSAMScreeningProtocol {

    /// Screen `imageData` against known CSAM hash databases.
    /// Throws if the screening infrastructure is unavailable.
    func screen(imageData: Data) async throws -> CSAMScreeningResult
}

// MARK: - CSAM Screening Result

enum CSAMScreeningResult {
    /// Image cleared screening — no known CSAM hashes matched.
    case clean

    /// Image matched a known CSAM hash at the given confidence level.
    case flagged(confidence: Double)

    /// Screening infrastructure was unavailable.
    /// The fail-closed policy treats this as equivalent to .flagged.
    case screeningUnavailable
}

// MARK: - Child Safety Constraints Result

/// Captures what the child safety layer forced or blocked in a publish attempt.
struct ChildSafetyConstraintsResult {
    /// If non-nil, the audience was forced to this value regardless of the user's selection.
    let forcedAudience: CameraAudiencePreset?

    /// If true, GPS / location metadata must be stripped from this capture.
    let locationMustBeStripped: Bool

    /// If true, the publish is fully blocked and `blockReason` explains why.
    let isBlocked: Bool

    /// Human-readable reason shown to the user when `isBlocked` is true.
    let blockReason: String?
}

// MARK: - CameraChildSafetyService

actor CameraChildSafetyService {

    static let shared = CameraChildSafetyService()

    // Injected screener. nil = fail-closed: no screener means no publish allowed
    // for any capture that reaches the CSAM gate.
    var csamScreener: (any CSAMScreeningProtocol)?

    // MARK: - Init

    private init() {}

    // MARK: - Apply Child Safety Constraints

    /// Modifies `scanResult` in-place to enforce child safety rules:
    ///
    /// - If the capture contains a minor: force audience to .privateOnly,
    ///   set requiresHumanReview = true, strip location.
    /// - If the user is themselves a minor: force .privateOnly on every capture
    ///   regardless of content, per COPPA / platform minor policy.
    ///
    /// Returns a `ChildSafetyConstraintsResult` summarising what was enforced.
    @discardableResult
    func applyChildSafetyConstraints(
        to scanResult: inout CameraPrePublishScanResult,
        userIsMinor: Bool
    ) async -> ChildSafetyConstraintsResult {

        var forcedAudience: CameraAudiencePreset?
        var locationMustBeStripped = false
        var isBlocked = false
        var blockReason: String?

        // Rule 1: User is a minor — all their posts are private-only.
        if userIsMinor {
            scanResult = scanResult.withRecommendedAudience(.privateOnly)
            forcedAudience = .privateOnly
            locationMustBeStripped = true
        }

        // Rule 2: Capture contains a minor face — restrict audience and require review.
        if scanResult.containsMinor {
            scanResult = scanResult.withRecommendedAudience(.privateOnly)
            scanResult = scanResult.withRequiresHumanReview(true)
            forcedAudience = .privateOnly
            locationMustBeStripped = true

            // If the scan result was already blocked for another reason, preserve that.
            // Otherwise, non-minor users posting minors' faces get a review gate, not a hard block.
        }

        // Rule 3: If risk is already .critical and contains a minor, block publish entirely.
        if scanResult.containsMinor && scanResult.riskLevel >= .severe {
            isBlocked = true
            blockReason = "Content showing a child in a sensitive context cannot be published without moderation review."
            scanResult = scanResult.withBlocksPublish(true)
            scanResult = scanResult.withRequiresHumanReview(true)
        }

        return ChildSafetyConstraintsResult(
            forcedAudience: forcedAudience,
            locationMustBeStripped: locationMustBeStripped,
            isBlocked: isBlocked,
            blockReason: blockReason
        )
    }

    // MARK: - CSAM Screening

    /// Screens image data for CSAM.
    ///
    /// Fail-closed contract:
    ///   - If `csamScreener` is nil → .screeningUnavailable
    ///   - If the screener throws → .screeningUnavailable
    ///   - Callers must treat .screeningUnavailable as a block (see `shouldBlockForCSAM`).
    func screenForCSAM(imageData: Data) async -> CSAMScreeningResult {
        guard let screener = csamScreener else {
            // No screener injected — fail closed.
            return .screeningUnavailable
        }
        do {
            return try await screener.screen(imageData: imageData)
        } catch {
            // Screener threw — fail closed.
            return .screeningUnavailable
        }
    }

    /// Returns true if the given CSAM result should block the publish.
    ///
    /// Fail-closed: both .flagged and .screeningUnavailable block the publish.
    /// Only .clean allows the publish to proceed.
    func shouldBlockForCSAM(_ result: CSAMScreeningResult) -> Bool {
        switch result {
        case .clean:
            return false
        case .flagged:
            return true
        case .screeningUnavailable:
            return true  // Fail-closed: unknown = blocked.
        }
    }

    // MARK: - Audience Floor for Minor Content

    /// Returns the minimum (most restrictive) audience that may be set
    /// on any capture containing minor faces.
    /// No caller may override this to a more permissive preset.
    func minimumAudienceForMinorContent() -> CameraAudiencePreset {
        return .privateOnly
    }
}

// MARK: - CameraPrePublishScanResult mutation helpers
//
// CameraPrePublishScanResult is a struct; we provide small functional-update
// helpers here so the actor can produce modified copies without the call site
// needing to re-construct the full struct.

private extension CameraPrePublishScanResult {

    func withRecommendedAudience(_ audience: CameraAudiencePreset) -> CameraPrePublishScanResult {
        CameraPrePublishScanResult(
            riskLevel: riskLevel,
            detectedItems: detectedItems,
            redactionSuggestions: redactionSuggestions,
            safetyProfile: safetyProfile,
            requiresHumanReview: requiresHumanReview,
            blocksPublish: blocksPublish,
            nudgeMessage: nudgeMessage,
            recommendedAudience: audience,
            sceneType: sceneType,
            containsMinor: containsMinor
        )
    }

    func withRequiresHumanReview(_ value: Bool) -> CameraPrePublishScanResult {
        CameraPrePublishScanResult(
            riskLevel: riskLevel,
            detectedItems: detectedItems,
            redactionSuggestions: redactionSuggestions,
            safetyProfile: safetyProfile,
            requiresHumanReview: value,
            blocksPublish: blocksPublish,
            nudgeMessage: nudgeMessage,
            recommendedAudience: recommendedAudience,
            sceneType: sceneType,
            containsMinor: containsMinor
        )
    }

    func withBlocksPublish(_ value: Bool) -> CameraPrePublishScanResult {
        CameraPrePublishScanResult(
            riskLevel: riskLevel,
            detectedItems: detectedItems,
            redactionSuggestions: redactionSuggestions,
            safetyProfile: safetyProfile,
            requiresHumanReview: requiresHumanReview,
            blocksPublish: value,
            nudgeMessage: nudgeMessage,
            recommendedAudience: recommendedAudience,
            sceneType: sceneType,
            containsMinor: containsMinor
        )
    }
}

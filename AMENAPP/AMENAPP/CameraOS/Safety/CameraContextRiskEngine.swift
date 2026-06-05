// CameraContextRiskEngine.swift
// AMENAPP — Camera OS
// Compositional risk scoring: composes multiple signals into a single risk level.
// Never single-flags; always reasons over the full detection set.

import Foundation
import CoreLocation

// MARK: - CameraContextRiskEngine

actor CameraContextRiskEngine {

    static let shared = CameraContextRiskEngine()

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Computes a full pre-publish scan result by composing all available signals.
    /// This function performs synchronous logic only — ML detection is handled upstream
    /// by the scan service, which feeds detected items into this engine.
    func computeRisk(
        detectedItems: [CameraSensitiveItemType],
        sceneType: CameraSceneType,
        userLocation: CLLocation?,
        safeZones: [CameraSafeZone],
        safetyProfile: CameraSafetyProfile,
        intent: CameraIntent
    ) async -> CameraPrePublishScanResult {

        // 1. Derive composite risk level from items, scene, and profile.
        let riskLevel = compositeRisk(
            items: detectedItems,
            scene: sceneType,
            profile: safetyProfile
        )

        // 2. Determine if location is within a declared safe zone (e.g. a school campus).
        let isNearSchoolSafeZone = isInSafeZone(
            location: userLocation,
            safeZones: safeZones,
            types: [.school, .classroom]
        )

        // 3. If all four critical signals align: minor face + school uniform + school sign + school safe zone,
        //    override to .critical regardless of profile weighting.
        let hasCriticalSchoolPattern =
            detectedItems.contains(.minorFace) &&
            detectedItems.contains(.schoolUniform) &&
            detectedItems.contains(.schoolSign) &&
            isNearSchoolSafeZone

        let finalRiskLevel: CameraContextRiskLevel = hasCriticalSchoolPattern ? .critical : riskLevel

        // 4. Build redaction suggestions for items that are auto-redactable.
        let redactionSuggestions = buildRedactionSuggestions(for: detectedItems)

        // 5. Determine publish gate and human review flag.
        let blocksPublish = finalRiskLevel >= .severe
        let requiresHumanReview = finalRiskLevel >= .high

        // 6. Derive the recommended audience for the risk level.
        let audience = recommendedAudience(
            for: finalRiskLevel,
            items: detectedItems,
            profile: safetyProfile
        )

        // 7. Build the nudge message if appropriate.
        let nudge = nudgeMessage(
            for: finalRiskLevel,
            items: detectedItems,
            scene: sceneType
        )

        // 8. Detect whether a minor appears in the content.
        let containsMinor = detectedItems.contains(.minorFace)

        return CameraPrePublishScanResult(
            riskLevel: finalRiskLevel,
            detectedItems: detectedItems,
            redactionSuggestions: redactionSuggestions,
            safetyProfile: safetyProfile,
            requiresHumanReview: requiresHumanReview,
            blocksPublish: blocksPublish,
            nudgeMessage: nudge,
            recommendedAudience: audience,
            sceneType: sceneType,
            containsMinor: containsMinor
        )
    }

    // MARK: - Private Helpers

    /// Computes a scalar risk level from raw item weights alone, without scene or profile modifiers.
    private func baseRisk(for items: [CameraSensitiveItemType]) -> CameraContextRiskLevel {
        let total = items.reduce(0) { $0 + itemWeight($1) }

        switch total {
        case 0:       return .low
        case 1...2:   return .low
        case 3...4:   return .medium
        case 5...6:   return .high
        case 7...9:   return .severe
        default:      return .critical
        }
    }

    /// Weight contribution of a single item type.
    private func itemWeight(_ item: CameraSensitiveItemType) -> Int {
        switch item {
        case .minorFace:      return 2
        case .adultFace:      return 0
        case .homeAddress:    return 2
        case .streetSign:     return 0   // low on its own; compositional signals add weight
        case .schoolSign:     return 2
        case .schoolUniform:  return 1
        case .busStop:        return 1
        case .licensePlate:   return 1
        case .idDocument:     return 3
        case .badge:          return 2
        case .medicalRecord:  return 3
        case .screenContent:  return 1
        case .phoneNumber:    return 1
        }
    }

    /// Applies compositional rules on top of the scalar base risk.
    ///
    /// Compositional rules:
    ///   - minorFace + schoolUniform → at least .medium
    ///   - minorFace + schoolUniform + schoolSign → at least .high
    ///   - minorFace + schoolUniform + schoolSign + near-school safe zone → .critical (handled in computeRisk)
    ///   - idDocument / medicalRecord / badge → at least .high
    ///   - profile == .parent / .school → multiply weights by 1.5 (rounded up)
    ///   - scene == .school / .classroom → bump minorFace detections by +1
    private func compositeRisk(
        items: [CameraSensitiveItemType],
        scene: CameraSceneType,
        profile: CameraSafetyProfile
    ) -> CameraContextRiskLevel {

        // Build an effective item list, applying scene-based weight amplification.
        var effectiveItems = items
        if (scene == .school || scene == .classroom) && items.contains(.minorFace) {
            // Amplify: treat minorFace as appearing twice in the weight total.
            effectiveItems.append(.minorFace)
        }

        // Compute profile multiplier.
        let profileMultiplier: Double = (profile == .parent || profile == .school) ? 1.5 : 1.0

        // Compute base score with profile multiplier applied.
        let rawScore = effectiveItems.reduce(0) { $0 + itemWeight($1) }
        let weightedScore = Int((Double(rawScore) * profileMultiplier).rounded(.up))

        var level: CameraContextRiskLevel = {
            switch weightedScore {
            case 0...2:   return .low
            case 3...4:   return .medium
            case 5...6:   return .high
            case 7...9:   return .severe
            default:      return .critical
            }
        }()

        // --- Compositional overrides ---

        // Rule: documents and credentials → always at least .high.
        let sensitiveDocPresent =
            items.contains(.idDocument) ||
            items.contains(.medicalRecord) ||
            items.contains(.badge)
        if sensitiveDocPresent {
            level = max(level, .high)
        }

        // Rule: minorFace + schoolUniform → at least .medium.
        if items.contains(.minorFace) && items.contains(.schoolUniform) {
            level = max(level, .medium)
        }

        // Rule: minorFace + schoolUniform + schoolSign → at least .high.
        if items.contains(.minorFace) && items.contains(.schoolUniform) && items.contains(.schoolSign) {
            level = max(level, .high)
        }

        return level
    }

    /// Returns an optional human-readable nudge message for the current risk level.
    private func nudgeMessage(
        for level: CameraContextRiskLevel,
        items: [CameraSensitiveItemType],
        scene: CameraSceneType
    ) -> String? {
        switch level {
        case .low:
            return nil

        case .medium:
            if items.contains(.minorFace) {
                return "This photo may include a child. Consider limiting your audience."
            }
            if items.contains(.licensePlate) || items.contains(.homeAddress) {
                return "Personal information detected. Review before sharing."
            }
            return "Some personal details were detected. Consider limiting your audience."

        case .high:
            if items.contains(.minorFace) && items.contains(.schoolUniform) {
                return "A child in a school uniform has been detected. This post will be limited to close connections only."
            }
            if items.contains(.idDocument) {
                return "An ID document has been detected. Sharing is restricted to protect personal information."
            }
            if items.contains(.medicalRecord) {
                return "Medical information has been detected. This will require review before publishing."
            }
            if scene == .school || scene == .classroom {
                return "School environment detected. Audience has been restricted to protect children's privacy."
            }
            return "Sensitive content detected. Your audience has been automatically restricted."

        case .severe:
            if items.contains(.minorFace) {
                return "Content showing a child in a sensitive context cannot be shared publicly. Human review required."
            }
            return "Sensitive content requires review before it can be published."

        case .critical:
            return "This content cannot be published. It contains highly sensitive information and has been blocked pending review."
        }
    }

    /// Derives the most restrictive appropriate audience preset for the risk level.
    private func recommendedAudience(
        for level: CameraContextRiskLevel,
        items: [CameraSensitiveItemType],
        profile: CameraSafetyProfile
    ) -> CameraAudiencePreset {

        // Any minor in the image forces at minimum a close-circle audience.
        let containsMinor = items.contains(.minorFace)

        switch level {
        case .low:
            if profile == .parent || profile == .school { return .friends }
            return .public

        case .medium:
            if containsMinor { return .family }
            if profile == .parent || profile == .school { return .family }
            return .friends

        case .high:
            if containsMinor { return .privateOnly }
            if items.contains(.idDocument) || items.contains(.medicalRecord) { return .privateOnly }
            return .smallGroup

        case .severe:
            return .privateOnly

        case .critical:
            return .privateOnly
        }
    }

    // MARK: - Safe Zone Helpers

    /// Returns true if `location` is within 200 metres of any safe zone
    /// whose scene type is in `types`.
    private func isInSafeZone(
        location: CLLocation?,
        safeZones: [CameraSafeZone],
        types: Set<CameraSceneType>
    ) -> Bool {
        guard let loc = location else { return false }
        for zone in safeZones where types.contains(zone.sceneType) {
            let zoneLocation = CLLocation(
                latitude: zone.coordinate.latitude,
                longitude: zone.coordinate.longitude
            )
            if loc.distance(from: zoneLocation) <= zone.radiusMetres {
                return true
            }
        }
        return false
    }

    // MARK: - Redaction Suggestion Builder

    /// Builds placeholder redaction suggestions for auto-redactable item types.
    /// In production, the ML scanner provides the normalised rects; here we
    /// generate zero-rect placeholders so the result type is always well-formed.
    private func buildRedactionSuggestions(
        for items: [CameraSensitiveItemType]
    ) -> [CameraRedactionSuggestion] {
        items
            .filter { autoRedactableTypes.contains($0) }
            .enumerated()
            .map { index, itemType in
                CameraRedactionSuggestion(
                    id: "suggestion-\(index)-\(itemType)",
                    itemType: itemType,
                    normalizedRect: .zero,
                    confidence: 0.0,
                    autoRedactable: true,
                    isRedacted: false
                )
            }
    }

    /// Item types that can be automatically redacted without user confirmation.
    private let autoRedactableTypes: Set<CameraSensitiveItemType> = [
        .licensePlate,
        .homeAddress,
        .phoneNumber,
        .screenContent,
        .idDocument,
        .medicalRecord
    ]
}

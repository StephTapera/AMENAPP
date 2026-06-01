// AegisService.swift
// Aegis Safety Orchestrator — composes N detection results into AegisSafetyDecision.
// All capabilities default-OFF via AegisFeatureFlags; nothing runs unless the flag is ON.
//
// Lane routing:
//   .vision      → AegisVisionDetector (on-device) + optional server escalation
//   .berean      → aegisReviewText callable (Berean LLM)
//   .provenance  → aegisAnalyzeMedia callable
//   .harassment, .privacyModes, .vulnerableUser, .wellbeing, .dataRights → aegisReviewText callable
//
// callWithTimeout is defined on Functions in FirebaseCallableHelper.swift.

import Foundation
import UIKit
import FirebaseAuth
import FirebaseFunctions

// MARK: - AegisService

@MainActor
final class AegisService: ObservableObject {

    static let shared = AegisService()

    private let functions = Functions.functions()
    private let detector = AegisVisionDetector()

    private init() {}

    // MARK: - Public API

    /// Analyzes media (image/video/audio) against all enabled vision + provenance capabilities.
    /// On-device Vision runs first; server escalation fires when confidence is low or server
    /// capabilities are enabled.
    func analyzeMedia(url: String, type: String, surface: ContentSurface) async -> AegisSafetyDecision {
        let uid = Auth.auth().currentUser?.uid ?? "anonymous"

        // 1. Collect enabled vision-lane capabilities
        let visionCaps = AegisCapability.allCases.filter {
            $0.lane == .vision && AegisFeatureFlags.shared.isEnabled($0)
        }

        // 2. On-device detection (image only; skip for audio/video)
        var onDeviceResults: [AegisDetectionResult] = []
        if type == "image", let imageUrl = URL(string: url) {
            onDeviceResults = await runOnDeviceDetection(imageUrl: imageUrl)
        }

        // 3. Determine which capabilities need server escalation:
        //    - Provenance-lane caps always go to server
        //    - Vision caps where on-device confidence < threshold → escalate
        let provenanceCaps = AegisCapability.allCases.filter {
            $0.lane == .provenance && AegisFeatureFlags.shared.isEnabled($0)
        }
        let needsServerEscalation = !provenanceCaps.isEmpty
            || onDeviceResults.contains(where: { $0.confidence < 0.75 && $0.severity >= .caution })
            || !visionCaps.isEmpty // send all enabled vision caps to server for cross-check

        var serverResults: [AegisDetectionResult] = []
        if needsServerEscalation {
            let allCaps = (visionCaps + provenanceCaps).map(\.rawValue)
            guard !allCaps.isEmpty else { return compositeDecision(from: onDeviceResults) }
            let req = AegisAnalyzeMediaRequest(
                mediaUrl: url,
                mediaType: type,
                userId: uid,
                surface: surface.rawValue,
                capabilities: allCaps
            )
            if let resp = try? await callAegisAnalyzeMedia(req) {
                serverResults = resp.results
            }
        }

        // 4. Merge: prefer the server result if present, else keep on-device.
        //    De-duplicate by capabilityId, taking the higher-severity result.
        let merged = mergeResults(primary: serverResults, fallback: onDeviceResults)
        return compositeDecision(from: merged)
    }

    /// Reviews text against all enabled non-vision capabilities.
    func reviewText(_ text: String, surface: ContentSurface) async -> AegisSafetyDecision {
        let uid = Auth.auth().currentUser?.uid ?? "anonymous"

        let enabledCaps = AegisCapability.allCases.filter {
            $0.lane != .vision && AegisFeatureFlags.shared.isEnabled($0)
        }
        guard !enabledCaps.isEmpty else {
            return AegisSafetyDecision.allow()
        }

        let req = AegisReviewTextRequest(
            text: text,
            surface: surface.rawValue,
            userId: uid,
            capabilities: enabledCaps.map(\.rawValue),
            context: [:]
        )
        guard let resp = try? await callAegisReviewText(req) else {
            return AegisSafetyDecision.allow()
        }
        return resp.decision
    }

    // MARK: - Decision Composition

    /// Merges N detection results into a single AegisSafetyDecision.
    ///
    /// Rules:
    ///   - Any .block  → allowPost = false, result added to redactions
    ///   - Any .warn   → allowPost = true, audienceRestriction = .adultsOnly
    ///   - Any .caution → requiredAcknowledgements appended
    ///   - All care resources aggregated, de-duplicated by id
    ///   - routeToCare = true if any careResources are present
    func compositeDecision(from results: [AegisDetectionResult]) -> AegisSafetyDecision {
        guard !results.isEmpty else {
            return AegisSafetyDecision.allow()
        }

        let blockResults   = results.filter { $0.severity == .block }
        let warnResults    = results.filter { $0.severity == .warn }
        let cautionResults = results.filter { $0.severity == .caution }

        let allowPost = blockResults.isEmpty
        let redactions = blockResults

        var audienceRestriction: AegisSafetyDecision.AegisAudienceRestriction? = nil
        if !warnResults.isEmpty { audienceRestriction = .adultsOnly }
        if results.contains(where: { $0.capabilityId == .childMinorPresence && $0.severity >= .warn }) {
            audienceRestriction = .noMinors
        }

        let requiredAcks = cautionResults.map(\.capabilityId)

        // Aggregate care resources, de-dup by id
        var seenCareIds = Set<String>()
        let allCare = results
            .flatMap(\.careResources)
            .filter { seenCareIds.insert($0.id).inserted }
        let libraryCare = careLibrary(for: results.map(\.capabilityId))
            .filter { seenCareIds.insert($0.id).inserted }
        let careResources = allCare + libraryCare

        return AegisSafetyDecision(
            decisionId: UUID().uuidString,
            allowPost: allowPost,
            requiredAcknowledgements: requiredAcks,
            audienceRestriction: audienceRestriction,
            redactions: redactions,
            routeToCare: !careResources.isEmpty,
            careResources: careResources,
            detectionResults: results,
            timestamp: Date(),
            policyVersion: AegisContractsVersion
        )
    }

    // MARK: - Private Helpers

    private func runOnDeviceDetection(imageUrl: URL) async -> [AegisDetectionResult] {
        guard let data = try? Data(contentsOf: imageUrl),
              let image = UIImage(data: data) else { return [] }
        return await detector.detectAll(in: image)
    }

    /// Merge results from two arrays: for each capability, prefer the higher-severity result.
    private func mergeResults(
        primary: [AegisDetectionResult],
        fallback: [AegisDetectionResult]
    ) -> [AegisDetectionResult] {
        var byCapability: [AegisCapability: AegisDetectionResult] = [:]
        for result in fallback + primary {   // primary wins on equal severity because it comes last
            let existing = byCapability[result.capabilityId]
            if existing == nil || result.severity >= existing!.severity {
                byCapability[result.capabilityId] = result
            }
        }
        return Array(byCapability.values)
    }

    // MARK: - Callable Wrappers

    private func callAegisAnalyzeMedia(_ req: AegisAnalyzeMediaRequest) async throws -> AegisAnalyzeMediaResponse {
        let payload = try encodeToDict(req)
        let result = try await functions.callWithTimeout("aegisAnalyzeMedia", data: payload, timeout: 30)
        guard let dict = result.data as? [String: Any] else {
            throw AegisServiceError.malformedResponse("aegisAnalyzeMedia")
        }
        return try decodeFromDict(dict, as: AegisAnalyzeMediaResponse.self)
    }

    private func callAegisReviewText(_ req: AegisReviewTextRequest) async throws -> AegisReviewTextResponse {
        let payload = try encodeToDict(req)
        let result = try await functions.callWithTimeout("aegisReviewText", data: payload, timeout: 30)
        guard let dict = result.data as? [String: Any] else {
            throw AegisServiceError.malformedResponse("aegisReviewText")
        }
        return try decodeFromDict(dict, as: AegisReviewTextResponse.self)
    }

    // MARK: - Encode / Decode helpers

    private func encodeToDict<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            throw AegisServiceError.encodingFailed
        }
        return dict
    }

    private func decodeFromDict<T: Decodable>(_ dict: [String: Any], as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(type, from: data)
    }

    // MARK: - Static Care Resource Library

    /// Returns pre-defined care resources relevant to the triggered capabilities.
    private func careLibrary(for capabilities: [AegisCapability]) -> [AegisCareResource] {
        var resources: [AegisCareResource] = []
        let caps = Set(capabilities)

        if caps.contains(.spiritualAbuse) {
            resources.append(AegisCareResource(
                id: "care.spiritual_abuse.grace_truth",
                title: "GRACE & TRUTH Hotline",
                body: "Confidential support for survivors of spiritual abuse and religious coercion. Available 24/7.",
                actionLabel: "Call Now",
                actionUrl: "tel:+18009874357",
                resourceType: .crisisLine
            ))
            resources.append(AegisCareResource(
                id: "care.spiritual_abuse.network",
                title: "Spiritual Abuse Recovery Network",
                body: "Peer-support community for those healing from coercive religious control.",
                actionLabel: "Visit Site",
                actionUrl: "https://spiritualabusenetwork.com",
                resourceType: .externalLink
            ))
        }

        if caps.contains(.sextortionPattern) {
            resources.append(AegisCareResource(
                id: "care.sextortion.ccri",
                title: "Cyber Civil Rights Initiative",
                body: "Free crisis helpline and resources for victims of non-consensual intimate image abuse and sextortion.",
                actionLabel: "Get Help",
                actionUrl: "https://cybercivilrights.org",
                resourceType: .crisisLine
            ))
            resources.append(AegisCareResource(
                id: "care.sextortion.ncmec",
                title: "NCMEC CyberTipline",
                body: "Report sextortion or exploitation of minors to the National Center for Missing & Exploited Children.",
                actionLabel: "Report Now",
                actionUrl: "https://www.missingkids.org/gethelpnow/cybertipline",
                resourceType: .externalLink
            ))
        }

        if caps.contains(.romanceScam) {
            resources.append(AegisCareResource(
                id: "care.romance_scam.ic3",
                title: "FBI Internet Crime Complaint Center (IC3)",
                body: "File a complaint about romance scams, pig-butchering fraud, and other internet crimes.",
                actionLabel: "File Report",
                actionUrl: "https://www.ic3.gov",
                resourceType: .externalLink
            ))
            resources.append(AegisCareResource(
                id: "care.romance_scam.ftc",
                title: "FTC — ReportFraud.ftc.gov",
                body: "Report romance scams to the Federal Trade Commission to help protect others.",
                actionLabel: "Report Scam",
                actionUrl: "https://reportfraud.ftc.gov",
                resourceType: .externalLink
            ))
        }

        if caps.contains(.donationFraud) {
            resources.append(AegisCareResource(
                id: "care.donation_fraud.bbb",
                title: "BBB Wise Giving Alliance",
                body: "Verify charitable organizations before donating. Protects you from fraudulent ministries.",
                actionLabel: "Verify Charity",
                actionUrl: "https://give.org",
                resourceType: .externalLink
            ))
        }

        if caps.contains(.childMinorPresence) || caps.contains(.aiCsamDetection) {
            resources.append(AegisCareResource(
                id: "care.child.ncmec",
                title: "NCMEC CyberTipline",
                body: "Report suspected child exploitation material to NCMEC.",
                actionLabel: "Report Now",
                actionUrl: "https://www.missingkids.org/gethelpnow/cybertipline",
                resourceType: .crisisLine
            ))
        }

        if caps.contains(.doxxingDetection) || caps.contains(.stalkingPattern) {
            resources.append(AegisCareResource(
                id: "care.doxxing.safety_net",
                title: "Safety Net — Tech Safety",
                body: "Resources for survivors experiencing technology-facilitated abuse, including doxxing and stalking.",
                actionLabel: "Get Help",
                actionUrl: "https://techsafety.org",
                resourceType: .externalLink
            ))
        }

        if caps.contains(.prayerExploitation) {
            resources.append(AegisCareResource(
                id: "care.prayer.pastoral_note",
                title: "Speak with a Pastoral Counselor",
                body: "Your prayer requests are sacred. Reach out to a trusted pastor or certified Christian counselor if something felt wrong.",
                actionLabel: "Find a Counselor",
                actionUrl: "https://aacc.net/find-a-counselor",
                resourceType: .pastoralGuidance
            ))
        }

        if caps.contains(.griefTargeting) || caps.contains(.elderNewBeliever) || caps.contains(.crisisFinancial) {
            resources.append(AegisCareResource(
                id: "care.vulnerable.befrienders",
                title: "Befrienders Worldwide",
                body: "Confidential emotional support for those in distress. Available globally.",
                actionLabel: "Find Support",
                actionUrl: "https://www.befrienders.org",
                resourceType: .crisisLine
            ))
        }

        return resources
    }
}

// MARK: - Error

private enum AegisServiceError: Error, LocalizedError {
    case malformedResponse(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .malformedResponse(let fn): return "Aegis: malformed response from \(fn)"
        case .encodingFailed: return "Aegis: failed to encode request payload"
        }
    }
}

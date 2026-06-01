// AegisVulnerableUserService.swift — C44–C46 Vulnerable-User Protection
// Capabilities: griefTargeting, elderNewBeliever, crisisFinancial

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

actor AegisVulnerableUserService {

    static let shared = AegisVulnerableUserService()

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    private init() {}

    // MARK: - C44: Grief / Bereavement Targeting

    /// Detects grief signals in post text and auto-restricts DMs from strangers for 72h.
    func assessGriefVulnerability(postText: String, userId: String) async -> AegisDetectionResult? {
        guard await AegisFeatureFlags.shared.isEnabled(.griefTargeting) else { return nil }

        let keywords = ["funeral", "loss", "passed away", "memorial", "grieving", "in memoriam",
                        "rest in peace", "gone too soon", "bereavement", "mourning"]
        let lower = postText.lowercased()
        let matched = keywords.filter { lower.contains($0) }
        guard !matched.isEmpty else { return nil }

        let confidence = min(0.6 + (Double(matched.count) * 0.1), 0.95)

        // Write a 72-hour DM restriction flag for this user
        let restrictUntil = Date().addingTimeInterval(72 * 3600)
        try? await db
            .collection("aegisProfiles")
            .document(userId)
            .setData([
                "griefDmRestrictionUntil": Timestamp(date: restrictUntil),
                "griefFlaggedAt": FieldValue.serverTimestamp(),
            ], merge: true)

        let evidence = matched.map { keyword -> AegisEvidence in
            let range = (lower as NSString).range(of: keyword)
            return AegisEvidence(
                type: .textSpan,
                description: "Grief keyword detected: '\(keyword)'",
                confidence: 0.9,
                spanStart: range.location == NSNotFound ? nil : range.location,
                spanEnd: range.location == NSNotFound ? nil : range.location + range.length
            )
        }

        let care = [
            AegisCareResource(
                id: "C44-grief-safety",
                title: "Safety During Grief",
                body: "Scammers often target people during difficult times. Be cautious of financial requests or quick romantic interest from new contacts.",
                actionLabel: "Learn More",
                actionUrl: "https://www.ftc.gov/consumer-advice/articles/what-you-need-know-about-romance-scams",
                resourceType: .pastoralGuidance
            )
        ]

        return AegisDetectionResult.make(
            capability: .griefTargeting,
            severity: .caution,
            confidence: confidence,
            action: "DM access from non-connections restricted for 72 hours. Scam-protection resources surfaced.",
            evidence: evidence,
            care: care
        )
    }

    // MARK: - C45: Elder & New-Believer Protection

    /// Detects elder or new-believer vulnerability signals and warns when romantic or financial approaches occur.
    func assessElderNewBeliever(accountAge: TimeInterval, interactionPatterns: [String]) async -> AegisDetectionResult? {
        guard await AegisFeatureFlags.shared.isEnabled(.elderNewBeliever) else { return nil }

        let isNewAccount = accountAge < (90 * 24 * 3600) // < 90 days
        let elderSignals = ["senior", "retired", "grandparent", "elderly", "widow", "widower"]
        let hasElderPattern = interactionPatterns.contains { pattern in
            elderSignals.contains { pattern.lowercased().contains($0) }
        }

        guard isNewAccount || hasElderPattern else { return nil }

        let financialApproach = interactionPatterns.contains { p in
            let l = p.lowercased()
            return l.contains("invest") || l.contains("send money") || l.contains("gift card")
                || l.contains("wire") || l.contains("crypto") || l.contains("blessing")
        }
        let romanticApproach = interactionPatterns.contains { p in
            let l = p.lowercased()
            return l.contains("beautiful") || l.contains("soulmate") || l.contains("meet in person")
                || l.contains("fall in love") || l.contains("destiny")
        }

        guard financialApproach || romanticApproach else { return nil }

        let confidence: Double = isNewAccount && (financialApproach || romanticApproach) ? 0.82 : 0.65
        let approachType = financialApproach ? "financial" : "romantic"

        let evidence = [
            AegisEvidence(
                type: .pattern,
                description: "Account age: \(Int(accountAge / 86400))d. \(approachType.capitalized) approach pattern detected.",
                confidence: confidence,
                spanStart: nil,
                spanEnd: nil
            )
        ]

        let care = [
            AegisCareResource(
                id: "C45-elder-protect",
                title: "Protect Yourself",
                body: "Be cautious of financial or romantic requests from new connections, especially those you have not met in person.",
                actionLabel: "Review Connection",
                actionUrl: nil,
                resourceType: .inAppAction
            )
        ]

        return AegisDetectionResult.make(
            capability: .elderNewBeliever,
            severity: .warn,
            confidence: confidence,
            action: "Be cautious of financial or romantic requests from new connections.",
            evidence: evidence,
            care: care
        )
    }

    // MARK: - C46: Crisis-State Financial Predation

    /// Detects crisis signals followed by financial solicitation from non-connections.
    func assessCrisisFinancial(postText: String, userId: String) async -> AegisDetectionResult? {
        guard await AegisFeatureFlags.shared.isEnabled(.crisisFinancial) else { return nil }

        let crisisKeywords = ["lost my job", "divorce", "bankruptcy", "can't pay", "medical bills",
                              "evicted", "foreclosure", "laid off", "homeless", "desperate need"]
        let financialSolicitationKeywords = ["cash app", "venmo", "paypal", "gofundme", "zelle",
                                             "send money", "donation", "help me financially",
                                             "wire transfer", "gift card"]

        let lower = postText.lowercased()
        let crisisMatched = crisisKeywords.filter { lower.contains($0) }
        let solicitationMatched = financialSolicitationKeywords.filter { lower.contains($0) }

        guard !crisisMatched.isEmpty && !solicitationMatched.isEmpty else { return nil }

        let confidence = min(0.65 + (Double(crisisMatched.count + solicitationMatched.count) * 0.08), 0.92)

        let crisisEvidence = crisisMatched.map { keyword -> AegisEvidence in
            AegisEvidence(
                type: .textSpan,
                description: "Crisis signal: '\(keyword)'",
                confidence: 0.85,
                spanStart: nil,
                spanEnd: nil
            )
        }
        let solicitationEvidence = solicitationMatched.map { keyword -> AegisEvidence in
            AegisEvidence(
                type: .textSpan,
                description: "Financial solicitation signal: '\(keyword)'",
                confidence: 0.80,
                spanStart: nil,
                spanEnd: nil
            )
        }

        let care = [
            AegisCareResource(
                id: "C46-fbi-ic3",
                title: "Report Financial Fraud",
                body: "If you believe you are being targeted by a financial scammer, report it to the FBI Internet Crime Complaint Center.",
                actionLabel: "File a Report",
                actionUrl: "https://www.ic3.gov",
                resourceType: .externalLink
            ),
            AegisCareResource(
                id: "C46-church-care",
                title: "Church Care Resources",
                body: "Your church community can connect you with trusted financial counseling and benevolence support.",
                actionLabel: "Find Support",
                actionUrl: nil,
                resourceType: .inAppAction
            ),
        ]

        return AegisDetectionResult.make(
            capability: .crisisFinancial,
            severity: .warn,
            confidence: confidence,
            action: "Financial solicitation detected alongside crisis signals. Care resources surfaced.",
            evidence: crisisEvidence + solicitationEvidence,
            care: care
        )
    }
}

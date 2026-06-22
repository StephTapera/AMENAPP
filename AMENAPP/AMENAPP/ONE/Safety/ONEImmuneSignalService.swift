// ONEImmuneSignalService.swift
// ONE P5-B/C — Metadata-only immune signals + evidence path.
//
// Safety rule: The immune system operates on PUBLIC metadata only.
// It NEVER reads E2E-encrypted content. For E2E threads, only momentID,
// timestamp, authorUID, category, and a content hash are captured.
// Plaintext never reaches this service or the server.
//
// Evidence lock invariant: one_reportMoment locks evidence server-side
// BEFORE decay can run. A moment with evidenceLocked=true is skipped
// by the decay CF. Author account deletion cannot remove locked evidence.

import Foundation

// MARK: - Report category

enum ONEReportCategory: String, CaseIterable, Sendable {
    case harmful           = "harmful"
    case harassment        = "harassment"
    case illegal           = "illegal"
    case misinformation    = "misinformation"

    var displayLabel: String {
        switch self {
        case .harmful:        return "Harmful or dangerous"
        case .harassment:     return "Harassment or abuse"
        case .illegal:        return "Illegal content"
        case .misinformation: return "Dangerous misinformation"
        }
    }

    var displayDescription: String {
        switch self {
        case .harmful:        return "Content that may cause harm to self or others"
        case .harassment:     return "Targeted, repeated harmful behavior"
        case .illegal:        return "CSAM, trafficking, or other illegal material"
        case .misinformation: return "False content that could cause real-world harm"
        }
    }

    var icon: String {
        switch self {
        case .harmful:        return "exclamationmark.triangle.fill"
        case .harassment:     return "hand.raised.fill"
        case .illegal:        return "scale.3d"
        case .misinformation: return "megaphone.fill"
        }
    }
}

// MARK: - Evidence receipt

struct ONEEvidenceReceipt: Sendable {
    let evidenceID: String
    let momentID:   String
    let category:   ONEReportCategory
    let lockedAt:   Date
    let retainUntil: Date  // 90-day default from SECURITY.md BQ-5
}

// MARK: - ONEImmuneSignalService

actor ONEImmuneSignalService {
    static let shared = ONEImmuneSignalService()
    private init() {}

    // In-memory set to prevent duplicate reports within the same session.
    private var reportedMomentIDs: Set<String> = []

    // MARK: - Report a moment

    /// Lock server-side evidence and file a report.
    /// Safe to call from any context — operates on public metadata only.
    func reportMoment(momentID: String, category: ONEReportCategory) async throws -> ONEEvidenceReceipt {
        guard !reportedMomentIDs.contains(momentID) else {
            // Already reported this session — return a placeholder receipt
            // rather than filing a duplicate. A real implementation would
            // look up the existing receipt from the server.
            return ONEEvidenceReceipt(
                evidenceID: "DUPLICATE",
                momentID:   momentID,
                category:   category,
                lockedAt:   Date(),
                retainUntil: Date().addingTimeInterval(90 * 86_400)
            )
        }

        // Evidence lock happens server-side in one_reportMoment.
        // The CF sets evidenceLocked=true on the moment document BEFORE
        // enqueueing any decay operations. This order is enforced in CF logic.
        let evidenceID = try await ONECallableService.shared.reportMoment(
            momentID: momentID,
            reason: category.rawValue
        )

        reportedMomentIDs.insert(momentID)

        return ONEEvidenceReceipt(
            evidenceID:  evidenceID,
            momentID:    momentID,
            category:    category,
            lockedAt:    Date(),
            retainUntil: Date().addingTimeInterval(90 * 86_400)
        )
    }

    // MARK: - Metadata-only signal check

    /// Check whether public metadata for a moment has anomalous reach patterns.
    /// This operates on aggregated, public data only — never E2E content.
    /// Returns true if the moment should be soft-flagged for elevated review.
    func hasAnomalousReachSignal(reachBudget: ONEReachBudget) -> Bool {
        // Heuristic: chain depth > 8 with < 2 shares remaining signals viral coercion.
        return reachBudget.chainDepth > 8 && reachBudget.sharesRemaining < 2
    }
}

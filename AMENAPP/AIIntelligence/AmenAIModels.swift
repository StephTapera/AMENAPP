import Foundation

// MARK: - AmenAIProvenance
// Extended with constitutional audit trail fields (safety-hardening, 2026-06-12).
// constitutionalReviewPassed and bereanMode are the Enterprise Reliability Framework
// anchor: every AI-assisted artefact carries a record of whether the constitutional
// gate passed and which mode was active.

struct AmenAIProvenance: Codable, Equatable {
    let aiAssisted: Bool
    let aiGenerated: Bool
    let aiTranslated: Bool
    let aiCaptioned: Bool
    let provider: String
    let model: String
    let runId: String
    let taskType: String
    let sourceSurface: String
    let userApproved: Bool
    let userEdited: Bool
    let moderationStatus: String
    let safetyVerdict: String
    let createdAt: Date
    let approvedAt: Date?
    /// True when BereanConstitutionalReviewGate passed for this artefact.
    let constitutionalReviewPassed: Bool
    /// The constitutional mode that was in effect when this artefact was generated.
    let bereanMode: BereanConstitutionalMode
}

struct AmenGeneratedDraft: Identifiable, Codable, Equatable {
    let id: String
    let ownerUid: String
    let sourceSurface: String
    let taskType: String
    let outputType: String
    let title: String?
    let body: String?
    let mediaUrl: String?
    let thumbnailUrl: String?
    let languageCode: String?
    let targetLanguageCode: String?
    let provenance: AmenAIProvenance
    let status: String
    let createdAt: Date
    let updatedAt: Date
}

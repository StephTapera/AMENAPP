// TestimonyCopilotContracts.swift
// AMENAPP — ARISE / OUTPOUR Creator Co-Pilot
//
// Field-for-field Swift mirror of Backend/functions/src/testimony/testimonyCopilotContracts.ts.
// TypeScript is the source of truth; no logic divergence here. These are pure value types.
//
// Everything is INERT until the creator confirms (state .creatorReview -> .confirmed).
// Nothing auto-publishes. AI captions are disclosed as AuthenticityKind.aiAssistedCaptions
// (raw value "ai_assisted_captions", defined in SocialOSModels.swift). The child-safety hash
// hook is enforced fail-closed by the GUARDIAN pre-publish chain and is never gated here.

import Foundation

// MARK: - Disclosed authenticity kind (raw values match AuthenticityKind in SocialOSModels.swift)

enum CopilotAuthenticityKind: String, Codable, CaseIterable, Sendable {
    case aiAssistedCaptions = "ai_assisted_captions"
    case aiAssistedTranslation = "ai_assisted_translation"
    case transcriptApproved = "transcript_approved"
}

// MARK: - Job state machine

enum CopilotJobState: String, Codable, CaseIterable, Sendable {
    case queued
    case transcribing
    case ocr
    case extracting
    case generating
    case creatorReview      // suggestions ready; INERT until the creator confirms
    case confirmed          // creator accepted a subset; only then may anything publish
    case discarded
    case failed
}

enum CopilotStageKind: String, Codable, CaseIterable, Sendable {
    case transcription
    case ocr
    case extraction
    case generation
    case creatorReview
}

// MARK: - Suggested artifacts (each inert + confidence-scored)

struct SuggestedChapter: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let startSeconds: Double
    let endSeconds: Double
    let summary: String
    let confidence: Double      // 0...1, coarse, never displayed as a number
    let confirmed: Bool         // false until the creator accepts it
}

struct ClipRef: Codable, Identifiable, Sendable {
    let id: String
    let sourceJobId: String
    let startSeconds: Double
    let endSeconds: Double
    let label: String
    let scriptureRefs: [String]
    let confidence: Double
    let confirmed: Bool
}

struct DiscussionQuestion: Codable, Identifiable, Sendable {
    let id: String
    let prompt: String
    let scriptureRefs: [String]
    let confidence: Double
    let confirmed: Bool
}

struct SuggestedCaption: Codable, Identifiable, Sendable {
    let id: String
    let language: String        // BCP-47, e.g. "en"
    let text: String
    let authenticityKind: CopilotAuthenticityKind  // disclosed on publish
    let confidence: Double
    let confirmed: Bool
}

// MARK: - The job document (never auto-published)

struct CopilotJob: Codable, Identifiable, Sendable {
    let jobId: String
    let ownerId: String
    let testimonyId: String?         // links to a Testimony once confirmed; nil while inert
    let sourceMediaJobId: String     // the creatorJobs id transcribe/subtitle CFs operate on
    let state: CopilotJobState
    let stage: CopilotStageKind?
    let progress: Double             // 0...1
    let suggestedChapters: [SuggestedChapter]
    let suggestedClips: [ClipRef]
    let suggestedQuestions: [DiscussionQuestion]
    let suggestedCaptions: [SuggestedCaption]
    let verseRefs: [String]
    let flagEnabled: Bool
    let autoPublished: Bool          // CP-I1 structural guarantee: always false
    let createdAtUTC: Double
    let updatedAtUTC: Double
    let error: String?

    var id: String { jobId }
}

// MARK: - Confirmation payload (the ONLY path that lets anything publish)

struct CopilotConfirmation: Codable, Sendable {
    let jobId: String
    let ownerId: String
    let acceptedChapterIds: [String]
    let acceptedClipIds: [String]
    let acceptedQuestionIds: [String]
    let acceptedCaptionIds: [String]
    let confirmedAtUTC: Double
}

// MARK: - Fail-closed helpers (mirror the TS factories)

extension CopilotJob {
    static func empty(
        jobId: String,
        ownerId: String,
        sourceMediaJobId: String,
        flagEnabled: Bool,
        nowUTC: Double
    ) -> CopilotJob {
        CopilotJob(
            jobId: jobId,
            ownerId: ownerId,
            testimonyId: nil,
            sourceMediaJobId: sourceMediaJobId,
            state: .queued,
            stage: nil,
            progress: 0,
            suggestedChapters: [],
            suggestedClips: [],
            suggestedQuestions: [],
            suggestedCaptions: [],
            verseRefs: [],
            flagEnabled: flagEnabled,
            autoPublished: false,
            createdAtUTC: nowUTC,
            updatedAtUTC: nowUTC,
            error: nil
        )
    }

    /// Nothing publishes from a non-confirmed job. Structural guard, not model judgment.
    var mayPublishArtifact: Bool {
        state == .confirmed && autoPublished == false
    }
}

// testimonyCopilotContracts.ts
// ADDITIVE to the FROZEN testimony.ts — do NOT edit testimony.ts.
//
// ARISE / OUTPOUR Creator Co-Pilot contracts. Everything here is INERT until the
// creator confirms (state === "creatorReview" -> "confirmed"). No suggestion ever
// auto-publishes. AI-generated captions are disclosed as AuthenticityKind
// "ai_assisted_captions". The child-safety hash hook is NEVER flag-gated and is
// fail-closed elsewhere in the GUARDIAN pre-publish chain; this contract carries no
// detection logic.
//
// Invariants:
//  CP-I1  No artifact leaves the co-pilot without an explicit creator confirmation.
//  CP-I2  Every machine-produced artifact carries a coarse `confidence` (0..1, never displayed
//         as a public number) and is `confirmed: false` until the creator accepts it.
//  CP-I3  Flag OFF (testimonyCopilotEnabled) => orchestrator does not run; no job is created.
//  CP-I4  Captions are disclosed as AuthenticityKind "ai_assisted_captions" on publish.
//  CP-I5  Pipeline reuses existing transcribe/subtitle CFs by reference; it never re-implements them.

// MARK: - Disclosed authenticity kind (mirrors AuthenticityKind raw values in SocialOSModels.swift)

export type CopilotAuthenticityKind =
    | "ai_assisted_captions"
    | "ai_assisted_translation"
    | "transcript_approved";

// MARK: - Job state machine

export type CopilotJobState =
    | "queued"
    | "transcribing"
    | "ocr"
    | "extracting"
    | "generating"
    | "creatorReview"   // suggestions ready; INERT until the creator confirms
    | "confirmed"       // creator accepted a subset; only then may anything publish
    | "discarded"       // creator rejected; nothing publishes
    | "failed";

export type CopilotStageKind =
    | "transcription"
    | "ocr"
    | "extraction"
    | "generation"
    | "creatorReview";

// MARK: - Suggested artifacts (each inert + confidence-scored)

export interface SuggestedChapter {
    readonly id: string;
    readonly title: string;
    readonly startSeconds: number;
    readonly endSeconds: number;
    readonly summary: string;
    readonly confidence: number;   // 0..1, coarse, never displayed as a number
    readonly confirmed: boolean;   // false until the creator accepts it
}

export interface ClipRef {
    readonly id: string;
    readonly sourceJobId: string;
    readonly startSeconds: number;
    readonly endSeconds: number;
    readonly label: string;
    readonly scriptureRefs: string[]; // e.g. ["John 3:16"] — surfaced for creator review only
    readonly confidence: number;
    readonly confirmed: boolean;
}

export interface DiscussionQuestion {
    readonly id: string;
    readonly prompt: string;
    readonly scriptureRefs: string[];
    readonly confidence: number;
    readonly confirmed: boolean;
}

export interface SuggestedCaption {
    readonly id: string;
    readonly language: string;       // BCP-47, e.g. "en"
    readonly text: string;
    readonly authenticityKind: CopilotAuthenticityKind; // disclosed on publish
    readonly confidence: number;
    readonly confirmed: boolean;
}

// MARK: - The job document (never auto-published)

export interface CopilotJob {
    readonly jobId: string;
    readonly ownerId: string;
    readonly testimonyId: string | null; // links to a Testimony doc once confirmed; null while inert
    readonly sourceMediaJobId: string;    // the creatorJobs id the transcribe/subtitle CFs operate on
    readonly state: CopilotJobState;
    readonly stage: CopilotStageKind | null;
    readonly progress: number;            // 0..1
    readonly suggestedChapters: SuggestedChapter[];
    readonly suggestedClips: ClipRef[];
    readonly suggestedQuestions: DiscussionQuestion[];
    readonly suggestedCaptions: SuggestedCaption[];
    readonly verseRefs: string[];         // extraction output, review-only
    readonly flagEnabled: boolean;        // mirrors testimonyCopilotEnabled at job creation
    readonly autoPublished: false;        // CP-I1 structural guarantee: always false
    readonly createdAtUTC: number;
    readonly updatedAtUTC: number;
    readonly error: string | null;
}

// MARK: - Confirmation payload (the ONLY path that lets anything publish)

export interface CopilotConfirmation {
    readonly jobId: string;
    readonly ownerId: string;
    readonly acceptedChapterIds: string[];
    readonly acceptedClipIds: string[];
    readonly acceptedQuestionIds: string[];
    readonly acceptedCaptionIds: string[];
    readonly confirmedAtUTC: number;
}

// MARK: - Fail-closed factories

export function emptyCopilotJob(
    jobId: string,
    ownerId: string,
    sourceMediaJobId: string,
    flagEnabled: boolean,
    nowUTC: number,
): CopilotJob {
    return {
        jobId,
        ownerId,
        testimonyId: null,
        sourceMediaJobId,
        state: "queued",
        stage: null,
        progress: 0,
        suggestedChapters: [],
        suggestedClips: [],
        suggestedQuestions: [],
        suggestedCaptions: [],
        verseRefs: [],
        flagEnabled,
        autoPublished: false,
        createdAtUTC: nowUTC,
        updatedAtUTC: nowUTC,
        error: null,
    };
}

// Nothing publishes from a non-confirmed job. This is a structural guard, not model judgment.
export function mayPublishArtifact(job: CopilotJob): boolean {
    return job.state === "confirmed" && job.autoPublished === false;
}

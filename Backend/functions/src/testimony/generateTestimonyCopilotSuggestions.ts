// generateTestimonyCopilotSuggestions.ts
// ARISE / OUTPOUR Creator Co-Pilot orchestrator (SKELETON).
//
// Region: us-east1 (staged in the deploy runbook; NOT deployed by an agent).
// Pipeline: transcription -> ocr -> extraction -> generation -> creatorReview.
// The job is stored and NEVER auto-published — it parks at "creatorReview" until the
// creator confirms a subset of suggestions via a separate confirmation callable/UI.
//
// This function REUSES the existing transcribe/subtitle CFs (transcribeMedia,
// generateSubtitleTrack) BY REFERENCE — it does not re-implement transcription or
// subtitling. It composes their outputs into inert, confidence-scored suggestions.
//
// Gating: testimonyCopilotEnabled (Remote Config: testimony_copilot_enabled, default OFF).
// Flag OFF => the orchestrator refuses to run (CP-I3). The child-safety hash hook is
// handled by the GUARDIAN pre-publish chain and is never gated here.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {
    CopilotJob,
    CopilotJobState,
    CopilotStageKind,
    emptyCopilotJob,
} from "./testimonyCopilotContracts";

// Remote Config key — fail-closed default OFF.
const FLAG_KEY = "testimony_copilot_enabled";

async function isCopilotEnabled(): Promise<boolean> {
    try {
        const template = await admin.remoteConfig().getTemplate();
        const param = template.parameters[FLAG_KEY];
        const value = (param?.defaultValue as { value?: string } | undefined)?.value;
        return value === "true";
    } catch {
        // Fail-closed: any error reading the flag => treat as OFF.
        return false;
    }
}

function jobRef(ownerId: string, jobId: string): FirebaseFirestore.DocumentReference {
    return admin
        .firestore()
        .collection("users")
        .doc(ownerId)
        .collection("testimonyCopilotJobs")
        .doc(jobId);
}

async function advance(
    ownerId: string,
    jobId: string,
    state: CopilotJobState,
    stage: CopilotStageKind | null,
    progress: number,
): Promise<void> {
    await jobRef(ownerId, jobId).set(
        { state, stage, progress, updatedAtUTC: Date.now() },
        { merge: true },
    );
}

export const generateTestimonyCopilotSuggestions = onCall(
    { region: "us-east1" },
    async (request): Promise<{ ok: boolean; jobId: string; state: CopilotJobState }> => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Must be signed in.");
        }
        if (!request.app) {
            throw new HttpsError("failed-precondition", "App Check required.");
        }

        const flagEnabled = await isCopilotEnabled();
        if (!flagEnabled) {
            // CP-I3: flag OFF => no job is created, nothing runs.
            throw new HttpsError("failed-precondition", "Testimony Co-Pilot is disabled.");
        }

        const data = request.data as { sourceMediaJobId?: unknown } | undefined;
        const ownerId = request.auth.uid;
        const sourceMediaJobId = String(data?.sourceMediaJobId ?? "");
        if (!sourceMediaJobId) {
            throw new HttpsError("invalid-argument", "Missing sourceMediaJobId.");
        }

        const now = Date.now();
        const jobId = jobRef(ownerId, "_").parent.doc().id;
        const job: CopilotJob = emptyCopilotJob(jobId, ownerId, sourceMediaJobId, true, now);
        await jobRef(ownerId, jobId).set(job, { merge: true });

        try {
            // Stage 1 — transcription. REUSE the existing transcribeMedia CF by reference
            // (the client invokes transcribeMedia against `sourceMediaJobId`; we read its
            // transcript output here). No re-implementation of speech-to-text.
            await advance(ownerId, jobId, "transcribing", "transcription", 0.2);
            // TODO(runbook): read transcript produced by transcribeMedia(sourceMediaJobId).

            // Stage 2 — OCR over on-screen text / slides.
            await advance(ownerId, jobId, "ocr", "ocr", 0.4);
            // TODO(runbook): OCR pass over keyframes; outputs feed extraction only.

            // Stage 3 — Berean extraction (themes + verse refs), review-only.
            await advance(ownerId, jobId, "extracting", "extraction", 0.6);
            // TODO(runbook): extract verseRefs/themes via Berean; store as inert suggestions.

            // Stage 4 — generation of suggested chapters / clips / discussion questions /
            // captions. Each artifact is confidence-scored and confirmed:false.
            // Captions are disclosed as AuthenticityKind "ai_assisted_captions".
            await advance(ownerId, jobId, "generating", "generation", 0.85);
            // TODO(runbook): reuse generateSubtitleTrack output for caption suggestions;
            //                build SuggestedChapter/ClipRef/DiscussionQuestion, all inert.

            // Stage 5 — park at creatorReview. CP-I1: nothing publishes here.
            await advance(ownerId, jobId, "creatorReview", "creatorReview", 1.0);

            return { ok: true, jobId, state: "creatorReview" };
        } catch (err) {
            // Fail-closed: any error => "failed", never auto-publish.
            await jobRef(ownerId, jobId).set(
                {
                    state: "failed" as CopilotJobState,
                    error: err instanceof Error ? err.message : "unknown",
                    updatedAtUTC: Date.now(),
                },
                { merge: true },
            );
            throw new HttpsError("internal", "Co-Pilot generation failed.");
        }
    },
);

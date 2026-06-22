/**
 * mediaMetadataPipeline.ts
 *
 * Phase 3: Provider-backed media metadata generation pipeline.
 *
 * EXPORTS
 * ───────
 * onPostCreatedGenerateMediaMetadata
 *   gen2 Firestore trigger on posts/{postId} — detects video media items,
 *   initialises mediaMeta docs, runs transcription + key-moment inference,
 *   and persists results. Respects userEditedMetadata merge rules.
 *
 * retryMediaGeneration
 *   Callable — allows client to retry a failed generation for a single
 *   media item. Accepts { postId, mediaId }.
 *
 * MERGE RULES (enforced here, not only on client)
 * ────────────────────────────────────────────────
 * - If mediaMeta/{mediaId}.userEditedMetadata == true → skip ALL generated writes.
 * - If captionTracks subcollection already has a doc with source == "userEdited" → skip caption write.
 * - If keyMoments subcollection already has any doc with source == "userEdited" → skip moment write.
 * - Generated results never overwrite authored content.
 *
 * DEGRADED MODE
 * ─────────────
 * - Missing OPENAI_API_KEY → captionsGenerationState = "failed", post unaffected.
 * - Transcription error    → captionsGenerationState = "failed", keyMoments unaffected.
 * - Key-moment error       → keyMomentsGenerationState = "failed", captions unaffected.
 * - Each media item fails independently.
 *
 * PROVIDER INTEGRATION POINTS
 * ───────────────────────────
 * - Transcription: transcriptionProvider.transcribeAudioBuffer()
 *   To swap provider: replace that function's implementation.
 * - Key moments:   keyMomentInference.inferKeyMomentsHeuristic()
 *                  + keyMomentInference.refineMomentLabelsWithClaude()
 *   To add ML model: replace inferKeyMomentsHeuristic or add a branch.
 */

import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import {
    openaiApiKey,
    transcribeAudioBuffer,
    TranscriptionProviderError,
    TranscriptionResult,
    faithContextPrompt,
} from "./transcriptionProvider";
import {
    anthropicApiKey,
    inferKeyMomentsHeuristic,
    refineMomentLabelsWithClaude,
    GeneratedKeyMoment,
} from "./keyMomentInference";

if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();
const storage = admin.storage();

// ─── Constants ────────────────────────────────────────────────────────────────

const SUPPORTED_VIDEO_MIME_TYPES = ["video/mp4", "video/quicktime", "video/m4v", "video/mpeg"];
const SUPPORTED_AUDIO_MIME_TYPES = ["audio/m4a", "audio/mpeg", "audio/wav", "audio/aac"];
const MIN_VIDEO_DURATION_SECS = 10; // don't transcribe clips shorter than 10 s

// ─── Trigger: onPostCreatedGenerateMediaMetadata ─────────────────────────────

export const onPostCreatedGenerateMediaMetadata = onDocumentCreated(
    {
        document: "posts/{postId}",
        secrets: [openaiApiKey, anthropicApiKey],
        timeoutSeconds: 540,    // 9 min max — long Whisper jobs
        memory: "512MiB",
    },
    async (event) => {
        const postId = event.params.postId;
        const data = event.data?.data();
        if (!data) return;

        const mediaItems: unknown[] = data.mediaItems ?? [];
        if (mediaItems.length === 0) return;

        const authorId: string = data.authorId ?? data.userId ?? "";

        // Process each media item independently so one failure doesn't block others
        await Promise.allSettled(
            mediaItems.map((item) => processMediaItem(postId, authorId, item as Record<string, unknown>))
        );
    }
);

// ─── Callable: retryMediaGeneration ──────────────────────────────────────────

export const retryMediaGeneration = onCall(
    {
        secrets: [openaiApiKey, anthropicApiKey],
        timeoutSeconds: 540,
        memory: "512MiB",
        enforceAppCheck: true,
    },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Auth required");
        }

        const {postId, mediaId} = request.data as {postId?: string; mediaId?: string};
        if (!postId || !mediaId) {
            throw new HttpsError("invalid-argument", "postId and mediaId required");
        }

        // Verify caller owns the post
        const postSnap = await db.collection("posts").doc(postId).get();
        if (!postSnap.exists) {
            throw new HttpsError("not-found", "Post not found");
        }
        const authorId: string = postSnap.data()?.authorId ?? postSnap.data()?.userId ?? "";
        if (authorId !== request.auth.uid) {
            throw new HttpsError("permission-denied", "Not your post");
        }

        const mediaItems: unknown[] = postSnap.data()?.mediaItems ?? [];
        const item = mediaItems.find(
            (m) => (m as Record<string, unknown>)["id"] === mediaId
        ) as Record<string, unknown> | undefined;

        if (!item) {
            throw new HttpsError("not-found", "Media item not found in post");
        }

        // Reset state so UI reflects retry attempt
        await db
            .collection("posts").doc(postId)
            .collection("mediaMeta").doc(mediaId)
            .set({
                captionsGenerationState: "queued",
                keyMomentsGenerationState: "queued",
                processingState: "processing",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});

        await processMediaItem(postId, authorId, item);
        return {ok: true};
    }
);

// ─── Pipeline core ────────────────────────────────────────────────────────────

async function processMediaItem(
    postId: string,
    authorId: string,
    item: Record<string, unknown>
): Promise<void> {
    const mediaId = String(item["id"] ?? "");
    const mediaType = String(item["type"] ?? "");
    const duration = Number(item["duration"] ?? 0);

    if (!mediaId || mediaType !== "video") return;
    if (duration > 0 && duration < MIN_VIDEO_DURATION_SECS) return;

    const mediaMetaRef = db.collection("posts").doc(postId)
        .collection("mediaMeta").doc(mediaId);

    // ── Check merge guard ──────────────────────────────────────────────────
    const existingMeta = await mediaMetaRef.get();
    if (existingMeta.exists && existingMeta.data()?.userEditedMetadata === true) {
        console.log(`[mediaMetadataPipeline] Skipping ${mediaId} — userEditedMetadata=true`);
        return;
    }

    // ── Initialise mediaMeta doc ───────────────────────────────────────────
    await mediaMetaRef.set({
        mediaId,
        authorId,
        type: mediaType,
        processingState: "processing",
        captionsGenerationState: "generating",
        keyMomentsGenerationState: "generating",
        userEditedMetadata: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    // ── Download video bytes ───────────────────────────────────────────────
    let audioBuffer: Buffer;
    try {
        audioBuffer = await downloadMediaFile(item);
    } catch (err) {
        console.error(`[mediaMetadataPipeline] Download failed for ${mediaId}:`, err);
        await mediaMetaRef.set({
            processingState: "failed",
            captionsGenerationState: "failed",
            keyMomentsGenerationState: "failed",
            generationError: String(err),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        return;
    }

    // ── Transcription ──────────────────────────────────────────────────────
    let transcript: TranscriptionResult | null = null;
    try {
        transcript = await transcribeAudioBuffer(
            audioBuffer,
            "video/mp4",
            "en",
            faithContextPrompt()
        );

        // Check caption merge guard before writing
        const existingCaptionGuard = await checkCaptionUserEditGuard(mediaMetaRef);
        if (!existingCaptionGuard) {
            await persistGeneratedCaptionTrack(mediaMetaRef, mediaId, transcript);
            await mediaMetaRef.set({
                captionsGenerationState: "ready",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
        } else {
            console.log(`[mediaMetadataPipeline] Caption write skipped for ${mediaId} — user-edited track exists`);
            await mediaMetaRef.set({
                captionsGenerationState: "ready",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
        }
    } catch (err) {
        const isConfigError = err instanceof TranscriptionProviderError &&
            err.code === "provider_not_configured";

        console.error(`[mediaMetadataPipeline] Transcription failed for ${mediaId}:`,
            isConfigError ? "OPENAI_API_KEY not configured" : err
        );
        await mediaMetaRef.set({
            captionsGenerationState: "failed",
            generationError: isConfigError
                ? "provider_not_configured"
                : "transcription_failed",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
    }

    // ── Key moment inference ───────────────────────────────────────────────
    try {
        // Check moment merge guard
        const existingMomentGuard = await checkKeyMomentUserEditGuard(mediaMetaRef);
        if (existingMomentGuard) {
            console.log(`[mediaMetadataPipeline] Moment write skipped for ${mediaId} — user-edited moments exist`);
            await mediaMetaRef.set({
                keyMomentsGenerationState: "ready",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
        } else {
            const effectiveTranscript: TranscriptionResult = transcript ?? {
                languageCode: "en",
                fullText: "",
                cues: [],
                durationSeconds: duration,
            };

            let moments = inferKeyMomentsHeuristic(effectiveTranscript);

            // Attempt Claude label refinement (best-effort, won't fail pipeline)
            const claudeKey = anthropicApiKey.value();
            if (claudeKey && moments.length > 0) {
                moments = await refineMomentLabelsWithClaude(moments, effectiveTranscript, claudeKey);
            }

            await persistGeneratedKeyMoments(mediaMetaRef, moments);
            await mediaMetaRef.set({
                keyMomentsGenerationState: moments.length > 0 ? "ready" : "failed",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
        }
    } catch (err) {
        console.error(`[mediaMetadataPipeline] Key moment inference failed for ${mediaId}:`, err);
        await mediaMetaRef.set({
            keyMomentsGenerationState: "failed",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
    }

    // ── Mark processing complete ───────────────────────────────────────────
    await mediaMetaRef.set({
        processingState: "ready",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
}

// ─── Firestore writers ────────────────────────────────────────────────────────

async function persistGeneratedCaptionTrack(
    mediaMetaRef: admin.firestore.DocumentReference,
    mediaId: string,
    transcript: TranscriptionResult
): Promise<void> {
    const trackId = `generated-${mediaId}`;
    const captionTrackRef = mediaMetaRef.collection("captionTracks").doc(trackId);

    const segments = transcript.cues.map((cue) => ({
        cueId: cue.cueId,
        startTime: cue.startTime,
        endTime: cue.endTime,
        text: cue.text,
    }));

    await captionTrackRef.set({
        captionTrackId: trackId,
        language: transcript.languageCode,
        source: "generated",
        selectedCaptionStyle: "minimal",
        displayByDefault: true,
        generatedTranscript: transcript.fullText,
        editedTranscript: null,
        segments,
        lastEditedAt: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

async function persistGeneratedKeyMoments(
    mediaMetaRef: admin.firestore.DocumentReference,
    moments: GeneratedKeyMoment[]
): Promise<void> {
    if (moments.length === 0) return;

    const batch = db.batch();
    for (const moment of moments) {
        const momentRef = mediaMetaRef.collection("keyMoments").doc(moment.momentId);
        batch.set(momentRef, {
            momentId: moment.momentId,
            time: moment.time,
            label: moment.label,
            kind: moment.kind,
            source: "generated",
            sortOrder: moment.sortOrder,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    await batch.commit();
}

// ─── Merge guards ─────────────────────────────────────────────────────────────

/** Returns true if a user-edited caption track already exists. */
async function checkCaptionUserEditGuard(
    mediaMetaRef: admin.firestore.DocumentReference
): Promise<boolean> {
    const snap = await mediaMetaRef
        .collection("captionTracks")
        .where("source", "==", "userEdited")
        .limit(1)
        .get();
    return !snap.empty;
}

/** Returns true if any user-authored key moment exists. */
async function checkKeyMomentUserEditGuard(
    mediaMetaRef: admin.firestore.DocumentReference
): Promise<boolean> {
    const snap = await mediaMetaRef
        .collection("keyMoments")
        .where("source", "==", "userEdited")
        .limit(1)
        .get();
    return !snap.empty;
}

// ─── File downloader ──────────────────────────────────────────────────────────

/**
 * Downloads video file bytes from Firebase Storage.
 * Accepts gs:// paths, Firebase Storage HTTPS URLs, or plain storage paths.
 */
async function downloadMediaFile(item: Record<string, unknown>): Promise<Buffer> {
    const urls = [
        item["originalURL"],
        item["url"],
        item["thumbnailURL"],
    ].filter((u) => typeof u === "string" && (u as string).length > 0) as string[];

    for (const url of urls) {
        try {
            const buffer = await fetchAudioableBuffer(url);
            if (buffer.length > 0) return buffer;
        } catch {
            // try next URL
        }
    }

    throw new Error("Could not download media file from any available URL");
}

async function fetchAudioableBuffer(url: string): Promise<Buffer> {
    if (url.startsWith("gs://")) {
        const filePath = url.replace(/^gs:\/\/[^/]+\//, "");
        const [contents] = await storage.bucket().file(filePath).download();
        return contents;
    }

    if (url.includes("firebasestorage.googleapis.com") || url.startsWith("https://")) {
        const parsedURL = new URL(url);
        const rawPath = parsedURL.pathname.split("/o/")[1]?.split("?")[0];
        if (rawPath) {
            const filePath = decodeURIComponent(rawPath);
            try {
                const [contents] = await storage.bucket().file(filePath).download();
                return contents;
            } catch {
                // Fall through to direct HTTP fetch
            }
        }

        // Direct HTTP download
        const response = await fetch(url);
        if (!response.ok) throw new Error(`HTTP ${response.status} fetching ${url}`);
        return Buffer.from(await response.arrayBuffer());
    }

    throw new Error(`Unsupported URL scheme: ${url}`);
}

// ─── Utility ──────────────────────────────────────────────────────────────────

function isSupportedMediaMime(mimeType: string): boolean {
    return (
        SUPPORTED_VIDEO_MIME_TYPES.includes(mimeType) ||
        SUPPORTED_AUDIO_MIME_TYPES.includes(mimeType)
    );
}

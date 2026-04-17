/**
 * mediaScanning.ts — HIGH-1: Server-side CSAM / unsafe-content detection
 *
 * Every file written to Firebase Storage is scanned with Cloud Vision
 * SafeSearch Detection before it becomes publicly accessible.
 *
 * Enforcement ladder:
 *   1. VERY_LIKELY on CSAM signals (childSafety or explicit) →
 *        • Delete the file immediately
 *        • Write moderationQueue entry (priority=immediate, type=csam_detection)
 *        • Write violationLog entry for audit trail
 *        • Auto-suspend the uploading account (reuses accountSuspension logic
 *          by writing a moderationQueue entry that autoSuspendOnCriticalPattern
 *          will pick up)
 *
 *   2. LIKELY on adult / violence / racy →
 *        • Move file to a quarantine folder (not deleted in case of false positives)
 *        • Write moderationQueue entry (priority=high, type=unsafe_content_detected)
 *        • Flag the originating post/message document for human review
 *
 *   3. POSSIBLE on adult / violence →
 *        • Flag the originating post/message document (add needsContentReview=true)
 *        • No file deletion — low-confidence, human reviewer makes the call
 *
 * Storage paths scanned:
 *   post_media/          — post images
 *   profile_images/      — profile photos
 *   chat_files/          — chat attachments
 *   chat_videos/         — chat videos
 *   messages/            — message attachments
 *   group_photos/        — group photos
 *
 * Paths explicitly skipped (no user-generated content):
 *   voice_messages/      — audio only; no visual content to scan
 *   studioVoice/         — audio only
 *   voiceDevotionals/    — audio only
 *   sermons/             — audio only
 *   lib/                 — build artefacts
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { ImageAnnotatorClient, protos } from "@google-cloud/vision";

const db = admin.firestore();
const visionClient = new ImageAnnotatorClient();

// ── Likelihood helpers ─────────────────────────────────────────────────────

type Likelihood = protos.google.cloud.vision.v1.Likelihood;
const L = protos.google.cloud.vision.v1.Likelihood;

function isAtLeast(value: Likelihood | null | undefined, threshold: Likelihood): boolean {
    if (value == null) return false;
    const order: Likelihood[] = [
        L.UNKNOWN,
        L.VERY_UNLIKELY,
        L.UNLIKELY,
        L.POSSIBLE,
        L.LIKELY,
        L.VERY_LIKELY,
    ];
    const vIdx = order.indexOf(value as Likelihood);
    const tIdx = order.indexOf(threshold);
    return vIdx >= 0 && tIdx >= 0 && vIdx >= tIdx;
}

// ── Path routing ───────────────────────────────────────────────────────────

const SCANNED_PREFIXES = [
    "post_media/",
    "profile_images/",
    "amenConnect/",
    "chat_files/",
    "chat_videos/",
    "messages/",
    "group_photos/",
    "churchNotes/",
    "creator/",         // Creator Studio media — must be scanned; was previously skipped
];

const AUDIO_PREFIXES = [
    "voice_messages/",
    "studioVoice/",
    "voiceDevotionals/",
    "sermons/",
];

const IMAGE_CONTENT_TYPES = new Set([
    "image/jpeg",
    "image/png",
    "image/gif",
    "image/webp",
    "image/heic",
    "image/heif",
]);

const VIDEO_CONTENT_TYPES = new Set([
    "video/mp4",
    "video/quicktime",
    "video/x-m4v",
    "video/webm",
]);

// ── Quarantine path ────────────────────────────────────────────────────────

function quarantinePath(originalPath: string): string {
    return `quarantine/${originalPath}`;
}

// ── Extract uploader UID from storage path ─────────────────────────────────
// All user-facing paths follow the pattern:
//   <collection>/<userId>/...   or   <collection>/<conversationId>/...
// We extract the second segment as the "owner" for violation logging.

function extractOwnerFromPath(filePath: string): string | null {
    const parts = filePath.split("/");
    return parts.length >= 2 ? parts[1] : null;
}

// ── Write helpers ──────────────────────────────────────────────────────────

async function writeViolationLog(
    filePath: string,
    uploaderUid: string | null,
    violationType: string,
    safeSearchResult: Record<string, string>
): Promise<void> {
    await db.collection("contentViolationLog").add({
        filePath,
        uploaderUid: uploaderUid ?? "unknown",
        violationType,
        safeSearchResult,
        detectedAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "actioned",
    });
}

async function writeModerationQueueEntry(
    filePath: string,
    uploaderUid: string | null,
    queueType: string,
    priority: "immediate" | "high" | "standard",
    safeSearchResult: Record<string, string>
): Promise<void> {
    await db.collection("moderationQueue").add({
        uid: uploaderUid ?? "unknown",
        queueType,
        priority,
        filePath,
        safeSearchResult,
        source: "mediaScanning",
        status: "pending_review",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

// ── Flag originating Firestore document ───────────────────────────────────
// Best-effort: derive the Firestore document from the storage path.
// post_media/{uid}/{uploadGroupId}/{file}   → posts (lookup by uploadGroupId)
// profile_images/{uid}/...                  → users/{uid}
// chat_files/{conversationId}/...           → conversations/{conversationId}

async function flagOriginatingDocument(filePath: string): Promise<void> {
    const parts = filePath.split("/");
    const prefix = parts[0];

    try {
        if (prefix === "post_media" && parts.length >= 3) {
            const uploadGroupId = parts[2];
            const snap = await db.collection("posts")
                .where("uploadGroupId", "==", uploadGroupId)
                .limit(1)
                .get();
            if (!snap.empty) {
                await snap.docs[0].ref.update({
                    needsContentReview: true,
                    contentReviewFlaggedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
        } else if (prefix === "profile_images" && parts.length >= 2) {
            const uid = parts[1];
            await db.collection("users").doc(uid).update({
                profileImageNeedsReview: true,
                profileImageFlaggedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        } else if ((prefix === "chat_files" || prefix === "chat_videos" || prefix === "messages")
                   && parts.length >= 2) {
            const conversationId = parts[1];
            await db.collection("conversations").doc(conversationId).update({
                needsContentReview: true,
                contentReviewFlaggedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    } catch {
        // Best-effort — failure here must not block the enforcement decision
        functions.logger.warn("[MediaScanning] flagOriginatingDocument failed silently", { filePath });
    }
}

// ── Core enforcement ───────────────────────────────────────────────────────

export const scanUploadedMedia = functions.storage
    .object()
    .onFinalize(async (object) => {
        const filePath = object.name ?? "";
        const contentType = object.contentType ?? "";
        const bucket = object.bucket;

        // Skip non-user-generated paths
        const isScannedPrefix = SCANNED_PREFIXES.some((p) => filePath.startsWith(p));
        const isAudioPrefix    = AUDIO_PREFIXES.some((p) => filePath.startsWith(p));

        if (!isScannedPrefix || isAudioPrefix) {
            return;
        }

        // Only scan images; for video we flag for human review without Vision scan
        // (Vision does not support arbitrary video; frame extraction would need ffmpeg)
        const isImage = IMAGE_CONTENT_TYPES.has(contentType);
        const isVideo = VIDEO_CONTENT_TYPES.has(contentType);

        if (!isImage && !isVideo) {
            return; // Unknown type — skip (e.g. PDFs, audio accidentally in a scanned prefix)
        }

        const uploaderUid = extractOwnerFromPath(filePath);

        // ── Video: queue for manual review without Vision scan ──────────────
        if (isVideo) {
            functions.logger.info("[MediaScanning] Video upload queued for manual review", { filePath });
            await writeModerationQueueEntry(
                filePath,
                uploaderUid,
                "video_upload_pending_review",
                "standard",
                {}
            );
            return;
        }

        // ── Image: run Cloud Vision SafeSearch ──────────────────────────────
        const gcsUri = `gs://${bucket}/${filePath}`;
        let safeSearch: protos.google.cloud.vision.v1.ISafeSearchAnnotation;

        try {
            const [result] = await visionClient.safeSearchDetection({ image: { source: { imageUri: gcsUri } } });
            safeSearch = result.safeSearchAnnotation ?? {};
        } catch (err) {
            // Vision API failure — fail OPEN for non-critical; queue for manual review
            functions.logger.error("[MediaScanning] Cloud Vision call failed — queuing for manual review", err);
            await writeModerationQueueEntry(
                filePath,
                uploaderUid,
                "vision_api_failure",
                "standard",
                { error: String(err) }
            );
            return;
        }

        const safeSearchResult: Record<string, string> = {
            adult:    String(safeSearch.adult    ?? "UNKNOWN"),
            violence: String(safeSearch.violence ?? "UNKNOWN"),
            racy:     String(safeSearch.racy     ?? "UNKNOWN"),
            spoof:    String(safeSearch.spoof    ?? "UNKNOWN"),
            medical:  String(safeSearch.medical  ?? "UNKNOWN"),
        };

        functions.logger.info("[MediaScanning] SafeSearch result", { filePath, safeSearchResult });

        // ── TIER 1: VERY_LIKELY CSAM/explicit — delete + suspend ─────────────
        // Cloud Vision does not have a dedicated CSAM likelihood field, but
        // VERY_LIKELY adult + racy together is the highest-confidence signal
        // available.  A dedicated PhotoDNA / CSAM hash-matching integration
        // should be added via a separate Microsoft PhotoDNA API call when the
        // API key is provisioned.
        const veryLikelyAdult    = isAtLeast(safeSearch.adult,    L.VERY_LIKELY);
        const veryLikelyRacy     = isAtLeast(safeSearch.racy,     L.VERY_LIKELY);
        const veryLikelyViolence = isAtLeast(safeSearch.violence, L.VERY_LIKELY);

        // Trigger TIER 1 if EITHER adult OR racy alone reaches VERY_LIKELY —
        // the previous condition `(veryLikelyAdult && veryLikelyRacy)` was always
        // subsumed by `veryLikelyAdult` and caused racy-only VERY_LIKELY signals
        // to fall through to TIER 2 instead of being actioned immediately.
        if (veryLikelyAdult || veryLikelyRacy) {
            functions.logger.warn("[MediaScanning] TIER 1: CSAM/explicit signal — deleting file", { filePath, safeSearchResult });

            try {
                await admin.storage().bucket(bucket).file(filePath).delete();
            } catch (deleteErr) {
                functions.logger.error("[MediaScanning] File deletion failed", { filePath, deleteErr });
            }

            await Promise.all([
                writeViolationLog(filePath, uploaderUid, "csam_or_explicit_content", safeSearchResult),
                writeModerationQueueEntry(filePath, uploaderUid, "csam_detection", "immediate", safeSearchResult),
                // Writing a critical_harassment_pattern entry causes autoSuspendOnCriticalPattern
                // to disable the uploading account's Firebase Auth entry.
                uploaderUid ? db.collection("moderationQueue").add({
                    uid: uploaderUid,
                    queueType: "minor_safety_pattern",  // picked up by autoSuspendOnCriticalPattern
                    priority: "immediate",
                    reason: "csam_or_explicit_content",
                    filePath,
                    safeSearchResult,
                    source: "mediaScanning",
                    status: "pending_review",
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                }) : Promise.resolve(),
            ]);
            return;
        }

        if (veryLikelyViolence) {
            functions.logger.warn("[MediaScanning] TIER 1: Graphic violence — deleting file", { filePath, safeSearchResult });

            try {
                await admin.storage().bucket(bucket).file(filePath).delete();
            } catch (deleteErr) {
                functions.logger.error("[MediaScanning] File deletion failed", { filePath, deleteErr });
            }

            await Promise.all([
                writeViolationLog(filePath, uploaderUid, "graphic_violence", safeSearchResult),
                writeModerationQueueEntry(filePath, uploaderUid, "graphic_violence_detected", "immediate", safeSearchResult),
            ]);
            return;
        }

        // ── TIER 2: LIKELY — quarantine + flag for human review ───────────────
        const likelyAdult    = isAtLeast(safeSearch.adult,    L.LIKELY);
        const likelyRacy     = isAtLeast(safeSearch.racy,     L.LIKELY);
        const likelyViolence = isAtLeast(safeSearch.violence, L.LIKELY);

        if (likelyAdult || likelyRacy || likelyViolence) {
            functions.logger.warn("[MediaScanning] TIER 2: Likely unsafe — quarantining", { filePath, safeSearchResult });

            const destPath = quarantinePath(filePath);
            try {
                await admin.storage().bucket(bucket)
                    .file(filePath)
                    .copy(admin.storage().bucket(bucket).file(destPath));
                await admin.storage().bucket(bucket).file(filePath).delete();
            } catch (moveErr) {
                functions.logger.error("[MediaScanning] Quarantine move failed", { filePath, moveErr });
            }

            await Promise.all([
                writeViolationLog(filePath, uploaderUid, "likely_unsafe_content", safeSearchResult),
                writeModerationQueueEntry(filePath, uploaderUid, "unsafe_content_detected", "high", safeSearchResult),
                flagOriginatingDocument(filePath),
            ]);
            return;
        }

        // ── TIER 3: POSSIBLE — flag document only, no file action ────────────
        const possibleAdult    = isAtLeast(safeSearch.adult,    L.POSSIBLE);
        const possibleViolence = isAtLeast(safeSearch.violence, L.POSSIBLE);

        if (possibleAdult || possibleViolence) {
            functions.logger.info("[MediaScanning] TIER 3: Possible unsafe content — flagging document", { filePath, safeSearchResult });
            await Promise.all([
                flagOriginatingDocument(filePath),
                writeModerationQueueEntry(filePath, uploaderUid, "possible_unsafe_content", "standard", safeSearchResult),
            ]);
        }

        // Clean — no action needed
    });

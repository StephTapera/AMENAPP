import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {requireAuthAndAppCheck} from "../amenAI/common";
import {enforceRateLimit} from "../rateLimit";

const db = getFirestore();

const MEDIA_SESSION_RATE_LIMIT = {name: "media_session_1hr", windowMs: 3_600_000, maxCalls: 20};
const MEDIA_REPORT_RATE_LIMIT = {name: "media_report_1hr", windowMs: 3_600_000, maxCalls: 10};

type SessionType = "morning_inspiration"|"friends_and_family"|"worship_and_music"|
  "learning_session"|"sermon_highlights"|"selah_reflection"|"testimonies"|
  "church_moments"|"encouragement"|"custom";

/** Creates a finite, intentional media session. No infinite autoplay. */
export const createMediaSession = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);

    const {sessionType = "custom", maxItems = 8, maxDurationSeconds = 900,
        communityIds = [], safetyMode = "gentle"} =
        (request.data ?? {}) as {
            sessionType?: SessionType; maxItems?: number;
            maxDurationSeconds?: number; communityIds?: string[]; safetyMode?: string;
        };

    if (maxItems < 1 || maxItems > 20) throw new HttpsError("invalid-argument", "maxItems must be 1–20.");
    if (maxDurationSeconds < 60 || maxDurationSeconds > 7200) {
        throw new HttpsError("invalid-argument", "maxDurationSeconds must be 60–7200.");
    }
    await enforceRateLimit(uid, [MEDIA_SESSION_RATE_LIMIT]);

    const ref = db.collection("users").doc(uid).collection("mediaSessions").doc();
    await ref.set({
        sessionId: ref.id, ownerUid: uid, sessionType,
        communityIds, itemIds: [],
        currentIndex: 0, status: "active",
        finiteQueue: true,          // always true — no infinite sessions
        maxItems, maxDurationSeconds,
        reflectionPromptShown: false,
        sourceSurface: "app", safetyMode,
        createdAt: FieldValue.serverTimestamp(),
        startedAt: FieldValue.serverTimestamp(),
    });

    return {sessionId: ref.id, checkpointRules: {checkpointAfterItems: 3, checkpointAfterMinutes: 8}};
});

/** Marks a media session as completed and records the final action. */
export const completeMediaSession = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    const {sessionId, finalAction = "completed"} = (request.data ?? {}) as {sessionId: string; finalAction?: string};
    if (!sessionId) throw new HttpsError("invalid-argument", "sessionId required.");

    const ref = db.collection("users").doc(uid).collection("mediaSessions").doc(sessionId);
    const snap = await ref.get();
    if (!snap.exists || snap.data()?.ownerUid !== uid) throw new HttpsError("not-found", "Session not found.");

    await ref.update({status: "completed", completedAt: FieldValue.serverTimestamp(), finalAction});
    return {ok: true, suggestedActions: ["reflect", "journal", "pray"]};
});

/** Saves media to a named queue (prayer_queue, church_notes, selah_tonight, etc.). */
export const saveToMediaQueue = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    const {postId, mediaId, queueType, note} =
        (request.data ?? {}) as {postId: string; mediaId: string; queueType: string; note?: string};

    const valid = ["watch_later","prayer_queue","church_notes","family_watch",
        "selah_tonight","sermon_study","testimony_archive"];
    if (!valid.includes(queueType)) throw new HttpsError("invalid-argument", "Invalid queueType.");
    if (!postId || !mediaId) throw new HttpsError("invalid-argument", "postId and mediaId required.");

    const postSnap = await db.collection("posts").doc(postId).get();
    if (!postSnap.exists) throw new HttpsError("not-found", "Post not found.");
    if (["rejected","removed"].includes(postSnap.data()?.moderationStatus ?? "")) {
        throw new HttpsError("failed-precondition", "Cannot queue a restricted post.");
    }

    await db.collection("users").doc(uid)
        .collection("mediaQueues").doc(queueType)
        .collection("items").doc(mediaId)
        .set({postId, mediaId, queueType, note: note ? note.slice(0, 500) : null,
            addedAt: FieldValue.serverTimestamp()});
    return {ok: true};
});

/** Updates playback progress. Progress is bounded and user-scoped. */
export const updateMediaProgress = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    const {postId, mediaId, progressSeconds, durationSeconds} =
        (request.data ?? {}) as {postId: string; mediaId: string; progressSeconds: number; durationSeconds: number};

    if (!postId || !mediaId) throw new HttpsError("invalid-argument", "postId and mediaId required.");
    if (typeof progressSeconds !== "number" || progressSeconds < 0) {
        throw new HttpsError("invalid-argument", "Invalid progressSeconds.");
    }
    if (typeof durationSeconds !== "number" || durationSeconds <= 0) {
        throw new HttpsError("invalid-argument", "Invalid durationSeconds.");
    }

    const clamped = Math.min(progressSeconds, durationSeconds);
    const percent = Math.round((clamped / durationSeconds) * 100);

    await db.collection("users").doc(uid).collection("mediaProgress").doc(mediaId)
        .set({mediaId, postId, progressSeconds: clamped, durationSeconds,
            percentComplete: percent, completed: percent >= 90,
            lastWatchedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {ok: true, percentComplete: percent};
});

/** Reports media — creates a moderation queue entry. */
export const reportMedia = onCall({enforceAppCheck: true}, async (request) => {
    const uid = await requireAuthAndAppCheck(request.auth, request.app);
    const {postId, mediaId, reason} =
        (request.data ?? {}) as {postId: string; mediaId?: string; reason: string};

    const validReasons = ["harmful_or_dangerous","harassment","sexual_content","graphic_content",
        "misinformation","spiritual_manipulation","exploitative_testimony",
        "child_safety","self_harm","synthetic_deception","spam","other"];
    if (!validReasons.includes(reason)) throw new HttpsError("invalid-argument", "Invalid reason.");
    if (!postId) throw new HttpsError("invalid-argument", "postId required.");

    await enforceRateLimit(uid, [MEDIA_REPORT_RATE_LIMIT]);

    const ref = db.collection("mediaModerationQueue").doc();
    await ref.set({reportId: ref.id, reporterUid: uid, postId,
        mediaId: mediaId ?? null, reason,
        status: "pending", createdAt: FieldValue.serverTimestamp()});
    return {reportId: ref.id};
});

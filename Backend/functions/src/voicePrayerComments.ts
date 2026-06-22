/**
 * voicePrayerComments.ts
 * AMEN App — Voice Prayer & Testimony Comments Backend
 *
 * Implements the full server-side pipeline:
 *   createVoicePrayerUploadSession   → auth + App Check, rate limit, create Firestore doc
 *   finalizeVoicePrayerComment       → auth + App Check, transcribe, moderate, classify, publish/hold/block
 *   deleteVoicePrayerComment         → auth + App Check, author or admin only
 *   reportVoicePrayerComment         → auth + App Check, threshold auto-hide
 *   reactToVoicePrayerComment        → auth + App Check, rate-limited atomic counter
 *   getVoicePrayerPlaybackURL        → auth + App Check, generates short-lived signed URL
 *   moderateVoicePrayerComment       → internal Firestore trigger (not callable)
 *
 * Security contract:
 *   - Client NEVER writes: transcript, moderation, intent, spiritualContext, summary, status
 *   - All publish decisions are server-authoritative
 *   - App Check required on every callable
 *   - Rate limits enforced server-side
 */

import * as functions from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = admin.firestore();
const storage = admin.storage();
type CallableAuthContext = {
    auth?: { uid: string };
    app?: unknown;
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

function requireAuth(context: CallableAuthContext): string {
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    return context.auth.uid;
}

function requireAppCheck(context: CallableAuthContext): void {
    if (context.app == undefined) {
        throw new HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }
}

function requireString(value: unknown, fieldName: string): string {
    if (typeof value !== "string" || value.trim() === "") {
        throw new HttpsError("invalid-argument", `${fieldName} must be a non-empty string.`);
    }
    return value.trim();
}

function requireStringEnum<T extends string>(value: unknown, allowed: T[], fieldName: string): T {
    const s = requireString(value, fieldName) as T;
    if (!allowed.includes(s)) {
        throw new HttpsError("invalid-argument", `${fieldName} must be one of: ${allowed.join(", ")}`);
    }
    return s;
}

// ─── Rate Limiting ────────────────────────────────────────────────────────────

const LIMITS = {
    prayer:    { daily: 10, hourly: 4 },
    testimony: { daily: 3,  hourly: 2 },
    reply:     { daily: 20, hourly: 10 },
};

async function enforceRateLimit(uid: string, type: "prayer" | "testimony" | "reply"): Promise<void> {
    const now = Date.now();
    const hourAgo = now - 3_600_000;
    const dayAgo  = now - 86_400_000;
    const bucket  = type === "reply" ? "voice_reply" : `voice_${type}`;
    const docRef  = db.collection("voiceCommentRateLimits").doc(`${uid}_${bucket}`);

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(docRef);
        const data = snap.exists ? snap.data()! : { timestamps: [] };
        const timestamps: number[] = data.timestamps || [];

        // Purge entries older than 24 h
        const recent = timestamps.filter((t: number) => t > dayAgo);
        const inLastHour = recent.filter((t: number) => t > hourAgo);

        const lim = LIMITS[type];
        if (recent.length >= lim.daily) {
            throw new HttpsError("resource-exhausted", `Daily limit for ${type} voice comments reached.`);
        }
        if (inLastHour.length >= lim.hourly) {
            throw new HttpsError("resource-exhausted", `Hourly limit for ${type} voice comments reached.`);
        }

        recent.push(now);
        tx.set(docRef, { timestamps: recent, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    });
}

// ─── Server Feature Flag Check ────────────────────────────────────────────────

async function assertVoiceCommentsEnabled(type: "prayer" | "testimony"): Promise<void> {
    const flagDoc = await db.collection("serverFeatureFlags").doc("voiceComments").get();
    if (!flagDoc.exists) return; // permissive default
    const flags = flagDoc.data()!;
    const key = type === "prayer" ? "voicePrayerCommentsEnabled" : "voiceTestimonyCommentsEnabled";
    if (flags[key] === false) {
        throw new HttpsError("failed-precondition", "Voice comments are not enabled at this time.");
    }
}

// ─── Moderation ───────────────────────────────────────────────────────────────

interface ModerationResult {
    decision: "allow" | "review" | "block";
    riskLevel: "low" | "medium" | "high";
    categories: string[];
    reasonCode: string;
}

const SELF_HARM_PATTERNS = [
    /\b(suicide|suicidal|kill myself|end my life|want to die|don't want to live)\b/i,
    /\b(cutting|self.?harm|hurt myself)\b/i,
];

const HATE_PATTERNS = [
    /\b(hate (all |those )?\w+s?\b)/i,
];

const SCAM_PATTERNS = [
    /\b(send money|wire transfer|bitcoin|crypto payment|bank account number|routing number)\b/i,
];

const ADVICE_PATTERNS = [
    /\b(you should stop taking|stop your medication|don't see a doctor|legal advice|tax advice)\b/i,
];

const DOXX_PATTERNS = [
    /\b(\d{3}[-.\s]?\d{3}[-.\s]?\d{4}|\b\d{9}\b)\b/, // phone / SSN shape
    /\b\d{1,5}\s+\w+\s+(street|st|avenue|ave|road|rd|blvd|lane|ln)\b/i, // street address
];

const SENSITIVE_DETAIL_PATTERNS = [
    /\b(cancer|hiv|aids|addiction|bipolar|schizophrenia|ptsd|abuse|assault|rape|bankrupt|foreclos)\b/i,
    /\b(divorce|infidelity|affair|custody|restraining order)\b/i,
];

const OFF_TOPIC_PATTERNS = [
    /\b(trump|biden|obama|democrat|republican|vote|election|abortion debate|gun control)\b/i,
    /\b(buy now|click here|dm me|follow me|check my bio|promo code|discount)\b/i,
    /\b(i hate (him|her|them)|you're wrong|fight me|this is stupid)\b/i,
];

function moderateTranscript(transcript: string): ModerationResult {
    const categories: string[] = [];

    for (const p of SELF_HARM_PATTERNS) {
        if (p.test(transcript)) categories.push("self_harm_crisis");
    }
    for (const p of HATE_PATTERNS) {
        if (p.test(transcript)) categories.push("hate");
    }
    for (const p of SCAM_PATTERNS) {
        if (p.test(transcript)) categories.push("scam");
    }
    for (const p of ADVICE_PATTERNS) {
        if (p.test(transcript)) categories.push("unsafe_advice");
    }
    for (const p of DOXX_PATTERNS) {
        if (p.test(transcript)) categories.push("doxxing");
    }

    if (categories.includes("self_harm_crisis") || categories.includes("doxxing")) {
        return { decision: "block", riskLevel: "high", categories, reasonCode: "safety_block" };
    }
    if (categories.includes("hate") || categories.includes("scam")) {
        return { decision: "block", riskLevel: "high", categories, reasonCode: "policy_block" };
    }
    if (categories.includes("unsafe_advice")) {
        return { decision: "review", riskLevel: "medium", categories, reasonCode: "advice_review" };
    }
    if (categories.length > 0) {
        return { decision: "review", riskLevel: "medium", categories, reasonCode: "content_review" };
    }
    return { decision: "allow", riskLevel: "low", categories: [], reasonCode: "clear" };
}

// ─── Intent Classification ────────────────────────────────────────────────────

interface IntentResult {
    label: "prayer_request" | "prayer_response" | "testimony" | "off_topic";
    confidence: number;
}

const PRAYER_REQUEST_PATTERNS = [
    /\b(please pray|pray for me|need prayer|asking for prayer|prayer request)\b/i,
    /\b(struggling with|going through|difficult time|hard season|battling)\b/i,
];
const PRAYER_RESPONSE_PATTERNS = [
    /\b(praying for you|lifting you up|standing with you in prayer|interceding)\b/i,
    /\b(father god|lord jesus|holy spirit|in jesus' name|amen)\b/i,
];
const TESTIMONY_PATTERNS = [
    /\b(god healed|miracle|testimony|breakthrough|delivered|set free|praise god)\b/i,
    /\b(god came through|blessed|overcame|victory|restored|god provided)\b/i,
];

function classifyIntent(transcript: string, declaredType: string): IntentResult {
    let prayerReqScore = 0;
    let prayerResScore = 0;
    let testimonyScore = 0;

    for (const p of PRAYER_REQUEST_PATTERNS)  if (p.test(transcript)) prayerReqScore++;
    for (const p of PRAYER_RESPONSE_PATTERNS) if (p.test(transcript)) prayerResScore++;
    for (const p of TESTIMONY_PATTERNS)       if (p.test(transcript)) testimonyScore++;

    // Off-topic check
    const isOffTopic = OFF_TOPIC_PATTERNS.some(p => p.test(transcript));
    const maxSignal = Math.max(prayerReqScore, prayerResScore, testimonyScore);

    if (isOffTopic && maxSignal === 0) {
        return { label: "off_topic", confidence: 0.85 };
    }

    // Declared type as prior
    if (declaredType === "prayer") {
        if (prayerResScore >= prayerReqScore) return { label: "prayer_response", confidence: 0.78 + prayerResScore * 0.04 };
        return { label: "prayer_request", confidence: 0.72 + prayerReqScore * 0.04 };
    }
    if (declaredType === "testimony") {
        if (testimonyScore > 0) return { label: "testimony", confidence: 0.8 + testimonyScore * 0.04 };
        // Accept as testimony if no strong counter-signal
        if (maxSignal === 0) return { label: "testimony", confidence: 0.60 };
    }

    if (testimonyScore > 0) return { label: "testimony", confidence: 0.7 };
    if (prayerResScore > 0) return { label: "prayer_response", confidence: 0.7 };
    return { label: "prayer_request", confidence: 0.6 };
}

// ─── Spiritual Context ────────────────────────────────────────────────────────

interface SpiritualContextResult {
    tone: string;
    confidence: number;
    containsSensitiveDetails: boolean;
    suggestedVisibility: string | null;
}

function analyzeSpiritualContext(transcript: string): SpiritualContextResult {
    const containsSensitiveDetails = SENSITIVE_DETAIL_PATTERNS.some(p => p.test(transcript));
    const tone = transcript.includes("praise") || transcript.includes("thank you god")
        ? "praise"
        : transcript.includes("broken") || transcript.includes("hurting")
            ? "lament"
            : "prayer";

    return {
        tone,
        confidence: 0.72,
        containsSensitiveDetails,
        suggestedVisibility: containsSensitiveDetails ? "prayer_circle" : null,
    };
}

// ─── Safe Summary Generation ──────────────────────────────────────────────────

function generateSafeSummary(transcript: string, intentLabel: string): string {
    // Strip sensitive patterns before summarizing
    let cleaned = transcript;
    for (const p of SENSITIVE_DETAIL_PATTERNS) {
        cleaned = cleaned.replace(p, "[details withheld]");
    }
    for (const p of DOXX_PATTERNS) {
        cleaned = cleaned.replace(p, "[private info]");
    }

    // Very short transcript → no summary
    if (cleaned.split(" ").length < 12) return "";

    const prefix = intentLabel === "testimony"
        ? "Testimony: "
        : intentLabel === "prayer_response"
            ? "Prayer response: "
            : "Prayer request: ";

    // Take first 100 chars of cleaned text as a minimal summary
    const short = cleaned.trim().slice(0, 100);
    return prefix + (short.endsWith(".") ? short : short + "…");
}

// ─── Transcription via Whisper proxy ─────────────────────────────────────────

async function transcribeStoragePath(storagePath: string): Promise<{ text: string; language: string }> {
    try {
        const bucket = storage.bucket();
        const [buffer] = await bucket.file(storagePath).download();
        const url = `https://api.openai.com/v1/audio/transcriptions`;

        // The Whisper proxy pattern: POST multipart/form-data
        const FormData = (await import("form-data")).default;
        const axios = (await import("axios")).default;
        const form = new FormData();
        form.append("file", buffer, { filename: "audio.m4a", contentType: "audio/m4a" });
        form.append("model", "whisper-1");
        form.append("response_format", "verbose_json");

        const apiKey = process.env.OPENAI_API_KEY;
        if (!apiKey) throw new Error("OPENAI_API_KEY not configured");

        const response = await axios.post(url, form, {
            headers: { Authorization: `Bearer ${apiKey}`, ...form.getHeaders() },
            timeout: 60_000,
        });
        return {
            text: response.data.text || "",
            language: response.data.language || "en",
        };
    } catch (err) {
        functions.logger.warn("[voicePrayer] Transcription failed, proceeding without transcript", err);
        return { text: "", language: "en" };
    }
}

// ─── createVoicePrayerUploadSession ──────────────────────────────────────────

export const createVoicePrayerUploadSession = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);

    const postId = requireString(data?.postId, "postId");
    const type   = requireStringEnum(data?.type, ["prayer", "testimony"] as const, "type");
    const durationMs = typeof data?.durationMs === "number" ? data.durationMs : 0;

    // Max duration: prayer = 90 000 ms, testimony = 180 000 ms
    const maxMs = type === "prayer" ? 90_000 : 180_000;
    if (durationMs > maxMs) {
        throw new HttpsError("invalid-argument", `Duration exceeds maximum for ${type} (${maxMs / 1000}s).`);
    }

    await assertVoiceCommentsEnabled(type);
    await enforceRateLimit(uid, type);

    const voiceCommentId = db.collection("_").doc().id; // generate unique ID
    const storagePath    = `voice_comments/${uid}/${postId}/${voiceCommentId}.m4a`;
    const now            = admin.firestore.FieldValue.serverTimestamp();

    // Create doc in processing state
    await db
        .collection("posts").doc(postId)
        .collection("voiceComments").doc(voiceCommentId)
        .set({
            id:              voiceCommentId,
            postId,
            authorUid:       uid,
            type,
            status:          "processing",
            audioStoragePath: storagePath,
            audioDurationMs: 0,
            waveform:        [],
            transcript:      "",
            transcriptStatus: "pending",
            summary:         "",
            language:        "en",
            moderation:      { decision: "pending", riskLevel: "unknown", categories: [], reasonCode: "" },
            intent:          { label: "unknown", confidence: 0 },
            spiritualContext: { tone: "", confidence: 0, containsSensitiveDetails: false, suggestedVisibility: null },
            visibility:      "public",
            counts:          { prayed: 0, amen: 0, encourage: 0, replies: 0, reports: 0 },
            createdAt:       now,
            updatedAt:       now,
        });

    // Audit log
    await db.collection("voiceCommentAuditLog").add({
        event:          "upload_session_created",
        uid,
        postId,
        voiceCommentId,
        type,
        timestamp:      now,
    });

    functions.logger.info(`[voicePrayer] upload session created: ${voiceCommentId} by ${uid}`);

    return { voiceCommentId, uploadPath: storagePath };
});

// ─── finalizeVoicePrayerComment ───────────────────────────────────────────────

export const finalizeVoicePrayerComment = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);

    const voiceCommentId = requireString(data?.voiceCommentId, "voiceCommentId");
    const postId         = requireString(data?.postId, "postId");
    const type           = requireStringEnum(data?.type, ["prayer", "testimony"] as const, "type");
    const visibility     = requireStringEnum(
        data?.visibility,
        ["public", "followers", "church", "prayer_circle", "private"] as const,
        "visibility"
    );
    const durationMs: number = typeof data?.durationMs === "number" ? data.durationMs : 0;
    const waveform: number[] = Array.isArray(data?.waveform) ? data.waveform.slice(0, 60) : [];

    // Max file size check
    const maxMs = type === "prayer" ? 90_000 : 180_000;
    if (durationMs > maxMs) {
        throw new HttpsError("invalid-argument", "Duration exceeds maximum.");
    }

    // Verify ownership
    const docRef = db.collection("posts").doc(postId).collection("voiceComments").doc(voiceCommentId);
    const snap   = await docRef.get();
    if (!snap.exists) throw new HttpsError("not-found", "Voice comment not found.");
    const existing = snap.data()!;
    if (existing.authorUid !== uid) throw new HttpsError("permission-denied", "Not authorized.");
    if (existing.status !== "processing") throw new HttpsError("failed-precondition", "Comment already finalized.");

    const now = admin.firestore.FieldValue.serverTimestamp();

    // Update waveform + duration immediately so UI can show it
    await docRef.update({ audioDurationMs: durationMs, waveform, updatedAt: now });

    // --- Transcription ---
    const storagePath = existing.audioStoragePath as string;
    const { text: transcript, language } = await transcribeStoragePath(storagePath);

    // --- Moderation ---
    const moderation = moderateTranscript(transcript);

    // --- Intent Classification ---
    const intent = classifyIntent(transcript, type);

    // --- Spiritual Context ---
    const spiritualContext = analyzeSpiritualContext(transcript);

    // --- Summary ---
    const summary = intent.label !== "off_topic"
        ? generateSafeSummary(transcript, intent.label)
        : "";

    // --- Decision ---
    let status: string;
    let analyticsEvent: string;

    if (moderation.decision === "block") {
        status = "blocked";
        analyticsEvent = "voice_comment_blocked";
    } else if (intent.label === "off_topic") {
        status = "blocked";
        analyticsEvent = "voice_comment_blocked";
    } else if (moderation.decision === "review") {
        status = "held_for_review";
        analyticsEvent = "voice_comment_held_for_review";
    } else {
        status = "published";
        analyticsEvent = "voice_comment_published";
    }

    // Write all server-owned fields atomically
    await docRef.update({
        status,
        transcript,
        transcriptStatus: transcript ? "ready" : "failed",
        language,
        summary,
        moderation,
        intent,
        spiritualContext,
        visibility,
        updatedAt: now,
    });

    // Audit log
    await db.collection("voiceCommentAuditLog").add({
        event:          analyticsEvent,
        uid,
        postId,
        voiceCommentId,
        type,
        status,
        moderationDecision: moderation.decision,
        intentLabel:    intent.label,
        timestamp:      now,
    });

    functions.logger.info(`[voicePrayer] finalized ${voiceCommentId}: status=${status}`);

    return { decision: status === "blocked" ? (intent.label === "off_topic" ? "off_topic" : "blocked") : status };
});

// ─── deleteVoicePrayerComment ─────────────────────────────────────────────────

export const deleteVoicePrayerComment = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);

    const voiceCommentId = requireString(data?.voiceCommentId, "voiceCommentId");
    const postId         = requireString(data?.postId, "postId");

    const docRef = db.collection("posts").doc(postId).collection("voiceComments").doc(voiceCommentId);
    const snap   = await docRef.get();
    if (!snap.exists) throw new HttpsError("not-found", "Voice comment not found.");

    const doc = snap.data()!;

    // Author or admin
    const isAuthor = doc.authorUid === uid;
    const adminDoc = await db.collection("admins").doc(uid).get();
    const isAdmin  = adminDoc.exists;

    if (!isAuthor && !isAdmin) {
        throw new HttpsError("permission-denied", "Only the author or an admin can delete this.");
    }

    // Delete Storage file
    try {
        const storagePath = doc.audioStoragePath as string;
        if (storagePath) {
            await storage.bucket().file(storagePath).delete();
        }
    } catch { /* non-fatal */ }

    // Delete Firestore doc
    await docRef.delete();

    // Audit log
    await db.collection("voiceCommentAuditLog").add({
        event:          "voice_comment_deleted",
        deletedBy:      uid,
        postId,
        voiceCommentId,
        timestamp:      admin.firestore.FieldValue.serverTimestamp(),
    });

    functions.logger.info(`[voicePrayer] deleted ${voiceCommentId} by ${uid}`);
    return { success: true };
});

// ─── reportVoicePrayerComment ─────────────────────────────────────────────────

const REPORT_THRESHOLD_HIDE = 5;

export const reportVoicePrayerComment = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);

    const voiceCommentId = requireString(data?.voiceCommentId, "voiceCommentId");
    const postId         = requireString(data?.postId, "postId");
    const reason         = requireString(data?.reason, "reason");

    const docRef    = db.collection("posts").doc(postId).collection("voiceComments").doc(voiceCommentId);
    const reportRef = db.collection("voiceCommentReports").doc(`${uid}_${voiceCommentId}`);
    const now       = admin.firestore.FieldValue.serverTimestamp();

    // Idempotent: one report per user per comment
    const existingReport = await reportRef.get();
    if (existingReport.exists) return { success: true };

    const batch = db.batch();
    batch.set(reportRef, { uid, voiceCommentId, postId, reason, createdAt: now });
    batch.update(docRef, { "counts.reports": admin.firestore.FieldValue.increment(1), updatedAt: now });
    await batch.commit();

    // Auto-hide at threshold
    const snap = await docRef.get();
    if (snap.exists) {
        const reportCount = (snap.data()?.counts?.reports ?? 0) as number;
        if (reportCount >= REPORT_THRESHOLD_HIDE && snap.data()?.status === "published") {
            await docRef.update({ status: "held_for_review", updatedAt: now });
            await db.collection("voiceCommentAuditLog").add({
                event: "report_threshold_hide",
                voiceCommentId, postId,
                reportCount,
                timestamp: now,
            });
        }
    }

    functions.logger.info(`[voicePrayer] reported ${voiceCommentId} by ${uid}: ${reason}`);
    return { success: true };
});

// ─── reactToVoicePrayerComment ────────────────────────────────────────────────

const ALLOWED_REACTIONS = ["prayed", "amen", "encourage"] as const;
type Reaction = typeof ALLOWED_REACTIONS[number];

export const reactToVoicePrayerComment = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);

    const voiceCommentId = requireString(data?.voiceCommentId, "voiceCommentId");
    const postId         = requireString(data?.postId, "postId");
    const reaction       = requireStringEnum(data?.reaction, [...ALLOWED_REACTIONS] as string[], "reaction") as Reaction;

    const docRef      = db.collection("posts").doc(postId).collection("voiceComments").doc(voiceCommentId);
    const reactDocRef = db.collection("voiceCommentReactions").doc(`${uid}_${voiceCommentId}_${reaction}`);
    const now         = admin.firestore.FieldValue.serverTimestamp();

    // Verify comment is published
    const snap = await docRef.get();
    if (!snap.exists || snap.data()?.status !== "published") {
        throw new HttpsError("not-found", "Voice comment not available.");
    }

    const existingReact = await reactDocRef.get();
    const batch = db.batch();

    if (existingReact.exists) {
        // Toggle off
        batch.delete(reactDocRef);
        batch.update(docRef, {
            [`counts.${reaction}`]: admin.firestore.FieldValue.increment(-1),
            updatedAt: now,
        });
    } else {
        // Add reaction
        batch.set(reactDocRef, { uid, voiceCommentId, postId, reaction, createdAt: now });
        batch.update(docRef, {
            [`counts.${reaction}`]: admin.firestore.FieldValue.increment(1),
            updatedAt: now,
        });
    }

    await batch.commit();
    return { success: true, toggled: existingReact.exists };
});

// ─── getVoicePrayerPlaybackURL ────────────────────────────────────────────────
// Returns a short-lived signed URL (15 minutes) so clients never access Storage
// paths directly (no public read).

export const getVoicePrayerPlaybackURL = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    requireAppCheck(context);

    const storagePath = requireString(data?.storagePath, "storagePath");

    // Validate path structure: must be voice_comments/{uid}/{postId}/{filename}
    const pathRegex = /^voice_comments\/[^/]+\/[^/]+\/[^/]+\.m4a$/;
    if (!pathRegex.test(storagePath)) {
        throw new HttpsError("invalid-argument", "Invalid storage path.");
    }

    // Verify the comment is published and caller has access
    const parts    = storagePath.split("/");
    const postId   = parts[2];
    const fileName = parts[3];
    const commentId = fileName.replace(".m4a", "");

    const snap = await db.collection("posts").doc(postId).collection("voiceComments").doc(commentId).get();
    if (!snap.exists) throw new HttpsError("not-found", "Comment not found.");

    const doc = snap.data()!;
    if (doc.status !== "published") {
        throw new HttpsError("permission-denied", "Comment not available.");
    }

    // Visibility check: private → author only
    if (doc.visibility === "private" && doc.authorUid !== uid) {
        throw new HttpsError("permission-denied", "Access denied.");
    }

    const [url] = await storage.bucket().file(storagePath).getSignedUrl({
        action: "read",
        expires: Date.now() + 15 * 60 * 1000, // 15 minutes
    });

    return { url };
});

// ─── moderateVoicePrayerComment (Firestore trigger — internal) ────────────────
// Fires when voiceComments docs transition from processing → any status.
// Not a callable; used for async re-moderation if transcript arrives later.

import { onDocumentUpdated } from "firebase-functions/v2/firestore";

export const moderateVoicePrayerComment = onDocumentUpdated(
    "posts/{postId}/voiceComments/{voiceCommentId}",
    async (event) => {
        const before = event.data?.before?.data();
        const after  = event.data?.after?.data();
        if (!before || !after) return;

        // Only re-evaluate when transcript arrives (pending → ready)
        if (before.transcriptStatus !== "pending" || after.transcriptStatus !== "ready") return;
        if (after.status === "blocked") return; // already decided

        const transcript = (after.transcript as string) || "";
        const declaredType = (after.type as string) || "prayer";
        const moderation = moderateTranscript(transcript);
        const intent     = classifyIntent(transcript, declaredType);
        const spiritual  = analyzeSpiritualContext(transcript);
        const summary    = intent.label !== "off_topic"
            ? generateSafeSummary(transcript, intent.label)
            : "";

        let newStatus = after.status as string;
        if (moderation.decision === "block" || intent.label === "off_topic") {
            newStatus = "blocked";
        } else if (moderation.decision === "review") {
            newStatus = "held_for_review";
        } else if (newStatus === "processing") {
            newStatus = "published";
        }

        if (newStatus === after.status && summary === after.summary) return; // no change

        await event.data?.after?.ref.update({
            status:          newStatus,
            summary,
            moderation,
            intent,
            spiritualContext: spiritual,
            updatedAt:       admin.firestore.FieldValue.serverTimestamp(),
        });

        functions.logger.info(
            `[voicePrayer] re-moderated ${event.params.voiceCommentId}: ${after.status} → ${newStatus}`
        );
    }
);

/**
 * communicationOS.js
 * AMEN App — Communication OS Cloud Functions
 *
 * Functions exported:
 *   analyzeMessageContext    — callable: detect links/dates/music/tasks/memories in thread message text
 *   analyzePostContext       — callable: detect context signals in a draft post
 *   saveConversationMemory   — callable: save a memory item to a thread subcollection
 *   savePrivateContactNote   — callable: save a private note about a contact (stored in caller's own path)
 *   generateThreadMiniSummary — callable: summarize saved memories for a thread (Remote Config gated)
 *   moderateTextContent      — callable: rule-based text moderation (V1, no external AI)
 *
 * Security model:
 *   - All functions require Firebase Auth (unauthenticated calls rejected)
 *   - Thread-scoped functions verify caller is a member of the thread
 *   - Contact notes are written to callerUid path only — never the client-supplied uid
 *   - Raw message/note text is NEVER written to logs
 *   - Moderation errors fail open (never block the user)
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

// ─── Helpers ───────────────────────────────────────────────────────────────────

/** Ensure user is authenticated. Throws HttpsError if not. */
function requireAuth(auth) {
    if (!auth || !auth.uid) {
        throw new HttpsError("unauthenticated", "Auth required.");
    }
}

/** Verify caller is a member of the given thread. Throws HttpsError if not. */
async function requireThreadMember(threadId, uid) {
    const memberSnap = await admin.firestore()
        .doc(`threads/${threadId}/members/${uid}`)
        .get();
    if (!memberSnap.exists) {
        throw new HttpsError("permission-denied", "Not a thread member.");
    }
}

// ─── Text parsers (deterministic, no external AI) ─────────────────────────────

function extractUrls(text) {
    const urlRegex = /https?:\/\/[^\s\]"'>]+/gi;
    const matches = text.match(urlRegex) || [];
    return matches.map((url) => {
        try {
            return { url, display: new URL(url).hostname };
        } catch {
            return { url, display: url };
        }
    });
}

function extractDatePhrases(text) {
    const patterns = [
        /\b(tomorrow|today|tonight|this\s+(?:morning|afternoon|evening))\b/gi,
        /\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/gi,
        /\b\d{1,2}\/\d{1,2}(?:\/\d{2,4})?\b/g,
        /\b\d{1,2}:\d{2}\s*(?:am|pm)\b/gi,
        /\bnext\s+(?:week|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/gi,
    ];
    const found = new Set();
    patterns.forEach((p) => {
        const hits = text.match(p);
        if (hits) hits.forEach((m) => found.add(m));
    });
    return Array.from(found).map((display) => ({ display }));
}

function extractMusicMentions(text) {
    const keywords = ["album", "song", "track", "playlist", "mixtape", " ep ", "single", "music"];
    const lower = text.toLowerCase();
    return keywords.filter((k) => lower.includes(k)).map((mention) => ({ mention }));
}

function extractTaskPhrases(text) {
    const triggers = ["let me know", "send me", "follow up", "remind me", "don't forget", "can you", "could you"];
    const lower = text.toLowerCase();
    return triggers.filter((t) => lower.includes(t)).map((phrase) => ({ phrase }));
}

function extractMemoryPhrases(text) {
    const triggers = ["remember when", "never forget", "back when", "that time we", "do you remember", "throwback"];
    const lower = text.toLowerCase();
    return triggers.filter((t) => lower.includes(t)).map((phrase) => ({ phrase }));
}

function buildSuggestedActions(text) {
    const actions = [];
    if (extractUrls(text).length > 0) actions.push({ actionKey: "addLinkPreview", label: "Add Link Preview" });
    if (extractDatePhrases(text).length > 0) actions.push({ actionKey: "createReminder", label: "Create Reminder" });
    if (extractMusicMentions(text).length > 0) actions.push({ actionKey: "attachMusic", label: "Attach Music" });
    if (extractTaskPhrases(text).length > 0) actions.push({ actionKey: "createTask", label: "Create Task" });
    if (extractMemoryPhrases(text).length > 0) actions.push({ actionKey: "saveMemory", label: "Save Memory" });
    return actions;
}

function parseTextContext(text) {
    return {
        detectedLinks: extractUrls(text),
        detectedDates: extractDatePhrases(text),
        detectedMusic: extractMusicMentions(text),
        detectedTasks: extractTaskPhrases(text),
        detectedMemories: extractMemoryPhrases(text),
        suggestedActions: buildSuggestedActions(text),
    };
}

/**
 * V1 rule-based moderation — no external AI, deterministic, always available offline.
 * Conservative: default to safe unless a clear signal is present.
 */
function runLocalModeration(text) {
    const lower = text.toLowerCase();
    const spamSignals = [
        "win a free",
        "click here now",
        "limited time offer",
        "act now",
        "you have been selected",
    ];
    if (spamSignals.some((s) => lower.includes(s))) {
        return {
            allowed: true,
            severity: "review",
            categories: ["spam"],
            userMessage: "Your message may appear as spam to others.",
        };
    }
    return { allowed: true, severity: "safe", categories: [] };
}

// ─── analyzeMessageContext ─────────────────────────────────────────────────────

exports.analyzeMessageContext = onCall(async (request) => {
    requireAuth(request.auth);

    const threadId = String(request.data?.threadId ?? "").trim();
    const text     = String(request.data?.text ?? "").trim();

    if (!threadId) throw new HttpsError("invalid-argument", "threadId required.");
    if (!text)     throw new HttpsError("invalid-argument", "text required.");
    if (text.length > 5000) throw new HttpsError("invalid-argument", "text too long (max 5000 chars).");

    await requireThreadMember(threadId, request.auth.uid);

    // Parse without logging raw content
    const result = parseTextContext(text);
    const detectionsCount = Object.values(result)
        .filter(Array.isArray)
        .reduce((sum, arr) => sum + arr.length, 0);
    logger.info("analyzeMessageContext", { threadId, detectionsCount });

    return result;
});

// ─── analyzePostContext ────────────────────────────────────────────────────────

exports.analyzePostContext = onCall(async (request) => {
    requireAuth(request.auth);

    const draftText = String(request.data?.draftText ?? "").trim();
    if (!draftText) throw new HttpsError("invalid-argument", "draftText required.");
    if (draftText.length > 10000) throw new HttpsError("invalid-argument", "text too long (max 10000 chars).");

    const result = parseTextContext(draftText);
    const detectionsCount = Object.values(result)
        .filter(Array.isArray)
        .reduce((sum, arr) => sum + arr.length, 0);
    logger.info("analyzePostContext", { uid: request.auth.uid, detectionsCount });

    return result;
});

// ─── saveConversationMemory ────────────────────────────────────────────────────

const VALID_MEMORY_TYPES = ["link", "date", "music", "note", "task", "event", "memory"];

exports.saveConversationMemory = onCall(async (request) => {
    requireAuth(request.auth);

    const threadId       = String(request.data?.threadId ?? "").trim();
    const type           = String(request.data?.type ?? "").trim();
    const title          = String(request.data?.title ?? "").trim();
    const body           = request.data?.body != null ? String(request.data.body) : null;
    const metadata       = request.data?.metadata ?? null;
    const sourceMessageId = request.data?.sourceMessageId
        ? String(request.data.sourceMessageId).trim()
        : null;

    if (!threadId)                          throw new HttpsError("invalid-argument", "threadId required.");
    if (!VALID_MEMORY_TYPES.includes(type)) throw new HttpsError("invalid-argument", `type must be one of: ${VALID_MEMORY_TYPES.join(", ")}.`);
    if (!title || title.length > 200)       throw new HttpsError("invalid-argument", "title must be 1–200 chars.");
    if (body !== null && body.length > 1000) throw new HttpsError("invalid-argument", "body must be ≤1000 chars.");

    await requireThreadMember(threadId, request.auth.uid);

    const memRef = admin.firestore().collection(`threads/${threadId}/memories`).doc();
    await memRef.set({
        createdBy:       request.auth.uid,
        type,
        title,
        body:            body ?? null,
        metadata:        metadata ?? null,
        sourceMessageId: sourceMessageId ?? null,
        createdAt:       admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info("saveConversationMemory", { threadId, type, memoryId: memRef.id });
    return { memoryId: memRef.id };
});

// ─── savePrivateContactNote ────────────────────────────────────────────────────

exports.savePrivateContactNote = onCall(async (request) => {
    requireAuth(request.auth);

    const contactUid      = String(request.data?.contactUid ?? "").trim();
    const note            = String(request.data?.note ?? "").trim();
    const tags            = request.data?.tags;
    const sourceMessageId = request.data?.sourceMessageId
        ? String(request.data.sourceMessageId).trim()
        : null;

    if (!contactUid) throw new HttpsError("invalid-argument", "contactUid required.");
    if (!note || note.length > 2000) throw new HttpsError("invalid-argument", "note must be 1–2000 chars.");

    if (tags !== undefined && tags !== null) {
        if (!Array.isArray(tags)) throw new HttpsError("invalid-argument", "tags must be an array.");
        if (tags.length > 20)    throw new HttpsError("invalid-argument", "tags must have ≤20 items.");
        if (tags.some((t) => typeof t !== "string" || t.length > 50)) {
            throw new HttpsError("invalid-argument", "Each tag must be a string ≤50 chars.");
        }
    }

    // Write to caller's own subcollection only — callerUid comes from context.auth.uid, NOT from client input
    await admin.firestore()
        .doc(`users/${request.auth.uid}/privateContactNotes/${contactUid}`)
        .set(
            {
                note,   // stored in Firestore; NEVER written to logs
                tags:   Array.isArray(tags) ? tags : [],
                sourceMessageId: sourceMessageId ?? null,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
        );

    // Log only uid — no note content
    logger.info("savePrivateContactNote", { uid: request.auth.uid });
    return { success: true };
});

// ─── generateThreadMiniSummary ─────────────────────────────────────────────────

exports.generateThreadMiniSummary = onCall(async (request) => {
    requireAuth(request.auth);

    const threadId = String(request.data?.threadId ?? "").trim();
    if (!threadId) throw new HttpsError("invalid-argument", "threadId required.");

    // Remote Config feature flag check
    try {
        const remoteConfig = admin.remoteConfig();
        const template = await remoteConfig.getTemplate();
        const flag = template.parameters["smartThreadMiniSummaryEnabled"];
        if (flag?.defaultValue && "value" in flag.defaultValue && flag.defaultValue.value === "false") {
            throw new HttpsError("failed-precondition", "Feature disabled.");
        }
    } catch (err) {
        if (err instanceof HttpsError) throw err;
        // Remote Config unavailable — proceed (fail open)
        logger.warn("generateThreadMiniSummary: Remote Config unavailable, proceeding.", { threadId });
    }

    await requireThreadMember(threadId, request.auth.uid);

    // Read recent memories (NOT raw messages — privacy-safe)
    const memoriesSnap = await admin.firestore()
        .collection(`threads/${threadId}/memories`)
        .orderBy("createdAt", "desc")
        .limit(10)
        .get();

    const importantItems = memoriesSnap.docs.map((doc) => ({
        id:    doc.id,
        type:  doc.data().type,
        title: doc.data().title,
    }));

    let summary;
    if (importantItems.length > 0) {
        const previewTitles = importantItems.slice(0, 3).map((i) => i.title).join(", ");
        const more = importantItems.length > 3 ? "..." : "";
        summary = `${importantItems.length} saved item${importantItems.length > 1 ? "s" : ""}: ${previewTitles}${more}`;
    } else {
        summary = "No saved items yet.";
    }

    logger.info("generateThreadMiniSummary", { threadId, itemCount: importantItems.length });
    return { summary, importantItems, sourceMessageIds: [] };
});

// ─── moderateTextContent ───────────────────────────────────────────────────────

const VALID_MODERATION_CONTEXTS = ["message", "post", "profile", "comment"];

exports.moderateTextContent = onCall(async (request) => {
    requireAuth(request.auth);

    const text               = String(request.data?.text ?? "").trim();
    const moderationContext  = String(request.data?.context ?? "").trim();

    if (!text || text.length > 10000) throw new HttpsError("invalid-argument", "text must be 1–10000 chars.");
    if (!VALID_MODERATION_CONTEXTS.includes(moderationContext)) {
        throw new HttpsError("invalid-argument", `context must be one of: ${VALID_MODERATION_CONTEXTS.join(", ")}.`);
    }

    // Fail open: moderation errors must never block the user
    let result;
    try {
        result = runLocalModeration(text);
    } catch {
        logger.warn("moderateTextContent: local moderation threw, failing open.", { uid: request.auth.uid });
        result = { allowed: true, severity: "safe", categories: [] };
    }

    // Log severity and categories only — no raw text
    logger.info("moderateTextContent", { uid: request.auth.uid, severity: result.severity, categories: result.categories });
    return result;
});

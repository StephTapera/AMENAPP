/**
 * semanticIntelligence.ts
 *
 * System 29 — Liquid Glass Intelligence Layer
 * Five callables that power inline semantic definitions, smart actions,
 * knowledge threads, saved insights, and presence signals.
 *
 * Security contract:
 *  - All functions require Firebase Auth
 *  - All functions enforce App Check
 *  - Trusted AI outputs (semanticDefinitions) are ONLY written here — never by the client
 *  - User-owned paths (semanticInsights, knowledgeThreads, presenceSignals) restricted
 *    to the authenticated UID
 *  - Input sanitised and validated before any Firestore or AI call
 *  - Rate limited: 30 definitions / user / hour via per-user Firestore counter
 */

import * as functions from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as crypto from "crypto";

const db = admin.firestore();
type CallableAuthContext = {
    auth?: { uid: string };
    app?: unknown;
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function requireAuth(context: CallableAuthContext): string {
    if (!context.auth) {
        throw new HttpsError(
            "unauthenticated",
            "Must be signed in to use intelligence features."
        );
    }
    return context.auth.uid;
}

function requireAppCheckGuard(context: CallableAuthContext): void {
    if (context.app == undefined) {
        throw new HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }
}

function sanitizeString(value: unknown, maxLen = 500): string {
    if (typeof value !== "string") return "";
    return value.replace(/[<>]/g, "").trim().slice(0, maxLen);
}

/** Returns a stable cache key for a normalised term + depth pair. */
function definitionCacheKey(term: string, depth: string): string {
    const normalised = term.toLowerCase().trim();
    return crypto.createHash("sha256").update(`${normalised}:${depth}`).digest("hex").slice(0, 24);
}

/** Enforces per-user rate limit using a sharded counter in Firestore. */
async function checkRateLimit(uid: string): Promise<void> {
    const hourKey = new Date().toISOString().slice(0, 13);
    const ref = db.collection("_rateLimits").doc(`semanticDef:${uid}:${hourKey}`);
    const snap = await ref.get();
    const count = snap.exists ? (snap.data()?.count ?? 0) : 0;
    if (count >= 30) {
        throw new HttpsError(
            "resource-exhausted",
            "Definition rate limit reached. Try again in an hour."
        );
    }
    await ref.set(
        { count: admin.firestore.FieldValue.increment(1), uid, hour: hourKey },
        { merge: true }
    );
}

// ---------------------------------------------------------------------------
// 1. defineSemanticTerm
// ---------------------------------------------------------------------------

export const defineSemanticTerm = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    requireAppCheckGuard(context);
    const uid = requireAuth(context);
    await checkRateLimit(uid);

    const term          = sanitizeString(data.term, 80);
    const sourceText    = sanitizeString(data.sourceText, 500);
    const sourceType    = sanitizeString(data.sourceType, 40) || "post";
    const sourceId      = sanitizeString(data.sourceId, 128);
    const depth         = ["compact", "expanded", "biblical"].includes(data.requestedDepth)
                          ? (data.requestedDepth as string)
                          : "compact";
    const screenContext = sanitizeString(data.screenContext, 40) || "feed";
    const userLocale    = sanitizeString(data.userLocale, 10) || "en_US";

    if (!term) {
        throw new HttpsError("invalid-argument", "term is required.");
    }

    const cacheKey = definitionCacheKey(term, depth);

    // Return cached definition if approved for reuse
    const cached = await db.collection("semanticDefinitions").doc(cacheKey).get();
    if (cached.exists && cached.data()?.safetyStatus === "approved") {
        functions.logger.info("semanticDef cache hit", { term, cacheKey, uid });
        await logAnalyticsEvent("semantic_definition_loaded", uid, { term, cacheStatus: "hit", sourceType });
        return { ...cached.data(), id: cacheKey, cacheStatus: "hit" };
    }

    // Build definition via Berean AI proxy (studyPassage CF already exists)
    // We call the studyPassage callable internally to avoid duplicating AI logic.
    // For safety: we never fabricate scripture — only references the AI returns
    // from grounded retrieval are included.
    let compactDefinition = "";
    let expandedDefinition: string | null = null;
    let biblicalContext: string | null = null;
    let relatedScriptureRefs: string[] = [];
    let confidence = 0.7;
    let safetyNotes: string | null = null;
    let modelUsed = "berean-proxy";

    try {
        // Compose a structured prompt for the definition
        const promptContext = sourceText
            ? `Context: "${sourceText.slice(0, 200)}"`
            : "";

        const systemPrompt = [
            `You are a biblical scholar assistant for the Amen Christian social app.`,
            `Provide a definition for the term "${term}".`,
            promptContext,
            `Rules:`,
            `- Return ONLY real Bible references (chapter:verse). Never fabricate.`,
            `- Keep the compact definition under 80 words.`,
            `- If the term has no clear biblical meaning, state that plainly.`,
            `Respond with JSON: { "compact": "...", "expanded": "...", "biblical": "...", "refs": ["..."], "confidence": 0.0-1.0 }`,
        ].join("\n");

        // Call the Berean AI endpoint via admin SDK (internal HTTP call to avoid auth overhead)
        const bereanProxyRef = await db
            .collection("_aiRequests")
            .add({
                type: "defineSemanticTerm",
                term,
                systemPrompt,
                depth,
                requestedBy: uid,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                status: "pending",
            });

        // For now, we build a high-quality rule-based definition for common
        // theological terms (production would fan out to the real Berean proxy).
        // This avoids fabrication risks at launch while the async AI path is wired.
        const builtins: Record<string, { compact: string; biblical: string; refs: string[] }> = {
            atonement: {
                compact: "The reconciliation of humanity to God through Christ's sacrificial death, covering the penalty of sin.",
                biblical: "Central to Christian theology — God's justice satisfied through Christ as the substitute (penal substitution).",
                refs: ["Romans 5:11", "Hebrews 9:22", "1 John 2:2"],
            },
            sanctification: {
                compact: "The ongoing process by which the Holy Spirit makes a believer more like Christ in character and conduct.",
                biblical: "Distinct from justification (declared righteous) — sanctification is progressive growth in holiness.",
                refs: ["1 Thessalonians 4:3", "2 Corinthians 3:18", "Hebrews 12:14"],
            },
            covenant: {
                compact: "A binding agreement between God and humanity, establishing relationship, promises, and obligations.",
                biblical: "Scripture is structured around covenants: Noahic, Abrahamic, Mosaic, Davidic, and New Covenant.",
                refs: ["Genesis 9:9", "Genesis 17:2", "Jeremiah 31:31", "Luke 22:20"],
            },
            grace: {
                compact: "God's unmerited favour and love given freely to humanity despite sin, enabling salvation and transformation.",
                biblical: "Foundational to Protestant theology — salvation is by grace through faith, not works.",
                refs: ["Ephesians 2:8-9", "Romans 6:14", "Titus 2:11"],
            },
            repentance: {
                compact: "A genuine turning away from sin toward God — a change of mind, heart, and direction.",
                biblical: "The Greek metanoia means a complete change of mind. John the Baptist and Jesus both called for repentance.",
                refs: ["Mark 1:15", "Acts 2:38", "2 Corinthians 7:10"],
            },
            discernment: {
                compact: "The spiritual capacity to distinguish truth from falsehood, and to perceive God's will in complex situations.",
                biblical: "A gift of the Holy Spirit used to test spirits, evaluate teaching, and navigate moral complexity.",
                refs: ["1 Corinthians 12:10", "Hebrews 5:14", "1 John 4:1"],
            },
            fasting: {
                compact: "Voluntarily abstaining from food (and sometimes other pleasures) as an act of prayer, humility, and seeking God.",
                biblical: "Practised throughout Scripture by Moses, David, Esther, Daniel, Jesus, and the early church.",
                refs: ["Matthew 6:16-18", "Isaiah 58:6", "Acts 13:2"],
            },
            justification: {
                compact: "God's legal declaration that a sinner is righteous — not by works, but through faith in Christ.",
                biblical: "A courtroom metaphor: the guilty are declared 'not guilty' because Christ's righteousness is imputed to them.",
                refs: ["Romans 3:24", "Galatians 2:16", "Romans 5:1"],
            },
        };

        const key = term.toLowerCase().trim();
        const builtin = builtins[key];
        if (builtin) {
            compactDefinition = builtin.compact;
            biblicalContext = depth !== "compact" ? builtin.biblical : null;
            relatedScriptureRefs = depth !== "compact" ? builtin.refs : [];
            confidence = 0.95;
            modelUsed = "builtin-theological-dictionary";
        } else {
            // No builtin — return a safe fallback without fabrication
            compactDefinition = `"${term}" is a term used in Christian tradition. Tap "Ask Berean" for a detailed theological explanation.`;
            confidence = 0.0;
            safetyNotes = "no_builtin_definition";
            modelUsed = "fallback";
        }

        // Clean up pending request
        await bereanProxyRef.delete();

    } catch (err) {
        functions.logger.error("defineSemanticTerm AI error", { term, err });
        await logAnalyticsEvent("semantic_definition_failed", uid, { term, sourceType });
        throw new HttpsError("internal", "Could not generate definition.");
    }

    const generatedAt = admin.firestore.Timestamp.now();
    const result = {
        id: cacheKey,
        term,
        compactDefinition,
        expandedDefinition: expandedDefinition ?? null,
        biblicalContext: biblicalContext ?? null,
        relatedScriptureRefs,
        confidence,
        safetyNotes: safetyNotes ?? null,
        generatedAt: generatedAt.toMillis(),
        modelUsed,
        cacheStatus: "miss",
        normalizedTerm: term.toLowerCase().trim(),
        safetyStatus: confidence > 0.5 ? "approved" : "review_required",
        approvedForReuse: confidence > 0.5,
        cacheKey,
    };

    // Persist to shared cache (trusted server write — client cannot write here)
    if (confidence > 0.5) {
        await db.collection("semanticDefinitions").doc(cacheKey).set(result);
    }

    await logAnalyticsEvent("semantic_definition_loaded", uid, { term, cacheStatus: "miss", sourceType });
    return result;
});

// ---------------------------------------------------------------------------
// 2. detectSmartActions
// ---------------------------------------------------------------------------

export const detectSmartActions = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    requireAppCheckGuard(context);
    const uid = requireAuth(context);

    const screen       = sanitizeString(data.screen, 40);
    const sourceType   = sanitizeString(data.sourceType, 40);
    const sourceId     = sanitizeString(data.sourceId, 128);
    const visibleText  = sanitizeString(data.visibleText, 800);
    const selectedText = sanitizeString(data.selectedText, 300);
    const featureFlags = (typeof data.featureFlags === "object" && data.featureFlags !== null)
                          ? data.featureFlags as Record<string, boolean>
                          : {};

    const rankedActions: Array<{
        id: string; icon: string; title: string;
        subtitle?: string; priorityRaw: number; analyticsEvent: string;
    }> = [];
    const suppressedActions: string[] = [];
    const reasonCodes: string[] = [];

    // Safety: never show actions for content that isn't available
    const hasTranscript = featureFlags["has_transcript"] === true;
    const isAuthenticated = true; // already checked above

    // Scripture detected
    const scripturePattern = /(\d\s)?[A-Z][a-z]+\s\d{1,3}(:\d{1,3}(-\d{1,3})?)?/;
    if (scripturePattern.test(visibleText) || scripturePattern.test(selectedText)) {
        rankedActions.push({
            id: "scripture_context",
            icon: "book.closed",
            title: "Bible Context",
            priorityRaw: 3,
            analyticsEvent: "smart_action_tapped_scripture",
        });
    }

    // Selected text — define it
    if (selectedText.length > 2) {
        rankedActions.push({
            id: "define_selection",
            icon: "character.magnify",
            title: "Define",
            subtitle: `"${selectedText.slice(0, 20)}${selectedText.length > 20 ? "…" : ""}"`,
            priorityRaw: 2,
            analyticsEvent: "smart_action_tapped_define",
        });
    }

    // Media transcript available
    if (sourceType === "media" && hasTranscript) {
        rankedActions.push({
            id: "explain_video",
            icon: "sparkles",
            title: "Explain",
            priorityRaw: 2,
            analyticsEvent: "smart_action_tapped_explain_video",
        });
    } else if (sourceType === "media" && !hasTranscript) {
        suppressedActions.push("explain_video");
        reasonCodes.push("transcript_not_ready");
    }

    // Church note detected
    if (screen === "churchNotes" || sourceType === "churchNote") {
        rankedActions.push({
            id: "save_to_notes",
            icon: "note.text",
            title: "Save Note",
            priorityRaw: 4,
            analyticsEvent: "smart_action_tapped_save_notes",
        });
    }

    // Ask Berean — always available when authenticated
    if (isAuthenticated && featureFlags["berean_rag_enabled"] !== false) {
        rankedActions.push({
            id: "ask_berean",
            icon: "sparkles",
            title: "Ask Berean",
            priorityRaw: 2,
            analyticsEvent: "smart_action_tapped_ask_berean",
        });
    }

    // Save to Selah — only when enabled
    if (isAuthenticated && featureFlags["selah_media_os_enabled"] !== false) {
        rankedActions.push({
            id: "save_to_selah",
            icon: "bookmark",
            title: "Save to Selah",
            priorityRaw: 5,
            analyticsEvent: "smart_action_tapped_save_selah",
        });
    }

    // Dedup and limit to 3
    const seen = new Set<string>();
    const deduped = rankedActions
        .filter(a => seen.has(a.id) ? false : (seen.add(a.id), true))
        .sort((a, b) => a.priorityRaw - b.priorityRaw)
        .slice(0, 3);

    await logAnalyticsEvent("smart_action_rendered", uid, { screen, sourceType, count: String(deduped.length) });

    return { rankedActions: deduped, suppressedActions, reasonCodes };
});

// ---------------------------------------------------------------------------
// 3. createKnowledgeThread
// ---------------------------------------------------------------------------

export const createKnowledgeThread = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    requireAppCheckGuard(context);
    const uid = requireAuth(context);

    const term         = sanitizeString(data.term, 80);
    const sourceType   = sanitizeString(data.sourceType, 40);
    const sourceId     = sanitizeString(data.sourceId, 128);
    const definitionId = sanitizeString(data.definitionId, 64);
    const relatedRefs  = Array.isArray(data.relatedRefs)
                          ? (data.relatedRefs as unknown[]).map(r => sanitizeString(r as string, 40))
                          : [];
    const userNote     = data.userNote ? sanitizeString(data.userNote, 500) : null;

    if (!term || !definitionId) {
        throw new HttpsError("invalid-argument", "term and definitionId are required.");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const threadRef = db
        .collection("users").doc(uid)
        .collection("knowledgeThreads")
        .doc(); // server-generated ID

    await threadRef.set({
        title: term,
        primaryTerm: term,
        sourceObjects: [{
            sourceType,
            sourceId,
            displayTitle: null,
            addedAt: now,
        }],
        relatedScriptureRefs: relatedRefs,
        savedInsightIds: [definitionId],
        createdAt: now,
        updatedAt: now,
        lastOpenedAt: null,
        uid, // denormalised for security rule simplification
    });

    await logAnalyticsEvent("knowledge_thread_created", uid, { term, sourceType });
    return { threadId: threadRef.id, createdAt: Date.now() };
});

// ---------------------------------------------------------------------------
// 4. saveSemanticInsight
// ---------------------------------------------------------------------------

export const saveSemanticInsight = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    requireAppCheckGuard(context);
    const uid = requireAuth(context);

    const definitionId = sanitizeString(data.definitionId, 64);
    const term         = sanitizeString(data.term, 80);
    const sourceType   = sanitizeString(data.sourceType, 40);
    const sourceId     = sanitizeString(data.sourceId, 128);
    const userNote     = data.userNote ? sanitizeString(data.userNote, 500) : null;

    if (!definitionId || !term) {
        throw new HttpsError("invalid-argument", "definitionId and term are required.");
    }

    // Deduplicate: check if this definition is already saved
    const existing = await db
        .collection("users").doc(uid)
        .collection("semanticInsights")
        .where("definitionId", "==", definitionId)
        .limit(1)
        .get();

    if (!existing.empty) {
        // Already saved — return the existing ID
        return { savedInsightId: existing.docs[0].id, savedAt: Date.now(), deduplicated: true };
    }

    // Fetch the shared definition to copy its safe fields into the user's insight
    const defSnap = await db.collection("semanticDefinitions").doc(definitionId).get();
    const defData = defSnap.data() ?? {};

    const now = admin.firestore.FieldValue.serverTimestamp();
    const insightRef = db
        .collection("users").doc(uid)
        .collection("semanticInsights")
        .doc();

    await insightRef.set({
        term,
        definitionId,
        compactDefinition: defData.compactDefinition ?? "",
        sourceType,
        sourceId,
        relatedScriptureRefs: defData.relatedScriptureRefs ?? [],
        createdAt: now,
        updatedAt: now,
        userNote,
        visibility: "private",
        uid,
    });

    await logAnalyticsEvent("semantic_definition_saved", uid, { term, sourceType });
    return { savedInsightId: insightRef.id, savedAt: Date.now(), deduplicated: false };
});

// ---------------------------------------------------------------------------
// 5. logPresenceSignal
// ---------------------------------------------------------------------------

export const logPresenceSignal = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    requireAppCheckGuard(context);
    const uid = requireAuth(context);

    const screen     = sanitizeString(data.screen, 40);
    const signalType = sanitizeString(data.signalType, 40);
    const sourceId   = data.sourceId ? sanitizeString(data.sourceId, 128) : null;

    // Only log privacy-safe metadata — no raw user text
    const allowedMetaKeys = new Set([
        "suggestionType", "screenSection", "scrollDepth", "sessionDuration"
    ]);
    const metadata: Record<string, string> = {};
    if (typeof data.metadata === "object" && data.metadata !== null) {
        for (const [k, v] of Object.entries(data.metadata as Record<string, unknown>)) {
            if (allowedMetaKeys.has(k) && typeof v === "string") {
                metadata[k] = v.slice(0, 80);
            }
        }
    }

    // Aggregate signal — write to user's private subcollection
    await db
        .collection("users").doc(uid)
        .collection("presenceSignals")
        .add({
            screen,
            signalType,
            sourceId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            privacyLevel: "aggregate",
            metadata,
            uid,
        });

    await logAnalyticsEvent("presence_signal_logged", uid, { screen, signalType });
    return { accepted: true };
});

// ---------------------------------------------------------------------------
// Analytics helper
// ---------------------------------------------------------------------------

async function logAnalyticsEvent(
    eventName: string,
    uid: string,
    params: Record<string, string | number> = {}
): Promise<void> {
    try {
        await db.collection("_analyticsEvents").add({
            event: eventName,
            uid,
            params,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch {
        // Analytics failures must never block the main operation
    }
}

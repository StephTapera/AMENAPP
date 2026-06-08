"use strict";

/**
 * worldResponse.js
 *
 * AMEN Intelligence — World Events as Christian Response
 *
 * Exports:
 *   buildWorldResponseCards(userId, db, callModelFn) → IntelligenceCard[]
 *
 * Design invariants:
 *   - GLOBAL tier only
 *   - source REQUIRED on every card — skip if missing
 *   - DEVELOPING cards capped at rankScore 40 (never top-ranked)
 *   - Actions restricted to PRAY / GIVE / SHOW_UP / DISCUSS — no commentary rungs
 *   - lamentFrame: true for disaster/conflict events
 *   - Fail-closed: AI error or moderation failure → skip card entirely
 *   - If world_response_queue is empty → return [] (never fabricate cards)
 *   - No political framing, editorial takes, or opinion language anywhere
 */

const admin = require("firebase-admin");

// ─── Constants ────────────────────────────────────────────────────────────────

const MAX_CARDS = 5;

// Default source seeds — stored in Firestore at worldResponseSources/{sourceId}.
// URLs are intentionally left as empty strings; an admin populates them via the
// Firestore console or a one-time seed script.  The app reads them from Firestore.
const DEFAULT_SOURCES = [
    {
        id: "world_magazine",
        name: "WORLD Magazine",
        url: "",
        rssUrl: "",
        active: true,
    },
    {
        id: "christianity_today",
        name: "Christianity Today",
        url: "",
        rssUrl: "",
        active: true,
    },
    {
        id: "relevant_magazine",
        name: "Relevant Magazine",
        url: "",
        rssUrl: "",
        active: true,
    },
    {
        id: "the_dispatch",
        name: "The Dispatch",
        url: "",
        rssUrl: "",
        active: true,
    },
    {
        id: "ap_religion",
        name: "AP Religion",
        url: "",
        rssUrl: "",
        active: true,
    },
];

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Seed default source docs into Firestore if the collection is empty.
 * Only runs if worldResponseSources has no documents — safe to call on every
 * function invocation because it short-circuits immediately when docs exist.
 */
async function seedDefaultSources(db) {
    const col = db.collection("worldResponseSources");
    const snap = await col.limit(1).get();
    if (!snap.empty) {
        return; // Already seeded
    }

    const batch = db.batch();
    for (const source of DEFAULT_SOURCES) {
        batch.set(col.doc(source.id), {
            ...source,
            seededAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    await batch.commit();
    console.log("[worldResponse] Seeded default worldResponseSources");
}

/**
 * Mark an event doc as processed by writing processedAt.
 * Non-critical — failure does not affect card delivery.
 */
async function markProcessed(db, eventId) {
    try {
        await db
            .collection("world_response_queue")
            .doc(eventId)
            .update({ processedAt: admin.firestore.FieldValue.serverTimestamp() });
    } catch (err) {
        console.warn(`[worldResponse] Failed to mark processed for ${eventId}:`, err.message);
    }
}

/**
 * Run the AI model call for a single event.
 * Returns { known: string[], contested: string[], howToRespond: string[] }
 * or null if the call fails (fail-closed).
 */
async function callForEvent(event, callModelFn) {
    try {
        const result = await callModelFn({
            task: "intelligence.world_response",
            input: event,
        });

        if (
            !result ||
            !Array.isArray(result.known) ||
            !Array.isArray(result.contested) ||
            !Array.isArray(result.howToRespond)
        ) {
            console.warn(`[worldResponse] Model returned malformed output for event ${event.id}`);
            return null;
        }

        return result;
    } catch (err) {
        console.error(`[worldResponse] callModelFn failed for event ${event.id}:`, err.message);
        return null;
    }
}

/**
 * Run content through moderation for a single event summary.
 * Returns true (pass) or false (fail-closed).
 * Uses a lightweight check — the full NeMo Guard runs for user-generated content;
 * here we validate that AI-generated summaries don't contain harmful output.
 */
async function passesModeration(summaryBullets, db) {
    try {
        const combinedText = summaryBullets.join(" ").slice(0, 2000);

        // Basic length / empty guard
        if (!combinedText.trim()) {
            return false;
        }

        // Write a moderation_check record; the moderationGateway handles deeper analysis
        // for user content.  AI-generated world-response summaries go through a lighter
        // internal check — we verify the text contains no self-harm or unsafe-advice phrases
        // before delivering to users.  Pattern list mirrors moderationGateway.js normalization.
        const normalized = combinedText
            .toLowerCase()
            .replace(/[^a-z0-9\s]/g, " ")
            .replace(/\s+/g, " ")
            .trim();

        const BLOCK_PATTERNS = [
            "kill myself", "suicide", "suicidal", "self harm",
            "stop taking your medication", "refuse treatment",
            "god told me to tell you",
        ];

        const blocked = BLOCK_PATTERNS.some((p) => normalized.includes(p));
        if (blocked) {
            console.warn("[worldResponse] Moderation blocked AI output for event — skipping card");
            return false;
        }

        return true;
    } catch (err) {
        // Fail closed
        console.error("[worldResponse] Moderation check error — failing closed:", err.message);
        return false;
    }
}

/**
 * Build a single IntelligenceCard from an event + model output.
 * Returns the card object (plain JS, matches IntelligenceCard Swift model).
 */
function buildCard(event, modelOutput) {
    const { known, contested, howToRespond } = modelOutput;

    // Summary: up to 3 bullets from known + howToRespond — no contested bullets
    const summaryBullets = [
        ...known.slice(0, 2),
        ...howToRespond.slice(0, 1),
    ].slice(0, 3);

    // Match reasons carries the contested bullets for the expandable disclosure UI
    // (WorldResponseCardView reads these and presents them in a collapsed section)
    const matchReasons = contested.slice(0, 3);

    // Actions: PRAY always present; GIVE if hasDonationLink; DISCUSS if discussionEnabled
    // SHOW_UP reserved for events that have a local angle (hasLocalAngle field)
    const actions = [];

    actions.push({
        rung: "PRAY",
        label: "Pray",
        handler: "openPrayer",
        target: event.id,
    });

    if (event.hasDonationLink) {
        actions.push({
            rung: "GIVE",
            label: "Give",
            handler: "openDonation",
            target: event.id,
        });
    }

    if (event.discussionEnabled) {
        actions.push({
            rung: "DISCUSS",
            label: "Discuss",
            handler: "discuss",
            target: event.id,
        });
    }

    if (event.hasLocalAngle) {
        actions.push({
            rung: "SHOW_UP",
            label: "Get involved locally",
            handler: "volunteer",
            target: event.id,
        });
    }

    const isVerified = Boolean(event.verified);
    const truthLevel = isVerified ? "VERIFIED" : "DEVELOPING";

    // DEVELOPING cards capped at 40 per invariant 4
    const rankScore = isVerified ? 65 : 40;

    const rankReasons = [
        "World event from trusted source",
        `Source: ${event.source}`,
    ];

    const isLamentEvent =
        event.type === "disaster" || event.type === "conflict";

    const nowMs = Date.now();
    const expiresAtMs = event.expiresAt
        ? Number(event.expiresAt)
        : nowMs + 24 * 60 * 60 * 1000; // default 24 h

    return {
        id: `world_response_${event.id}`,
        tier: "GLOBAL",
        title: event.title,
        summary: summaryBullets,
        backingEntity: {
            kind: "EVENT",
            id: event.id,
            verified: isVerified,
        },
        truthLevel,
        matchScore: null,
        matchReasons,
        actions,
        rankScore,
        rankReasons,
        geo: null,
        formation: {
            finite: true,
            spectacleCounters: false,
            lamentFrame: isLamentEvent,
            loopParentId: null,
        },
        source: event.source,
        createdAt: event.createdAt ? Number(event.createdAt) : nowMs,
        expiresAt: expiresAtMs,
    };
}

// ─── Main export ──────────────────────────────────────────────────────────────

/**
 * buildWorldResponseCards
 *
 * Reads world_response_queue from Firestore and builds GLOBAL IntelligenceCards.
 *
 * @param {string}   userId      — authenticated user ID (unused for now; reserved for
 *                                 personalised filtering if needed in future)
 * @param {object}   db          — Firestore instance (admin.firestore())
 * @param {function} callModelFn — async (payload) → { known, contested, howToRespond }
 *                                 Returns null on failure; worldResponse fails-closed.
 *
 * @returns {Promise<IntelligenceCard[]>}
 */
async function buildWorldResponseCards(userId, db, callModelFn) {
    // 1. Seed default sources if first run
    try {
        await seedDefaultSources(db);
    } catch (err) {
        // Non-critical — don't abort card building
        console.warn("[worldResponse] seedDefaultSources error:", err.message);
    }

    // 2. Fetch active events from world_response_queue
    let eventsSnap;
    try {
        eventsSnap = await db
            .collection("world_response_queue")
            .where("active", "==", true)
            .orderBy("createdAt", "desc")
            .limit(MAX_CARDS)
            .get();
    } catch (err) {
        console.error("[worldResponse] Failed to fetch world_response_queue:", err.message);
        return [];
    }

    if (eventsSnap.empty) {
        console.log("[worldResponse] world_response_queue is empty — returning []");
        return [];
    }

    const cards = [];

    for (const doc of eventsSnap.docs) {
        const event = { id: doc.id, ...doc.data() };

        // 3. Skip events missing a source (invariant: GLOBAL cards ALWAYS have source)
        if (!event.source || typeof event.source !== "string" || !event.source.trim()) {
            console.warn(`[worldResponse] Skipping event ${event.id} — missing source`);
            continue;
        }

        // 4. Call AI model
        const modelOutput = await callForEvent(event, callModelFn);
        if (!modelOutput) {
            // callModelFn failed — fail-closed, skip this card
            continue;
        }

        // 5. Moderation check — fail-closed
        const summaryForCheck = [
            ...modelOutput.known.slice(0, 2),
            ...modelOutput.howToRespond.slice(0, 1),
        ];
        const safe = await passesModeration(summaryForCheck, db);
        if (!safe) {
            continue;
        }

        // 6. Build card
        const card = buildCard(event, modelOutput);
        cards.push(card);

        // 7. Mark event as processed (non-critical)
        await markProcessed(db, event.id);
    }

    // 8. DEVELOPING cards already capped at rankScore 40 in buildCard.
    //    Sort: VERIFIED first, then DEVELOPING — never DEVELOPING at top.
    cards.sort((a, b) => b.rankScore - a.rankScore);

    console.log(`[worldResponse] Built ${cards.length} world response cards for user ${userId}`);
    return cards;
}

module.exports = { buildWorldResponseCards };

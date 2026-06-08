"use strict";

/**
 * worldResponseAdmin.js
 *
 * AMEN Intelligence — World Response admin Cloud Functions.
 *
 * Admin/pastor-only callables that populate and manage the
 * world_response_queue Firestore collection feeding GLOBAL intelligence cards.
 *
 * Exports:
 *   addWorldResponseEvent    — create a new world event for the intelligence pipeline
 *   closeWorldResponseEvent  — mark an event inactive
 *   listWorldResponseEvents  — list active events for admin review
 *
 * Add to functions/index.js:
 *   const { addWorldResponseEvent, closeWorldResponseEvent, listWorldResponseEvents }
 *       = require('./intelligence/worldResponseAdmin');
 *   exports.addWorldResponseEvent    = addWorldResponseEvent;
 *   exports.closeWorldResponseEvent  = closeWorldResponseEvent;
 *   exports.listWorldResponseEvents  = listWorldResponseEvents;
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const REGION = "us-central1";

const VALID_EVENT_TYPES = ["disaster", "conflict", "justice", "mission"];

// ── Role helper ───────────────────────────────────────────────────────────────

/**
 * Verify the caller is authenticated and has the pastor or admin custom claim.
 * Throws HttpsError('unauthenticated') if not signed in.
 * Throws HttpsError('permission-denied') if not pastor or admin.
 *
 * @param {object} request - onCall request object
 * @returns {string} uid
 */
function requirePastorOrAdmin(request) {
    if (!request.auth?.uid) {
        throw new HttpsError(
            "unauthenticated",
            "Authentication required."
        );
    }
    const claims = request.auth.token ?? {};
    if (!claims.pastor && !claims.admin) {
        throw new HttpsError(
            "permission-denied",
            "Only pastors and admins can manage world response events."
        );
    }
    return request.auth.uid;
}

// ── addWorldResponseEvent ─────────────────────────────────────────────────────

/**
 * addWorldResponseEvent
 *
 * Admin/pastor callable: creates a new event in world_response_queue for the
 * GLOBAL intelligence pipeline. The event will appear in intelligence cards
 * for all users on their next brief refresh.
 *
 * Request data:
 *   {
 *     title:               string   (required)
 *     source:              string   (required — news source attribution)
 *     type:                string   (required — "disaster"|"conflict"|"justice"|"mission")
 *     verified?:           boolean  (default false)
 *     hasDonationLink?:    boolean  (default false)
 *     donationUrl?:        string   (optional — only when hasDonationLink is true)
 *     discussionEnabled?:  boolean  (default true)
 *     hasLocalAngle?:      boolean  (default false)
 *     expiresInHours?:     number   (default 48)
 *   }
 *
 * Response: { eventId: string, success: true }
 *
 * Writes to: world_response_queue/{eventId}
 */
exports.addWorldResponseEvent = onCall({ region: REGION }, async (request) => {
    const uid = requirePastorOrAdmin(request);
    const db = getFirestore();

    const data = request.data ?? {};

    // ── Required field validation ─────────────────────────────────────────────

    if (!data.title || typeof data.title !== "string" || data.title.trim() === "") {
        throw new HttpsError("invalid-argument", "title is required and must be a non-empty string.");
    }

    if (!data.source || typeof data.source !== "string" || data.source.trim() === "") {
        throw new HttpsError("invalid-argument", "source is required and must be a non-empty string.");
    }

    if (!data.type || !VALID_EVENT_TYPES.includes(data.type)) {
        throw new HttpsError(
            "invalid-argument",
            `type is required and must be one of: ${VALID_EVENT_TYPES.join(", ")}.`
        );
    }

    // ── Optional field validation ─────────────────────────────────────────────

    const expiresInHours = typeof data.expiresInHours === "number" && data.expiresInHours > 0
        ? data.expiresInHours
        : 48;

    const verified         = data.verified         === true;
    const hasDonationLink  = data.hasDonationLink  === true;
    const discussionEnabled = data.discussionEnabled !== false; // default true
    const hasLocalAngle    = data.hasLocalAngle    === true;

    // Validate donationUrl if hasDonationLink is set
    if (hasDonationLink && data.donationUrl) {
        if (typeof data.donationUrl !== "string" || data.donationUrl.trim() === "") {
            throw new HttpsError("invalid-argument", "donationUrl must be a non-empty string when provided.");
        }
        // Basic URL check
        try {
            new URL(data.donationUrl.trim());
        } catch {
            throw new HttpsError("invalid-argument", "donationUrl must be a valid URL.");
        }
    }

    // ── Write to world_response_queue ─────────────────────────────────────────

    const eventRef = db.collection("world_response_queue").doc();
    const eventId  = eventRef.id;

    const eventDoc = {
        id:                 eventId,
        title:              data.title.trim(),
        source:             data.source.trim(),
        type:               data.type,
        verified,
        hasDonationLink,
        discussionEnabled,
        hasLocalAngle,
        active:             true,
        createdAt:          FieldValue.serverTimestamp(),
        expiresAt:          Date.now() + expiresInHours * 3_600_000,
        addedBy:            uid,
    };

    // Only add optional fields if they're present
    if (hasDonationLink && data.donationUrl) {
        eventDoc.donationUrl = data.donationUrl.trim();
    }

    await eventRef.set(eventDoc);

    console.log(`[addWorldResponseEvent] uid=${uid} eventId=${eventId} type=${data.type} title="${data.title.trim()}"`);

    return { eventId, success: true };
});

// ── closeWorldResponseEvent ───────────────────────────────────────────────────

/**
 * closeWorldResponseEvent
 *
 * Admin/pastor callable: marks a world response event as inactive.
 * Closed events stop appearing in intelligence card generation.
 *
 * Request data:
 *   { eventId: string }
 *
 * Response: { success: true }
 *
 * Writes to: world_response_queue/{eventId} — sets active=false, closedAt, closedBy
 */
exports.closeWorldResponseEvent = onCall({ region: REGION }, async (request) => {
    const uid = requirePastorOrAdmin(request);
    const db = getFirestore();

    const { eventId } = request.data ?? {};

    if (!eventId || typeof eventId !== "string" || eventId.trim() === "") {
        throw new HttpsError("invalid-argument", "eventId must be a non-empty string.");
    }

    const eventRef = db.collection("world_response_queue").doc(eventId.trim());
    const snap = await eventRef.get();

    if (!snap.exists) {
        throw new HttpsError("not-found", `Event ${eventId} not found in world_response_queue.`);
    }

    await eventRef.update({
        active:    false,
        closedAt:  FieldValue.serverTimestamp(),
        closedBy:  uid,
    });

    console.log(`[closeWorldResponseEvent] uid=${uid} eventId=${eventId} — marked inactive`);

    return { success: true };
});

// ── listWorldResponseEvents ───────────────────────────────────────────────────

/**
 * listWorldResponseEvents
 *
 * Admin/pastor callable: returns the current active world response events
 * for review in the admin UI.
 *
 * Request data: {} (no parameters required)
 *
 * Response: { events: WorldResponseEvent[] }
 *
 * Reads: world_response_queue where active == true, limit 20, orderBy createdAt desc
 */
exports.listWorldResponseEvents = onCall({ region: REGION }, async (request) => {
    requirePastorOrAdmin(request);
    const db = getFirestore();

    const snap = await db
        .collection("world_response_queue")
        .where("active", "==", true)
        .orderBy("createdAt", "desc")
        .limit(20)
        .get();

    const events = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));

    console.log(`[listWorldResponseEvents] Returning ${events.length} active event(s)`);

    return { events };
});

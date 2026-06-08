/**
 * amenLive.js
 * AMEN App — Amen Live session management engine
 *
 * Manages the amen_live_sessions Firestore collection.
 * All writes use the Admin SDK — no client writes are permitted.
 *
 * Formation invariants:
 *   - NO spectacle counters written to session documents
 *   - backingEntity existence is verified before a session is created
 *   - getActiveSessions returns max 3 sessions (don't overwhelm the banner)
 *   - isActive is always set server-side; clients may only read
 *
 * Firestore rules needed (add to firestore.rules — for human operator):
 *
 *   match /amen_live_sessions/{sessionId} {
 *     allow read: if isSignedIn();
 *     allow write: if false; // CF Admin SDK only
 *   }
 *
 * Exports:
 *   startLiveSession(data, db)  → sessionId (string)
 *   endLiveSession(sessionId, db)
 *   getActiveSessions(churchIds, db) → AmenLiveSession[]
 */

"use strict";

const { FieldValue } = require("firebase-admin/firestore");

// ── Constants ─────────────────────────────────────────────────────────────────

/** Maximum number of active sessions returned by getActiveSessions. */
const MAX_ACTIVE_SESSIONS = 3;

/**
 * Valid backingEntityKind values. Must match AmenLiveModels.swift.
 * @type {string[]}
 */
const VALID_BACKING_KINDS = ["CHURCH", "EVENT", "ORG"];

/**
 * Valid AmenLiveType raw values. Must match AmenLiveModels.swift.
 * @type {string[]}
 */
const VALID_SESSION_TYPES = [
    "PRAYER_EVENT",
    "SERMON_STREAM",
    "COMMUNITY_MOMENT",
    "VOLUNTEER_MOBILIZATION",
    "CRISIS_RESPONSE",
];

// ── Collection name helper ────────────────────────────────────────────────────

const COLLECTION = "amen_live_sessions";

// ── Backing entity resolver ───────────────────────────────────────────────────

/**
 * Map backingEntityKind to its Firestore collection name.
 * @param {string} kind
 * @returns {string|null}
 */
function collectionForKind(kind) {
    const map = {
        CHURCH: "churches",
        EVENT:  "events",
        ORG:    "organizations",
    };
    return map[kind] ?? null;
}

/**
 * Verify that a backing entity document exists in Firestore.
 * Throws an Error if the entity cannot be found.
 *
 * @param {string} backingEntityId
 * @param {string} backingEntityKind
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<void>}
 */
async function resolveBackingEntity(backingEntityId, backingEntityKind, db) {
    const collection = collectionForKind(backingEntityKind);
    if (!collection) {
        throw new Error(
            `Invalid backingEntityKind: "${backingEntityKind}". ` +
            `Valid values: ${VALID_BACKING_KINDS.join(", ")}`
        );
    }

    const snap = await db.collection(collection).doc(backingEntityId).get();
    if (!snap.exists) {
        throw new Error(
            `Backing entity not found: ${backingEntityKind}/${backingEntityId}. ` +
            "Live sessions must reference real entities."
        );
    }
}

// ── startLiveSession ──────────────────────────────────────────────────────────

/**
 * Create a new live session document in amen_live_sessions.
 *
 * @param {object} data
 * @param {string} data.title                 - Session headline (required)
 * @param {string} [data.subtitle]            - Supporting context line
 * @param {string} data.type                  - AmenLiveType rawValue (required)
 * @param {string} data.hostId                - Church/org/user Firestore UID (required)
 * @param {string} data.hostName              - Human-readable host name (required)
 * @param {string} data.backingEntityId       - Firestore doc ID of backing entity (required)
 * @param {string} data.backingEntityKind     - "CHURCH" | "EVENT" | "ORG" (required)
 * @param {string} data.actionLabel           - CTA button label (required)
 * @param {string} data.actionHandler         - CF callable name (required)
 * @param {string} data.actionTarget          - Entity ID for action target (required)
 * @param {number} [data.scheduledDurationMinutes] - If set, schedules endAt
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<string>} sessionId
 */
async function startLiveSession(data, db) {
    const {
        title,
        subtitle,
        type,
        hostId,
        hostName,
        backingEntityId,
        backingEntityKind,
        actionLabel,
        actionHandler,
        actionTarget,
        scheduledDurationMinutes,
    } = data;

    // ── Input validation ──────────────────────────────────────────────────────

    if (!title || typeof title !== "string" || title.trim() === "") {
        throw new Error("title is required and must be a non-empty string.");
    }
    if (!type || !VALID_SESSION_TYPES.includes(type)) {
        throw new Error(
            `type must be one of: ${VALID_SESSION_TYPES.join(", ")}`
        );
    }
    if (!hostId || typeof hostId !== "string") {
        throw new Error("hostId is required.");
    }
    if (!hostName || typeof hostName !== "string") {
        throw new Error("hostName is required.");
    }
    if (!backingEntityId || !backingEntityKind) {
        throw new Error("backingEntityId and backingEntityKind are required.");
    }
    if (!actionLabel || !actionHandler || !actionTarget) {
        throw new Error("actionLabel, actionHandler, and actionTarget are required.");
    }

    // ── Verify backing entity exists ──────────────────────────────────────────
    await resolveBackingEntity(backingEntityId, backingEntityKind, db);

    // ── Compute scheduledEndAt (epoch ms) ─────────────────────────────────────
    let scheduledEndAt = null;
    if (
        scheduledDurationMinutes &&
        typeof scheduledDurationMinutes === "number" &&
        scheduledDurationMinutes > 0
    ) {
        scheduledEndAt = Date.now() + scheduledDurationMinutes * 60 * 1000;
    }

    // ── Write session document ────────────────────────────────────────────────
    const sessionRef = db.collection(COLLECTION).doc();
    const now = Date.now();

    const sessionDoc = {
        title:             title.trim(),
        subtitle:          subtitle ?? null,
        type,
        hostId,
        hostName,
        startedAt:         now,
        scheduledEndAt,
        isActive:          true,
        backingEntityId,
        backingEntityKind,
        actionLabel,
        actionHandler,
        actionTarget,
        createdAt:         FieldValue.serverTimestamp(),
        // Formation invariants — deliberately absent:
        // NO attendeeCount, viewerCount, prayerCount, watcherCount
    };

    await sessionRef.set(sessionDoc);

    console.log(
        `[amenLive] Started session ${sessionRef.id} ` +
        `type=${type} host=${hostId}`
    );

    return sessionRef.id;
}

// ── endLiveSession ────────────────────────────────────────────────────────────

/**
 * Mark a live session as ended.
 *
 * @param {string} sessionId
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<void>}
 */
async function endLiveSession(sessionId, db) {
    if (!sessionId || typeof sessionId !== "string") {
        throw new Error("sessionId is required.");
    }

    const ref = db.collection(COLLECTION).doc(sessionId);
    const snap = await ref.get();

    if (!snap.exists) {
        throw new Error(`Session not found: ${sessionId}`);
    }

    await ref.update({
        isActive: false,
        endedAt:  FieldValue.serverTimestamp(),
    });

    console.log(`[amenLive] Ended session ${sessionId}`);
}

// ── getActiveSessions ─────────────────────────────────────────────────────────

/**
 * Return up to MAX_ACTIVE_SESSIONS active sessions for the given church/org IDs.
 *
 * @param {string[]} churchIds - Array of host IDs (church + org IDs for the user)
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<object[]>} Array of AmenLiveSession-shaped objects
 */
async function getActiveSessions(churchIds, db) {
    if (!Array.isArray(churchIds) || churchIds.length === 0) {
        return [];
    }

    // Firestore `in` supports at most 30 values.
    const safeIds = churchIds.slice(0, 30);

    const snap = await db
        .collection(COLLECTION)
        .where("isActive", "==", true)
        .where("hostId", "in", safeIds)
        .limit(MAX_ACTIVE_SESSIONS)
        .get();

    return snap.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
    }));
}

// ── Exports ───────────────────────────────────────────────────────────────────

module.exports = { startLiveSession, endLiveSession, getActiveSessions };

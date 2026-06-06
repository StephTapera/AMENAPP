/**
 * churchPulseCallable.js
 * AMEN App — getChurchPulse callable Cloud Function
 *
 * getChurchPulse — callable: returns a cached or freshly-computed ChurchPulse
 *   for the given churchId.
 *
 * Auth:       required (uid must be a member of the church)
 * Cache TTL:  6 hours (written to church_pulse/{churchId})
 * Membership: verified via churches/{churchId}/members/{uid}
 *
 * Request:  { churchId: string }
 * Response: ChurchPulse object (see churchPulse.js for shape)
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore }       = require("firebase-admin/firestore");
const { computeChurchPulse } = require("./churchPulse");

const CACHE_TTL_MS = 6 * 60 * 60 * 1000; // 6 hours

// ── Main callable ─────────────────────────────────────────────────────────────

exports.getChurchPulse = onCall({ region: "us-central1" }, async (request) => {
    // ── Auth guard ────────────────────────────────────────────────────────────
    if (!request.auth) {
        throw new HttpsError(
            "unauthenticated",
            "You must be signed in to view church pulse.",
        );
    }

    const uid = request.auth.uid;

    // ── Input validation ──────────────────────────────────────────────────────
    const { churchId } = request.data ?? {};

    if (!churchId || typeof churchId !== "string" || churchId.trim() === "") {
        throw new HttpsError(
            "invalid-argument",
            "churchId must be a non-empty string.",
        );
    }

    const db = getFirestore();

    // ── Verify church membership ──────────────────────────────────────────────
    // Check churches/{churchId}/members/{uid} exists
    const memberRef = db
        .collection("churches")
        .doc(churchId)
        .collection("members")
        .doc(uid);

    const memberSnap = await memberRef.get();

    if (!memberSnap.exists) {
        throw new HttpsError(
            "permission-denied",
            "You must be a member of this church to view its pulse.",
        );
    }

    // ── Cache check ───────────────────────────────────────────────────────────
    const pulseRef = db.collection("church_pulse").doc(churchId);
    const pulseSnap = await pulseRef.get();

    if (pulseSnap.exists) {
        const cached = pulseSnap.data();
        const computedAt = cached?.computedAt ?? 0;
        const age = Date.now() - computedAt;

        if (age < CACHE_TTL_MS) {
            // Cache hit — return as-is
            return cached;
        }
    }

    // ── Compute fresh pulse ───────────────────────────────────────────────────
    const pulse = await computeChurchPulse(churchId, db);

    // ── Write to cache ────────────────────────────────────────────────────────
    // Fail silently so a cache-write error never blocks the client response.
    try {
        await pulseRef.set(pulse);
    } catch (cacheErr) {
        // Non-critical — log and continue
        console.error("churchPulse: cache write failed", cacheErr);
    }

    return pulse;
});

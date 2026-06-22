"use strict";

/**
 * seedWorldResponseSources.js
 *
 * AMEN Intelligence — Seed worldResponseSources with trusted news sources.
 *
 * One-time seeder: populates the worldResponseSources Firestore collection
 * with trusted Christian and general news sources used by the GLOBAL
 * intelligence pipeline.
 *
 * Run once after first deploy:
 *   firebase functions:call seedWorldResponseSources --data '{}' --project amen-5e359
 *
 * Or trigger from admin console.
 *
 * Exports:
 *   seedWorldResponseSources — admin-only callable
 *
 * Add to functions/index.js:
 *   const { seedWorldResponseSources } = require('./intelligence/seedWorldResponseSources');
 *   exports.seedWorldResponseSources = seedWorldResponseSources;
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore } = require("firebase-admin/firestore");

const REGION = "us-central1";

// ── Default sources ───────────────────────────────────────────────────────────

const DEFAULT_SOURCES = [
    {
        id: "world_magazine",
        name: "WORLD Magazine",
        description: "Christian news and culture",
        active: true,
    },
    {
        id: "christianity_today",
        name: "Christianity Today",
        description: "Evangelical news and theology",
        active: true,
    },
    {
        id: "relevant_magazine",
        name: "Relevant Magazine",
        description: "Faith and culture for young adults",
        active: true,
    },
    {
        id: "the_dispatch",
        name: "The Dispatch",
        description: "Center-right fact-based journalism",
        active: true,
    },
    {
        id: "ap_religion",
        name: "AP Religion",
        description: "Associated Press religion coverage",
        active: true,
    },
];

// ── Role helper ───────────────────────────────────────────────────────────────

/**
 * Verify the caller is authenticated and has the admin custom claim.
 * Throws HttpsError('unauthenticated') if not signed in.
 * Throws HttpsError('permission-denied') if not admin.
 *
 * @param {object} request - onCall request object
 * @returns {string} uid
 */
function requireAdmin(request) {
    if (!request.auth?.uid) {
        throw new HttpsError(
            "unauthenticated",
            "Authentication required."
        );
    }
    const claims = request.auth.token ?? {};
    if (!claims.admin) {
        throw new HttpsError(
            "permission-denied",
            "Only admins can seed world response sources."
        );
    }
    return request.auth.uid;
}

// ── seedWorldResponseSources ──────────────────────────────────────────────────

/**
 * seedWorldResponseSources
 *
 * Admin-only callable: populates worldResponseSources/{source.id} with the
 * DEFAULT_SOURCES list. Uses { merge: true } so existing entries are not
 * overwritten.
 *
 * Request data: {} (no parameters required)
 *
 * Response: { seeded: number } — count of sources written
 *
 * Writes to: worldResponseSources/{source.id} (merge: true on each)
 */
exports.seedWorldResponseSources = onCall({ region: REGION }, async (request) => {
    const uid = requireAdmin(request);
    const db = getFirestore();

    console.log(`[seedWorldResponseSources] uid=${uid} — seeding ${DEFAULT_SOURCES.length} sources`);

    const batch = db.batch();

    for (const source of DEFAULT_SOURCES) {
        const ref = db.collection("worldResponseSources").doc(source.id);
        batch.set(ref, source, { merge: true });
    }

    await batch.commit();

    console.log(`[seedWorldResponseSources] uid=${uid} — seeded ${DEFAULT_SOURCES.length} sources successfully`);

    return { seeded: DEFAULT_SOURCES.length };
});

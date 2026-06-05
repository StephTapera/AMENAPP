/**
 * discoveryByGoalsFunctions.js
 * AMEN App — Personal Discovery Agent: goal-based community/church/event search
 *
 * discoverByGoals — callable: accepts a free-text goal description from the
 *   Personal Discovery Agent sheet and returns the top-N communities, churches,
 *   and upcoming events from Firestore.
 *
 * Current implementation returns results ordered by recency / popularity.
 *
 * TODO (future): replace Firestore range queries with Algolia semantic search:
 *   const { SearchClient } = require('algoliasearch');
 *   const client = new SearchClient(ALGOLIA_APP_ID, ALGOLIA_API_KEY);
 *   const hits   = await client.search({ query: goals, indexName: 'spaces' });
 *   Algolia will enable semantic matching of goals text against community/church
 *   descriptions rather than returning raw recency-sorted results.
 *
 * Auth:  required (uid must match request.auth.uid)
 * Reads: spaces (isPublic==true, ordered by memberCount), churches (isPublic==true),
 *        events  (startDate > now, isPublic==true)
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

const db = getFirestore();

// ---------------------------------------------------------------------------
// Helper — normalise a Firestore doc to the summary shape returned to the client
// ---------------------------------------------------------------------------

function toSummary(docSnap) {
  const d = docSnap.data() ?? {};
  return {
    id:          docSnap.id,
    name:        d.name        ?? d.title        ?? "",
    description: d.description ?? d.bio          ?? "",
    imageUrl:    d.imageUrl    ?? d.coverImageUrl ?? d.photoURL ?? null,
  };
}

// ---------------------------------------------------------------------------
// discoverByGoals
// ---------------------------------------------------------------------------

exports.discoverByGoals = onCall({ region: "us-central1" }, async (request) => {
  // ── Auth guard ────────────────────────────────────────────────────────────
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in to use the Discovery Agent.");
  }

  const callerUid = request.auth.uid;
  const { goals, userId } = request.data ?? {};

  // ── Input validation ──────────────────────────────────────────────────────
  if (!goals || typeof goals !== "string" || goals.trim() === "") {
    throw new HttpsError("invalid-argument", "goals must be a non-empty string.");
  }
  if (!userId || typeof userId !== "string") {
    throw new HttpsError("invalid-argument", "userId is required.");
  }

  // UID must match the authenticated caller.
  if (userId !== callerUid) {
    throw new HttpsError(
      "permission-denied",
      "userId does not match the authenticated user.",
    );
  }

  const goalsText = goals.trim();

  // Enforce a reasonable max length to prevent abuse.
  if (goalsText.length > 2000) {
    throw new HttpsError("invalid-argument", "goals must be 2000 characters or fewer.");
  }

  // ── Parallel Firestore queries ────────────────────────────────────────────
  //
  // Communities (spaces): public, ordered by memberCount descending, limit 5.
  // Churches:             public, limit 5 (Algolia will add semantic ranking later).
  // Events:               public, starting in the future, limit 5.
  //
  // All three run in parallel for low latency.

  const now = Timestamp.now();

  const [communitiesSnap, churchesSnap, eventsSnap] = await Promise.all([
    db.collection("spaces")
      .where("isPublic", "==", true)
      .orderBy("memberCount", "desc")
      .limit(5)
      .get(),

    db.collection("churches")
      .where("isPublic", "==", true)
      .limit(5)
      .get(),

    db.collection("events")
      .where("isPublic", "==", true)
      .where("startDate", ">", now)
      .orderBy("startDate", "asc")
      .limit(5)
      .get(),
  ]);

  // ── Shape the results ─────────────────────────────────────────────────────

  const communities = communitiesSnap.docs.map(toSummary);
  const churches    = churchesSnap.docs.map(toSummary);
  const events      = eventsSnap.docs.map(toSummary);

  return { communities, churches, events };
});

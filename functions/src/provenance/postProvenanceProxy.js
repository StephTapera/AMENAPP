/**
 * postProvenanceProxy.js
 * AMEN App — Post Provenance Proxy callable (Phase 3 / Master Run)
 *
 * [NEEDS HUMAN DEPLOY] to production Firebase.
 * Safe to run in the Firebase Emulator Suite only.
 *
 * Purpose:
 *   Returns the feed-ranking signals ("Why you're seeing this") for a given
 *   post. The iOS client calls this when the user taps the provenance
 *   disclosure affordance on a feed post.
 *
 * Security:
 *   - App Check enforced (enforceAppCheck: true) — invalid/spoofed apps are
 *     rejected before the function body runs.
 *   - Auth required — unauthenticated callers receive HttpsError('unauthenticated').
 *
 * Input (request.data):
 *   { postId: string }
 *
 * Output:
 *   PostProvenance — matches Phase0Contracts.swift PostProvenance (Codable):
 *   {
 *     postId:          string,
 *     reasons:         Array<{ label: string, score: number, kind: string }>,
 *     source:          string,    // FeedSource raw value
 *     addedInterestOn: string|null  // ISO-8601 Date or null
 *   }
 *
 * Implementation path:
 *   TODO: Replace mock return with real provenance lookup from the
 *   Intelligence Engine (Firestore feedEvents / rankingSignals subcollection
 *   or a dedicated provenance index). No raw feed-ranking data should ever
 *   be returned verbatim to the client — only the user-visible reason labels
 *   and scores are included in the response.
 *
 * Emulator usage:
 *   firebase emulators:start --only functions
 *   (iOS points to http://localhost:5001 via useEmulator in AppDelegate)
 */

'use strict';

const functions = require('firebase-functions/v2');

// ─── Main export ──────────────────────────────────────────────────────────────

exports.postProvenanceProxy = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    // 1. Auth guard
    if (!request.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Login required'
      );
    }

    // 2. Input validation
    const { postId } = request.data;
    if (!postId || typeof postId !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'postId required'
      );
    }

    // 3. TODO: real provenance lookup from Intelligence Engine
    //    Replace the mock below with:
    //      a. Firestore read from feedEvents/{uid}/posts/{postId} or
    //         rankingSignals/{postId} to fetch the stored ranking signals
    //         that caused this post to surface for the authenticated user.
    //      b. Map internal signal keys to user-visible reason labels.
    //      c. Return only the top 3 reasons by score.
    //    The raw ML signals must NEVER be returned to the client —
    //    only the user-visible label + kind are safe to expose.

    // Mock: return plausible reasons for emulator testing
    return {
      postId,
      reasons: [
        { label: 'You follow this person', score: 0.92, kind: 'following' },
        { label: 'Trending in your church group', score: 0.71, kind: 'communityTrending' },
        { label: 'Related to scripture you\'ve read', score: 0.54, kind: 'scripture' },
      ],
      source: 'following',
      addedInterestOn: null,
    };
  }
);

/**
 * postProvenanceProxy.js
 * AMEN App — Post Provenance Proxy callable (Phase 3 / Master Run)
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
 * Lookup strategy:
 *   1. Primary: read postProvenance/{uid}_{postId} from Firestore (written by
 *      the feed/ranking server). If found, map stored fields to output shape.
 *   2. Fallback: derive reasons from the post document + follows/topics.
 *      Only the top 3 reasons by score are returned. Raw ML signals are never
 *      exposed to the client.
 */

'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');

const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// Faith-related topic keywords used for fallback topic-match detection.
const FAITH_TOPICS = new Set([
  'faith', 'prayer', 'scripture', 'bible', 'worship', 'church', 'gospel',
  'testimony', 'devotion', 'jesus', 'god', 'holy', 'spirit', 'grace',
  'blessing', 'repentance', 'salvation', 'discipleship', 'missions',
]);

/**
 * Returns true if any of the supplied tags/topics overlap with known faith
 * topic keywords (case-insensitive).
 * @param {string[]|undefined} tags
 * @returns {boolean}
 */
function hasFaithTopicOverlap(tags) {
  if (!Array.isArray(tags) || tags.length === 0) return false;
  return tags.some((t) => FAITH_TOPICS.has(String(t).toLowerCase()));
}

// ─── Main export ──────────────────────────────────────────────────────────────

exports.postProvenanceProxy = onCall(
  { enforceAppCheck: true },
  async (request) => {
    // 1. Auth guard
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Login required');
    }

    const uid = request.auth.uid;

    // 2. Input validation
    const { postId } = request.data;
    if (!postId || typeof postId !== 'string') {
      throw new HttpsError('invalid-argument', 'postId required');
    }

    // ── Tier 1: primary lookup from postProvenance collection ────────────────
    const provenanceRef = db.collection('postProvenance').doc(`${uid}_${postId}`);
    const provenanceSnap = await provenanceRef.get();

    if (provenanceSnap.exists) {
      const data = provenanceSnap.data();
      const rawReasons = Array.isArray(data.reasons) ? data.reasons : [];

      // Map to the safe output shape and limit to top 3 by score.
      const reasons = rawReasons
        .map((r) => ({
          label: String(r.label || ''),
          score: typeof r.score === 'number' ? r.score : 0,
          kind:  String(r.kind  || 'unknown'),
        }))
        .sort((a, b) => b.score - a.score)
        .slice(0, 3);

      return {
        postId,
        reasons,
        source:          String(data.source || 'recommended'),
        addedInterestOn: data.addedInterestOn
          ? String(data.addedInterestOn)
          : null,
      };
    }

    // ── Tier 2: synthesize from post document ────────────────────────────────
    const postSnap = await db.collection('posts').doc(postId).get();

    if (!postSnap.exists) {
      // Post is gone; return a minimal safe response so the iOS UI can degrade
      // gracefully instead of crashing on an HttpsError.
      return {
        postId,
        reasons: [
          { label: 'Shared in your community', score: 0.5, kind: 'communityTrending' },
        ],
        source:          'recommended',
        addedInterestOn: null,
      };
    }

    const post = postSnap.data();
    const authorId = post.authorId || post.userId || null;

    const reasons = [];
    let source = 'recommended';

    // Check follow relationship
    if (authorId) {
      const followSnap = await db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(authorId)
        .get();

      if (followSnap.exists) {
        reasons.push({
          label: 'You follow this person',
          score: 0.9,
          kind:  'following',
        });
        source = 'following';
      }
    }

    // Check faith topic overlap
    const allTags = [
      ...(Array.isArray(post.tags)       ? post.tags       : []),
      ...(Array.isArray(post.topicTags)  ? post.topicTags  : []),
    ];
    if (hasFaithTopicOverlap(allTags)) {
      reasons.push({
        label: 'Matches your faith interests',
        score: 0.7,
        kind:  'topicMatch',
      });
    }

    // Always include community trending as a floor reason
    reasons.push({
      label: 'Shared in your community',
      score: 0.5,
      kind:  'communityTrending',
    });

    // Sort descending and take top 3
    const topReasons = reasons
      .sort((a, b) => b.score - a.score)
      .slice(0, 3);

    return {
      postId,
      reasons:         topReasons,
      source,
      addedInterestOn: null,
    };
  }
);

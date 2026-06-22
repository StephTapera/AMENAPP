/**
 * v2intelligenceFunctions.js
 *
 * AMEN Living Intelligence — Gen-2 Firebase Functions
 *
 * All gen-2 only. Do NOT import gen-1 SDK here.
 * Kept separate from v2functions.js (which owns notification triggers).
 *
 * Exports:
 *   buildDailyIntelligenceBriefs  — Scheduled: 7am + 7pm UTC daily
 *   getIntelligenceBrief          — Callable: iOS fetches current brief
 *   recordIntelligenceAction      — Callable: iOS records user action (loop-closing)
 */

"use strict";

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

const { buildUserBrief } = require('./intelligence/digestBuilder');

// ─── Secrets ──────────────────────────────────────────────────────────────────
const BEREAN_LLM_KEY    = defineSecret('BEREAN_LLM_KEY');
const ANTHROPIC_API_KEY = defineSecret('ANTHROPIC_API_KEY');

// ─── Constants ────────────────────────────────────────────────────────────────

const REGION = 'us-central1';
const BRIEF_TTL_MS = 12 * 60 * 60 * 1000;  // 12 hours
const MAX_CONCURRENT_BRIEFS = 50;

// ─── Helper: require auth ─────────────────────────────────────────────────────

function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }
  return request.auth.uid;
}

// ─── Scheduled: buildDailyIntelligenceBriefs ─────────────────────────────────

/**
 * buildDailyIntelligenceBriefs
 *
 * Runs at 7am and 7pm UTC daily.
 * Fetches all active users and rebuilds their intelligence brief in batches.
 * Max 50 concurrent brief builds to avoid quota exhaustion.
 */
exports.buildDailyIntelligenceBriefs = onSchedule(
  {
    schedule: '0 7,19 * * *',
    timeZone: 'UTC',
    region: REGION,
    secrets: [BEREAN_LLM_KEY, ANTHROPIC_API_KEY],
    memory: '512MiB',
    timeoutSeconds: 540,  // 9 minutes — runs over large user base
  },
  async (event) => {
    const db = admin.firestore();
    const startMs = Date.now();

    console.log('[buildDailyIntelligenceBriefs] Starting scheduled brief rebuild...');

    try {
      // Fetch all active users (paginated in batches of 200)
      let lastDoc = null;
      let totalBuilt = 0;
      let totalErrors = 0;
      const PAGE_SIZE = 200;

      while (true) {
        // Build the query for this page
        let query = db
          .collection('users')
          .where('intelligenceOptIn', '==', true)
          .orderBy('__name__')
          .limit(PAGE_SIZE);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const snap = await query.get();

        if (snap.empty) {
          console.log('[buildDailyIntelligenceBriefs] No more users to process.');
          break;
        }

        const userIds = snap.docs.map((d) => d.id);
        lastDoc = snap.docs[snap.docs.length - 1];

        // Process in parallel batches of MAX_CONCURRENT_BRIEFS
        for (let i = 0; i < userIds.length; i += MAX_CONCURRENT_BRIEFS) {
          const batch = userIds.slice(i, i + MAX_CONCURRENT_BRIEFS);

          const results = await Promise.allSettled(
            batch.map((userId) => buildUserBrief(userId, db)),
          );

          for (const result of results) {
            if (result.status === 'fulfilled') {
              totalBuilt++;
            } else {
              totalErrors++;
              console.error('[buildDailyIntelligenceBriefs] Brief build error:', result.reason?.message);
            }
          }
        }

        // If this page had fewer than PAGE_SIZE docs, we've reached the end
        if (snap.docs.length < PAGE_SIZE) break;
      }

      const elapsedMs = Date.now() - startMs;
      console.log(
        `[buildDailyIntelligenceBriefs] Complete: built=${totalBuilt} errors=${totalErrors} elapsed=${elapsedMs}ms`,
      );
    } catch (err) {
      console.error('[buildDailyIntelligenceBriefs] Fatal error:', err.message);
    }
  },
);

// ─── Callable: getIntelligenceBrief ──────────────────────────────────────────

/**
 * getIntelligenceBrief
 *
 * iOS app calls this to get the user's current intelligence brief.
 * If the brief exists and is fresh (< 12h old), returns it immediately.
 * Otherwise triggers a synchronous rebuild and returns the new brief.
 *
 * Response: { brief: IntelligenceBrief, cards: IntelligenceCard[], generatedAt: number }
 */
exports.getIntelligenceBrief = onCall(
  {
    region: REGION,
    secrets: [BEREAN_LLM_KEY, ANTHROPIC_API_KEY],
    memory: '512MiB',
    timeoutSeconds: 60,
  },
  async (request) => {
    const userId = requireAuth(request);
    const db = admin.firestore();
    const nowMs = Date.now();

    // Check for a fresh existing brief
    const briefSnap = await db.collection('intelligence_briefs').doc(userId).get();

    if (briefSnap.exists) {
      const existing = briefSnap.data();
      const isFresh = existing.expiresAt && existing.expiresAt > nowMs;

      if (isFresh) {
        // Fetch associated cards
        const cardIds = existing.cardIds || [];
        let cards = [];

        if (cardIds.length > 0) {
          const cardSnaps = await Promise.all(
            cardIds.map((id) => db.collection('intelligence_cards').doc(id).get()),
          );
          cards = cardSnaps
            .filter((s) => s.exists)
            .map((s) => ({ id: s.id, ...s.data() }));
        }

        console.log(`[getIntelligenceBrief] Returning fresh brief for ${userId} (${cards.length} cards)`);
        return {
          brief: existing,
          cards,
          generatedAt: existing.generatedAt || nowMs,
          fromCache: true,
        };
      }
    }

    // Brief is stale or missing — rebuild synchronously
    console.log(`[getIntelligenceBrief] Rebuilding brief for ${userId}`);
    try {
      const result = await buildUserBrief(userId, db);
      return {
        brief: result.brief,
        cards: result.cards,
        generatedAt: result.generatedAt,
        fromCache: false,
      };
    } catch (err) {
      console.error(`[getIntelligenceBrief] Build error for ${userId}:`, err.message);
      throw new HttpsError('internal', 'Failed to build intelligence brief. Please try again.');
    }
  },
);

// ─── Callable: recordIntelligenceAction ──────────────────────────────────────

/**
 * recordIntelligenceAction
 *
 * iOS app calls this when a user takes an action from a card
 * (RSVP, pray, give, show up, etc.).
 *
 * Writes to: intelligence_actions/{userId}/actions/{actionId}
 * Marks loopParentId so the next brief can include a follow-up card.
 *
 * Request: {
 *   cardId: string,          — the card the user acted on
 *   rung: ActionRung,        — which rung was activated
 *   targetId: string,        — entity being acted upon (event id, prayer id, etc.)
 *   loopParentId?: string    — optional: id to close a prior action loop
 * }
 */
exports.recordIntelligenceAction = onCall(
  {
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 30,
  },
  async (request) => {
    const userId = requireAuth(request);
    const db = admin.firestore();

    const { cardId, rung, targetId, loopParentId } = request.data ?? {};

    // Input validation
    if (!cardId || typeof cardId !== 'string') {
      throw new HttpsError('invalid-argument', 'cardId is required');
    }
    if (!rung || typeof rung !== 'string') {
      throw new HttpsError('invalid-argument', 'rung is required');
    }
    if (!targetId || typeof targetId !== 'string') {
      throw new HttpsError('invalid-argument', 'targetId is required');
    }

    const VALID_RUNGS = ['NOTICE', 'PRAY', 'LEARN', 'DISCUSS', 'GIVE', 'SHOW_UP', 'START'];
    if (!VALID_RUNGS.includes(rung)) {
      throw new HttpsError('invalid-argument', `rung must be one of: ${VALID_RUNGS.join(', ')}`);
    }

    const actionRef = db
      .collection('intelligence_actions')
      .doc(userId)
      .collection('actions')
      .doc();

    const actionData = {
      cardId,
      rung,
      targetId,
      loopParentId: loopParentId || cardId,  // default loop parent is the card itself
      userId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await actionRef.set(actionData);

    console.log(`[recordIntelligenceAction] userId=${userId} cardId=${cardId} rung=${rung} actionId=${actionRef.id}`);

    return {
      success: true,
      actionId: actionRef.id,
      loopParentId: actionData.loopParentId,
    };
  },
);

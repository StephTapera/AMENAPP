/**
 * functions/intelligence/digestBuilder.js
 *
 * AMEN Living Intelligence — Digest Builder
 *
 * Export:
 *   buildUserBrief(userId, db)
 *
 * Called by the scheduled v2 function twice daily.
 * Builds a complete IntelligenceBrief by:
 *   1. Enforcing digest cadence (max 2/day)
 *   2. Fetching user context from Firestore
 *   3. Collecting candidate cards from multiple sources
 *   4. Resolving and verifying backing entities
 *   5. Generating Berean summaries via callModelRouter
 *   6. Ranking all cards
 *   7. Applying all formation governor passes
 *   8. Writing the brief + cards to Firestore
 */

"use strict";

const admin = require('firebase-admin');
const { resolveBackingEntity } = require('./opportunityGraph');
const { rankCard } = require('./rankingBrain');
const { callModel } = require('./callModelRouter');
const {
  enforceDigestCadence,
  enforceBriefCap,
  stripSpectacleCounters,
  enforceGeo,
  enforcePoliticsFilter,
  assertLoopClosure,
  assertCard,
} = require('./formationGovernor');
const { BACKING_KIND, TRUTH_LEVEL, ACTION_RUNG, TIER_ORDER } = require('./contracts');

// ─── Constants ────────────────────────────────────────────────────────────────

const BRIEF_TTL_MS = 12 * 60 * 60 * 1000; // 12 hours
const MAX_CANDIDATES_PER_SOURCE = 10;
const BATCH_TIMEOUT_MS = 8000; // per-candidate timeout

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * withTimeout — wraps a promise with a timeout, returning null on timeout.
 */
async function withTimeout(promise, ms = BATCH_TIMEOUT_MS) {
  const timeout = new Promise((resolve) => setTimeout(() => resolve(null), ms));
  return Promise.race([promise, timeout]);
}

/**
 * fetchUserContext — load all user profile fields needed for ranking.
 *
 * @param {string} userId
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<object>}  User context object
 */
async function fetchUserContext(userId, db) {
  try {
    const userSnap = await db.collection('users').doc(userId).get();
    if (!userSnap.exists) {
      console.warn(`[digestBuilder] User ${userId} not found`);
      return { userId };
    }

    const u = userSnap.data();

    // Load prior intelligence actions (for loop-closing)
    const actionsSnap = await db
      .collection('intelligence_actions')
      .doc(userId)
      .collection('actions')
      .where('rung', 'in', ['SHOW_UP', 'GIVE'])
      .where('createdAt', '>=', new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)) // last 30 days
      .limit(20)
      .get();

    const priorActions = actionsSnap.docs.map((d) => d.data().loopParentId || d.id).filter(Boolean);

    return {
      userId,
      churchIds: u.churchIds || (u.churchId ? [u.churchId] : []),
      followedChurchIds: u.followedChurchIds || [],
      seasonOfLife: u.seasonOfLife || null,
      liturgicalSeason: u.liturgicalSeason || null,
      userCapacity: u.intelligenceCapacity || 'standard',
      location: u.locationSharingEnabled && u.coarseLocation
        ? { lat: u.coarseLocation.lat, lng: u.coarseLocation.lng }
        : null,
      priorActions,
      globalNewsOptIn: u.globalNewsOptIn === true,
    };
  } catch (err) {
    console.error(`[digestBuilder] fetchUserContext error for ${userId}:`, err.message);
    return { userId, churchIds: [], followedChurchIds: [], priorActions: [] };
  }
}

/**
 * buildCandidateFromEvent — transform a Firestore event doc into a card candidate.
 */
function buildCandidateFromEvent(doc, userId) {
  const d = doc.data();
  const now = Date.now();
  return {
    id: `event_${doc.id}_${userId}`,
    tier: 'LOCAL',
    title: d.title || d.name || 'Church Event',
    summary: [],  // to be filled by Berean
    backingEntity: {
      kind: BACKING_KIND.EVENT,
      id: doc.id,
      verified: false,  // to be verified via resolveBackingEntity
    },
    truthLevel: TRUTH_LEVEL.CHURCH_CONFIRMED,
    actions: [
      {
        rung: ACTION_RUNG.PRAY,
        label: 'Pray for this event',
        handler: 'recordIntelligenceAction',
        target: doc.id,
      },
      {
        rung: ACTION_RUNG.SHOW_UP,
        label: 'RSVP to attend',
        handler: 'rsvpToChurchEvent',
        target: doc.id,
      },
    ],
    rankScore: 0,
    rankReasons: [],
    formation: {
      finite: true,
      spectacleCounters: false,
    },
    rawContent: d.description || d.notes || '',
    scriptureRefs: d.scriptureRefs || [],
    createdAt: now,
    expiresAt: now + BRIEF_TTL_MS,
    _source: 'events',
  };
}

/**
 * buildCandidateFromPrayer — transform a prayer request doc into a card candidate.
 */
function buildCandidateFromPrayer(doc, userId) {
  const d = doc.data();
  const now = Date.now();
  return {
    id: `prayer_${doc.id}_${userId}`,
    tier: 'COMMUNITY',
    title: d.title || 'Prayer Request',
    summary: [],
    backingEntity: {
      kind: BACKING_KIND.PRAYER_REQUEST,
      id: doc.id,
      verified: false,
    },
    truthLevel: TRUTH_LEVEL.COMMUNITY_CONFIRMED,
    actions: [
      {
        rung: ACTION_RUNG.PRAY,
        label: 'Pray for this need',
        handler: 'recordPrayerAction',
        target: doc.id,
      },
    ],
    rankScore: 0,
    rankReasons: [],
    formation: {
      finite: true,
      spectacleCounters: false,
    },
    rawContent: d.body || d.content || d.request || '',
    scriptureRefs: [],
    createdAt: now,
    expiresAt: now + BRIEF_TTL_MS,
    _source: 'prayers',
  };
}

/**
 * buildCandidateFromVolunteerOpportunity — transform a volunteer opportunity doc.
 */
function buildCandidateFromOpportunity(doc, userId) {
  const d = doc.data();
  const now = Date.now();
  return {
    id: `need_${doc.id}_${userId}`,
    tier: 'LOCAL',
    title: d.title || d.role || 'Volunteer Opportunity',
    summary: [],
    backingEntity: {
      kind: BACKING_KIND.NEED,
      id: doc.id,
      verified: false,
    },
    truthLevel: TRUTH_LEVEL.CHURCH_CONFIRMED,
    actions: [
      {
        rung: ACTION_RUNG.LEARN,
        label: 'Learn more',
        handler: 'getVolunteerOpportunityDetails',
        target: doc.id,
      },
      {
        rung: ACTION_RUNG.SHOW_UP,
        label: 'Sign up to volunteer',
        handler: 'signUpForVolunteerOpportunity',
        target: doc.id,
      },
    ],
    rankScore: 0,
    rankReasons: [],
    formation: {
      finite: true,
      spectacleCounters: false,
    },
    rawContent: d.description || '',
    scriptureRefs: [],
    createdAt: now,
    expiresAt: now + BRIEF_TTL_MS,
    _source: 'volunteerOpportunities',
  };
}

/**
 * buildCandidateFromBereanInsight — transform a Berean study insight doc.
 */
function buildCandidateFromInsight(doc, userId) {
  const d = doc.data();
  const now = Date.now();
  return {
    id: `study_${doc.id}_${userId}`,
    tier: 'SPIRITUAL',
    title: d.title || 'Daily Insight',
    summary: [],
    backingEntity: {
      kind: BACKING_KIND.STUDY,
      id: doc.id,
      verified: false,
    },
    truthLevel: TRUTH_LEVEL.VERIFIED,
    actions: [
      {
        rung: ACTION_RUNG.LEARN,
        label: 'Study this insight',
        handler: 'openBereanInsight',
        target: doc.id,
      },
      {
        rung: ACTION_RUNG.DISCUSS,
        label: 'Discuss with community',
        handler: 'openDiscussionForInsight',
        target: doc.id,
      },
    ],
    rankScore: 0,
    rankReasons: [],
    formation: {
      finite: true,
      spectacleCounters: false,
    },
    rawContent: d.content || d.body || '',
    scriptureRefs: d.scriptureRefs || [],
    createdAt: now,
    expiresAt: now + BRIEF_TTL_MS,
    _source: 'bereanInsights',
  };
}

/**
 * buildCandidateFromGlobalNews — transform a global news card doc.
 */
function buildCandidateFromGlobalNews(doc, userId) {
  const d = doc.data();
  const now = Date.now();
  return {
    id: `global_${doc.id}_${userId}`,
    tier: 'GLOBAL',
    title: d.title || 'Global Update',
    summary: [],
    backingEntity: {
      kind: BACKING_KIND.ORG,
      id: d.orgId || doc.id,
      verified: false,
    },
    truthLevel: d.truthLevel || TRUTH_LEVEL.DEVELOPING,
    actions: [
      {
        rung: ACTION_RUNG.PRAY,
        label: 'Pray for this situation',
        handler: 'recordIntelligenceAction',
        target: doc.id,
      },
      {
        rung: ACTION_RUNG.LEARN,
        label: 'Learn more',
        handler: 'openGlobalNewsCard',
        target: doc.id,
      },
    ],
    rankScore: 0,
    rankReasons: [],
    formation: {
      finite: true,
      spectacleCounters: false,
    },
    source: d.source || d.publisher || '',
    rawContent: d.content || d.body || '',
    scriptureRefs: d.scriptureRefs || [],
    createdAt: now,
    expiresAt: now + BRIEF_TTL_MS,
    _source: 'globalNewsCards',
  };
}

// ─── Candidate collection ─────────────────────────────────────────────────────

/**
 * collectCandidates — fetch all candidate cards from multiple sources.
 *
 * @param {object} ctx  User context
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<object[]>}  Array of unverified, unranked card candidates
 */
async function collectCandidates(ctx, db) {
  const { userId, churchIds, globalNewsOptIn } = ctx;
  const candidates = [];
  const now = new Date();

  // ── Church events ──────────────────────────────────────────────────────────
  if (churchIds && churchIds.length > 0) {
    try {
      const eventSnap = await db
        .collection('events')
        .where('churchId', 'in', churchIds.slice(0, 10))
        .where('startDate', '>=', now)
        .orderBy('startDate', 'asc')
        .limit(MAX_CANDIDATES_PER_SOURCE)
        .get();
      for (const doc of eventSnap.docs) {
        candidates.push(buildCandidateFromEvent(doc, userId));
      }
    } catch (err) {
      console.warn('[digestBuilder] events fetch error:', err.message);
    }
  }

  // ── Prayer requests from network ─────────────────────────────────────────
  try {
    // Open public prayer requests from the user's church network
    const prayerQuery = churchIds && churchIds.length > 0
      ? db.collection('prayers')
          .where('churchId', 'in', churchIds.slice(0, 10))
          .where('isOpen', '==', true)
          .orderBy('createdAt', 'desc')
          .limit(MAX_CANDIDATES_PER_SOURCE)
      : db.collection('prayers')
          .where('isPublic', '==', true)
          .where('isOpen', '==', true)
          .orderBy('createdAt', 'desc')
          .limit(5);

    const prayerSnap = await prayerQuery.get();
    for (const doc of prayerSnap.docs) {
      candidates.push(buildCandidateFromPrayer(doc, userId));
    }
  } catch (err) {
    console.warn('[digestBuilder] prayers fetch error:', err.message);
  }

  // ── Volunteer opportunities ───────────────────────────────────────────────
  try {
    const volSnap = await db
      .collection('volunteerOpportunities')
      .where('status', '==', 'open')
      .orderBy('createdAt', 'desc')
      .limit(MAX_CANDIDATES_PER_SOURCE)
      .get();
    for (const doc of volSnap.docs) {
      candidates.push(buildCandidateFromOpportunity(doc, userId));
    }
  } catch (err) {
    console.warn('[digestBuilder] volunteerOpportunities fetch error:', err.message);
  }

  // ── Berean insights ───────────────────────────────────────────────────────
  try {
    const insightSnap = await db
      .collection('bereanInsights')
      .where('publishedAt', '<=', now)
      .orderBy('publishedAt', 'desc')
      .limit(5)
      .get();
    for (const doc of insightSnap.docs) {
      candidates.push(buildCandidateFromInsight(doc, userId));
    }
  } catch (err) {
    console.warn('[digestBuilder] bereanInsights fetch error:', err.message);
  }

  // ── Global news (opt-in only) ─────────────────────────────────────────────
  if (globalNewsOptIn) {
    try {
      const newsSnap = await db
        .collection('globalNewsCards')
        .where('publishedAt', '<=', now)
        .where('active', '==', true)
        .orderBy('publishedAt', 'desc')
        .limit(5)
        .get();
      for (const doc of newsSnap.docs) {
        candidates.push(buildCandidateFromGlobalNews(doc, userId));
      }
    } catch (err) {
      console.warn('[digestBuilder] globalNewsCards fetch error:', err.message);
    }
  }

  return candidates;
}

// ─── Card processing pipeline ─────────────────────────────────────────────────

/**
 * processCandidate — verify, summarize, rank, and apply formation passes.
 * Returns null if the card fails any gate.
 *
 * @param {object} candidate  Raw candidate card
 * @param {object} ctx        User context
 * @returns {Promise<object|null>}
 */
async function processCandidate(candidate, ctx) {
  try {
    // Step 1: Verify backing entity
    const { verified, doc } = await resolveBackingEntity(
      candidate.backingEntity.kind,
      candidate.backingEntity.id,
    );
    if (!verified) {
      console.log(`[digestBuilder] Skipping unverified entity ${candidate.backingEntity.kind}/${candidate.backingEntity.id}`);
      return null;
    }
    candidate.backingEntity.verified = true;

    // Step 2: Generate Berean summary (fail-closed — skip if null)
    const summary = await withTimeout(
      callModel({
        task: 'intelligence.summarize',
        input: {
          title: candidate.title,
          backingEntityKind: candidate.backingEntity.kind,
          rawContent: candidate.rawContent || '',
          scriptureRefs: candidate.scriptureRefs || [],
        },
        context: ctx,
        userId: ctx.userId,
      }),
    );

    if (summary && Array.isArray(summary) && summary.length > 0) {
      candidate.summary = summary.slice(0, 3);
    } else {
      // Fallback: use title as single summary bullet
      candidate.summary = [candidate.title];
    }

    // Step 3: Rank the card
    const { rankScore, rankReasons } = rankCard(candidate, ctx);
    candidate.rankScore = rankScore;
    candidate.rankReasons = rankReasons;

    // Step 4: Apply formation passes (these create new objects)
    let card = stripSpectacleCounters(candidate);
    card = enforceGeo(card);
    card = enforcePoliticsFilter(card);

    // Clean up internal-only fields
    delete card.rawContent;
    delete card.scriptureRefs;
    delete card._source;

    // Step 5: Validate the final card
    assertCard(card);

    return card;
  } catch (err) {
    console.warn(`[digestBuilder] processCandidate failed for ${candidate.id}:`, err.message);
    return null;
  }
}

// ─── Main export ──────────────────────────────────────────────────────────────

/**
 * buildUserBrief — build and persist an intelligence brief for a user.
 *
 * @param {string} userId
 * @param {FirebaseFirestore.Firestore} db  Admin Firestore instance
 * @returns {Promise<{ brief: object, cards: object[], generatedAt: number }>}
 */
async function buildUserBrief(userId, db) {
  const generatedAt = Date.now();

  // 1. Enforce digest cadence
  const canRebuild = await enforceDigestCadence(userId, db);
  if (!canRebuild) {
    // Return existing brief
    const existingSnap = await db.collection('intelligence_briefs').doc(userId).get();
    if (existingSnap.exists) {
      const existing = existingSnap.data();
      // Fetch associated cards
      const cardsSnap = await db
        .collection('intelligence_cards')
        .where('userId', '==', userId)
        .where('expiresAt', '>', generatedAt)
        .limit(10)
        .get();
      const cards = cardsSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
      return { brief: existing, cards, generatedAt };
    }
  }

  // 2. Fetch user context
  const ctx = await fetchUserContext(userId, db);

  // 3. Collect candidates from all sources
  const candidates = await collectCandidates(ctx, db);
  console.log(`[digestBuilder] ${userId}: ${candidates.length} candidates collected`);

  if (candidates.length === 0) {
    console.warn(`[digestBuilder] ${userId}: no candidates found — empty brief`);
  }

  // 4-7. Process candidates in parallel (verify, summarize, rank, formation passes)
  // Max 10 concurrent to avoid quota exhaustion
  const CONCURRENCY = 10;
  const processedCards = [];

  for (let i = 0; i < candidates.length; i += CONCURRENCY) {
    const batch = candidates.slice(i, i + CONCURRENCY);
    const results = await Promise.all(
      batch.map((candidate) => processCandidate(candidate, ctx)),
    );
    for (const r of results) {
      if (r !== null) processedCards.push(r);
    }
  }

  // 8. Sort by rankScore descending, then apply brief cap
  processedCards.sort((a, b) => b.rankScore - a.rankScore);
  const finalCards = enforceBriefCap(processedCards);

  // Check loop closure (log unresolved — do not block brief generation)
  const { unresolved } = assertLoopClosure(finalCards, ctx.priorActions || []);
  if (unresolved.length > 0) {
    console.log(`[digestBuilder] ${userId}: ${unresolved.length} prior actions without follow-up card`);
  }

  // 9. Write cards to intelligence_cards/{cardId}
  const batch = db.batch();
  for (const card of finalCards) {
    const cardRef = db.collection('intelligence_cards').doc(card.id);
    batch.set(cardRef, { ...card, userId, writtenAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  }
  await batch.commit();

  // 10. Write brief to intelligence_briefs/{userId}
  const brief = {
    userId,
    cardIds: finalCards.map((c) => c.id),
    cardCount: finalCards.length,
    generatedAt,
    expiresAt: generatedAt + BRIEF_TTL_MS,
    builtAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await db.collection('intelligence_briefs').doc(userId).set(brief, { merge: true });

  // Write audit record for cadence tracking
  await db
    .collection('intelligence_briefs')
    .doc(userId)
    .collection('audit')
    .add({
      builtAt: admin.firestore.FieldValue.serverTimestamp(),
      cardCount: finalCards.length,
    });

  console.log(`[digestBuilder] ${userId}: brief built with ${finalCards.length} cards`);

  return { brief, cards: finalCards, generatedAt };
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = { buildUserBrief };

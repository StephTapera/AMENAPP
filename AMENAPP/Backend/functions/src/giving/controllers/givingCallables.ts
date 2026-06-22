// givingCallables.ts
// AMEN Giving — Firebase Cloud Functions (gen2) callables.
// All onCall functions require App Check.

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { guardianReview } from '../services/BenevolenceGuardian';
import { rankOrganizations } from '../services/GivingRankingEngine';
import { GivingProfile, BenevolenceRequest } from '../models/givingModels';

const db = admin.firestore();

// Helper: require App Check
function requireAppCheck(context: any): void {
  if (!context.app) {
    throw new HttpsError('failed-precondition', 'App Check verification required.');
  }
}

// Helper: require auth
function requireAuth(context: any): string {
  if (!context.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }
  return context.auth.uid;
}

// ─── saveGivingProfile ────────────────────────────────────────────────────────
// Saves user intent profile and triggers a feed rank refresh.

export const saveGivingProfile = onCall(async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);
  const profile = request.data.profile as GivingProfile;

  if (!profile || !Array.isArray(profile.causePreferences)) {
    throw new HttpsError('invalid-argument', 'Invalid profile data.');
  }

  await db.collection('giving_profiles').doc(uid).set({
    ...profile,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  // Trigger async rank refresh
  await refreshFeedCandidates(uid, profile);

  return { success: true };
});

// ─── submitBenevolenceRequest ─────────────────────────────────────────────────
// Creates a benevolence request draft and kicks off verification + Guardian review.

export const submitBenevolenceRequest = onCall(async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);
  const data = request.data as Partial<BenevolenceRequest & { title: string; summary: string }>;

  if (!data.title || !data.summary || !data.requestedAmount || !data.category) {
    throw new HttpsError('invalid-argument', 'Missing required request fields.');
  }

  // Check: only one active request per person
  const activeRequests = await db.collection('benevolence_requests')
    .where('requesterUserId', '==', uid)
    .where('status', 'in', ['verification_pending', 'guardian_review', 'human_review', 'approved', 'active'])
    .get();
  if (!activeRequests.empty) {
    throw new HttpsError('failed-precondition', 'You already have an active request. Only one request at a time is permitted.');
  }

  // Run Guardian review
  const guardianResult = await guardianReview(
    { title: data.title, summary: data.summary, requestedAmount: data.requestedAmount, category: data.category },
    uid,
    db
  );

  const docRef = await db.collection('benevolence_requests').add({
    requesterUserId: uid,
    churchId: data.churchId ?? null,
    verificationType: data.verificationType ?? 'pastor_elder',
    category: data.category,
    title: data.title,
    summary: data.summary,
    requestedAmount: data.requestedAmount,
    approvedCapAmount: null,
    currency: 'usd',
    status: guardianResult.decision === 'cleared' ? 'verification_pending' : 'guardian_review',
    guardianStatus: guardianResult.decision === 'escalate_human' ? 'escalated' : guardianResult.decision,
    humanReviewStatus: guardianResult.decision === 'escalate_human' ? 'pending' : null,
    needsReceipts: true,
    fulfillmentState: 'not_started',
    guardianFlags: guardianResult.riskFlags,
    guardianReasons: guardianResult.reasons,
    expiresAt: admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)  // 30 days
    ),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Log moderation event
  await db.collection('moderation_events').add({
    resourceType: 'benevolence_request',
    resourceId: docRef.id,
    userId: uid,
    decision: guardianResult.decision,
    confidence: guardianResult.confidence,
    riskFlags: guardianResult.riskFlags,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    requestId: docRef.id,
    status: docRef.id ? 'submitted' : 'failed',
    guardianDecision: guardianResult.decision,
  };
});

// ─── getRankedFeed ────────────────────────────────────────────────────────────
// Returns a ranked feed of organizations for the authenticated user.

export const getRankedFeed = onCall(async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  // Load profile
  const profileDoc = await db.collection('giving_profiles').doc(uid).get();
  const profile = profileDoc.exists
    ? (profileDoc.data() as GivingProfile)
    : { causePreferences: [], geographicPreference: 'Balanced', theologicalAlignment: 'Denominationally Neutral', givingStylePreferences: [], locationMode: 'none', rankProfileVersion: 1 } as GivingProfile;

  // Load orgs
  const orgsSnap = await db.collection('organizations')
    .where('isActive', '==', true)
    .where('rankingEligibility', '==', true)
    .limit(60)
    .get();
  const orgs = orgsSnap.docs.map(d => ({ id: d.id, ...d.data() } as any));

  // Load active disaster
  const disasterSnap = await db.collection('disaster_events')
    .where('isActive', '==', true)
    .orderBy('startedAt', 'desc')
    .limit(1)
    .get();
  const disaster = !disasterSnap.empty ? disasterSnap.docs[0].data() as any : undefined;

  // Rank
  const ranked = rankOrganizations(orgs, profile, disaster);

  // Cache ranked results (for explanation tokens)
  const batch = db.batch();
  const cacheRef = db.collection('giving_feed_cache').doc(uid);
  batch.set(cacheRef, {
    rankedOrgIds: ranked.map(r => r.orgId),
    explanationTokens: Object.fromEntries(ranked.map(r => [r.orgId, r.tokens])),
    generatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();

  return { ranked: ranked.slice(0, 30) };
});

// ─── generateAnnualReview ─────────────────────────────────────────────────────
// Aggregates giving data for the annual review. Server-side only — no income stored.

export const generateAnnualReview = onCall(async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);
  const year = request.data.year ?? new Date().getFullYear();

  const receiptsSnap = await db.collection('receipts')
    .where('userId', '==', uid)
    .where('taxYear', '==', year)
    .get();

  let churchTotal = 0;
  let nonprofitTotal = 0;
  let localTotal = 0;
  let globalTotal = 0;
  let recurringTotal = 0;
  const destinationIds = new Set<string>();

  for (const doc of receiptsSnap.docs) {
    const receipt = doc.data();
    const amount = receipt.amount as number;
    destinationIds.add(receipt.destinationId);

    if (receipt.destinationType === 'church') {
      churchTotal += amount;
      localTotal += amount;
    } else {
      nonprofitTotal += amount;
      // Look up org locality
      const orgDoc = await db.collection('organizations').doc(receipt.destinationId).get();
      if (orgDoc.exists) {
        const orgData = orgDoc.data() as any;
        const isLocal = (orgData.serviceRegions as any[] || []).some((r: any) => r.isLocal);
        if (isLocal) localTotal += amount;
        else globalTotal += amount;
      }
    }
  }

  const reviewDoc = {
    userId: uid,
    year,
    churchGivingTotal: churchTotal,
    nonprofitGivingTotal: nonprofitTotal,
    localGivingTotal: localTotal,
    globalGivingTotal: globalTotal,
    recurringGivingTotal: recurringTotal,
    destinationCount: destinationIds.size,
    generatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await db.collection('annual_reviews').doc(`${uid}_${year}`).set(reviewDoc, { merge: true });
  return { review: reviewDoc };
});

// ─── Internal: refresh feed candidates ───────────────────────────────────────

async function refreshFeedCandidates(uid: string, profile: GivingProfile): Promise<void> {
  try {
    const orgsSnap = await db.collection('organizations')
      .where('isActive', '==', true)
      .where('rankingEligibility', '==', true)
      .limit(60)
      .get();
    const orgs = orgsSnap.docs.map(d => ({ id: d.id, ...d.data() } as any));
    const ranked = rankOrganizations(orgs, profile);
    await db.collection('giving_feed_cache').doc(uid).set({
      rankedOrgIds: ranked.map(r => r.orgId),
      explanationTokens: Object.fromEntries(ranked.map(r => [r.orgId, r.tokens])),
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error('Feed candidate refresh failed:', e);
  }
}

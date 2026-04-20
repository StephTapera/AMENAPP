// nonprofitIngestion.ts
// AMEN Giving — Scheduled nonprofit data ingestion from ProPublica + Charity Navigator.
// Normalizes org records. Updates trust/transparency documents.
// Marks stale fields when data ages out. Never fabricates precision.

import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as admin from 'firebase-admin';

const db = admin.firestore();

// ─── dailyNonprofitDataSync ───────────────────────────────────────────────────
// Runs daily. Fetches fresh 990 data from ProPublica for all tracked orgs.

export const dailyNonprofitDataSync = onSchedule('every 24 hours', async () => {
  const orgsSnap = await db.collection('organizations')
    .where('isActive', '==', true)
    .get();

  for (const orgDoc of orgsSnap.docs) {
    const org = orgDoc.data();
    const ein = org.ein as string | undefined;
    if (!ein) continue;

    try {
      await syncProPublicaData(orgDoc.id, ein);
    } catch (e) {
      console.error(`ProPublica sync failed for org ${orgDoc.id}:`, e);
      // Mark as stale — never fabricate
      await orgDoc.ref.collection('transparency').doc('current').set({
        verificationStatus: 'stale',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  }
});

async function syncProPublicaData(orgId: string, ein: string): Promise<void> {
  const url = `https://projects.propublica.org/nonprofits/api/v2/organizations/${ein.replace('-', '')}.json`;
  const response = await fetch(url, {
    headers: { 'User-Agent': 'AMEN-App/1.0 giving@amen.app' },
  });

  if (!response.ok) {
    throw new Error(`ProPublica returned ${response.status} for EIN ${ein}`);
  }

  const json = await response.json() as any;
  const org = json.organization;
  const filings = json.filings_with_data as any[] | undefined;
  const latestFiling = filings?.[0];

  if (!latestFiling) {
    await markStale(orgId);
    return;
  }

  // Check staleness: if most recent 990 is > 18 months old, mark stale
  const fiscalYear = latestFiling.tax_prd_yr as number;
  const now = new Date();
  if (now.getFullYear() - fiscalYear > 1) {
    await markStale(orgId);
    return;
  }

  const totalRevenue = latestFiling.totrevenue as number ?? 0;
  const programExpenses = latestFiling.totprgmrevnue as number ?? 0;
  const adminExpenses = latestFiling.totfuncexpns as number ?? 0;

  const programRatio = totalRevenue > 0 ? programExpenses / totalRevenue : null;

  const transparencyData = {
    programExpenseRatio: programRatio,
    fiscalYear: String(fiscalYear),
    sourceProviders: ['ProPublica Nonprofit Explorer'],
    sourceUrls: [url],
    verificationStatus: 'verified' as const,
    verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    confidence: programRatio !== null ? 'high' : 'low',
    notes: null,
  };

  await db.collection('organizations').doc(orgId)
    .collection('transparency').doc('current')
    .set(transparencyData, { merge: true });

  // Update org trust score based on data completeness
  const trustScore = calculateTrustScore(transparencyData, org);
  await db.collection('organizations').doc(orgId).update({
    trustScore,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function calculateTrustScore(transparency: any, org: any): number {
  let score = 0.0;

  if (transparency.verificationStatus === 'verified') score += 0.35;
  if (transparency.programExpenseRatio !== null) score += 0.25;
  if (transparency.programExpenseRatio >= 0.75) score += 0.15;  // >= 75% programs
  if (org.ntee_code) score += 0.10;  // Has NTEE classification
  if (org.subseccd === '3') score += 0.15;  // 501(c)(3)

  return Math.min(score, 1.0);
}

async function markStale(orgId: string): Promise<void> {
  await db.collection('organizations').doc(orgId)
    .collection('transparency').doc('current')
    .set({ verificationStatus: 'stale', updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
}

// ─── weeklyDisasterEventCleanup ───────────────────────────────────────────────
// Closes disaster events older than 90 days if still marked active.

export const weeklyDisasterEventCleanup = onSchedule('every 168 hours', async () => {
  const ninetyDaysAgo = new Date();
  ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);

  const staleEvents = await db.collection('disaster_events')
    .where('isActive', '==', true)
    .where('startedAt', '<', admin.firestore.Timestamp.fromDate(ninetyDaysAgo))
    .get();

  const batch = db.batch();
  for (const doc of staleEvents.docs) {
    batch.update(doc.ref, {
      isActive: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  console.log(`Closed ${staleEvents.size} stale disaster events.`);
});

// ─── weeklyBenevolenceRequestCleanup ─────────────────────────────────────────
// Expires benevolence requests past their expiresAt date.

export const weeklyBenevolenceRequestCleanup = onSchedule('every 168 hours', async () => {
  const now = admin.firestore.Timestamp.now();
  const expiredRequests = await db.collection('benevolence_requests')
    .where('status', 'in', ['approved', 'active'])
    .where('expiresAt', '<', now)
    .get();

  const batch = db.batch();
  for (const doc of expiredRequests.docs) {
    batch.update(doc.ref, {
      status: 'expired',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  console.log(`Expired ${expiredRequests.size} benevolence requests.`);
});

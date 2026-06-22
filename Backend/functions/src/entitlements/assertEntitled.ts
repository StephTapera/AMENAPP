// assertEntitled.ts — server-side entitlement check for Cloud Functions
// Not a deployed function; imported as a utility by other CFs to enforce tier gates.
// Throws ENTITLEMENT_REQUIRED if the user's Firestore tier is insufficient.
import * as admin from 'firebase-admin'

type ServerCapability =
  | 'bereanContextInjection' | 'verseResonance' | 'cohortResonance'
  | 'givingPortfolio' | 'continuityCrossDevice' | 'seasonsInsights'
  | 'matchFeedbackExplained' | 'volunteerNeedsPosting' | 'groupFormationAnalytics'
  | 'communityHealth' | 'teachingAnalytics'

const PREMIUM_CAPS = new Set([
  'bereanContextInjection', 'verseResonance', 'cohortResonance',
  'givingPortfolio', 'continuityCrossDevice', 'seasonsInsights',
  'matchFeedbackExplained'
])
const CHURCH_CAPS = new Set([
  'volunteerNeedsPosting', 'groupFormationAnalytics', 'communityHealth'
])
const CREATOR_CAPS = new Set(['teachingAnalytics'])

/**
 * Assert that `uid` holds the tier required for `capability`.
 * Reads `entitlements/{uid}` from Firestore; defaults to 'free' if missing.
 *
 * @throws Error with code ENTITLEMENT_REQUIRED if access is denied.
 *
 * Usage:
 *   await assertEntitled(context.auth!.uid, 'bereanContextInjection')
 */
export async function assertEntitled(uid: string, capability: ServerCapability): Promise<void> {
  const db = admin.firestore()
  const snap = await db.doc(`entitlements/${uid}`).get()
  const tier: string = snap.data()?.tier ?? 'free'

  if (PREMIUM_CAPS.has(capability) && !['premium', 'church', 'creator'].includes(tier)) {
    throw new Error(`ENTITLEMENT_REQUIRED: ${capability} requires premium tier`)
  }
  if (CHURCH_CAPS.has(capability) && !['church', 'creator'].includes(tier)) {
    throw new Error(`ENTITLEMENT_REQUIRED: ${capability} requires church tier`)
  }
  if (CREATOR_CAPS.has(capability) && tier !== 'creator') {
    throw new Error(`ENTITLEMENT_REQUIRED: ${capability} requires creator tier`)
  }
}

/**
 * Berean Trust Architecture — Firebase Callable Exports
 * Layer 1–6 pipeline wired as HTTPS callables (gen-2).
 *
 * All callables require Firebase Auth. App Check is enforced (failOpen: false)
 * on the pipeline callable; other callables carry the same posture via options.
 *
 * Feature flag document: featureFlags/trustArchitecture
 * Firestore collections: see firestore.rules §bereanTrustArchitecture block
 */

import * as functions from 'firebase-functions/v2/https'
import * as admin from 'firebase-admin'
import { runBereanPipeline } from './constitutionalPipeline'
import { readMemory, writeMemory, deleteMemory, lockMemory, deleteAllUserMemory } from './memoryStore'
import { submitFeedback, getFeedbackStats } from './feedbackCapture'
import { runEvalSuite, checkDeploymentGate } from './evalFramework'
import { EVAL_TEST_CASES } from './evalTestCases'

const db = admin.firestore()

// ── Feature flag helper ────────────────────────────────────────────────────────

async function isFlagEnabled(flag: string): Promise<boolean> {
  const doc = await db.doc('featureFlags/trustArchitecture').get()
  return doc.data()?.[flag] === true
}

// ── 1. bereanConstitutionalPipeline ───────────────────────────────────────────
// Runs the full 7-stage constitutional pipeline for a user query.
// Requires: auth, App Check enforced.
// Input:  { query: string, sessionId: string, mode?: string, conversationHistory?: object[] }
// Output: { response: string, traceId: string, trustScore?: number }

export const bereanConstitutionalPipeline = functions.onCall(
  {
    enforceAppCheck: true,
    region: 'us-central1',
    secrets: ['ANTHROPIC_API_KEY', 'GEMINI_API_KEY', 'BIBLE_API_KEY'],
  },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError('unauthenticated', 'Authentication required.')
    }

    const uid = request.auth.uid
    const { query, sessionId, mode, conversationHistory } = request.data as {
      query: string
      sessionId: string
      mode?: string
      conversationHistory?: object[]
    }

    if (!query || typeof query !== 'string' || query.trim().length === 0) {
      throw new functions.HttpsError('invalid-argument', 'query must be a non-empty string.')
    }
    if (!sessionId || typeof sessionId !== 'string') {
      throw new functions.HttpsError('invalid-argument', 'sessionId is required.')
    }

    const output = await runBereanPipeline({
      userId: uid,
      query,
      sessionId,
      mode,
      conversationHistory,
    })

    return { response: output.response, traceId: output.traceId, trustScore: output.trustScore }
  }
)

// ── 2. bereanGetMemory ────────────────────────────────────────────────────────
// Returns Berean memory entries for the authenticated user.
// Input:  { categories?: string[] }
// Output: { entries: MemoryEntry[] }

export const bereanGetMemory = functions.onCall(
  { enforceAppCheck: true, region: 'us-central1' },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError('unauthenticated', 'Authentication required.')
    }

    const uid = request.auth.uid
    const { categories } = (request.data ?? {}) as { categories?: string[] }

    const entries = await readMemory(uid, categories)
    return { entries }
  }
)

// ── 3. bereanDeleteMemory ─────────────────────────────────────────────────────
// Deletes a single memory entry for the authenticated user.
// Input:  { entryId: string }

export const bereanDeleteMemory = functions.onCall(
  { enforceAppCheck: true, region: 'us-central1' },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError('unauthenticated', 'Authentication required.')
    }

    const uid = request.auth.uid
    const { entryId } = request.data as { entryId: string }

    if (!entryId || typeof entryId !== 'string') {
      throw new functions.HttpsError('invalid-argument', 'entryId is required.')
    }

    await deleteMemory(uid, entryId)
    return { success: true }
  }
)

// ── 4. bereanToggleMemoryLock ─────────────────────────────────────────────────
// Locks or unlocks a memory entry to prevent AI modification.
// Input:  { entryId: string, locked: boolean }

export const bereanToggleMemoryLock = functions.onCall(
  { enforceAppCheck: true, region: 'us-central1' },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError('unauthenticated', 'Authentication required.')
    }

    const uid = request.auth.uid
    const { entryId, locked } = request.data as { entryId: string; locked: boolean }

    if (!entryId || typeof entryId !== 'string') {
      throw new functions.HttpsError('invalid-argument', 'entryId is required.')
    }
    if (typeof locked !== 'boolean') {
      throw new functions.HttpsError('invalid-argument', 'locked must be a boolean.')
    }

    await lockMemory(uid, entryId, locked)
    return { success: true, locked }
  }
)

// ── 5. bereanUpdateMemory ─────────────────────────────────────────────────────
// Updates the content of a memory entry. Only editable (unlocked) entries may
// be updated. The content field is the only client-mutable field — all
// provenance, category, and lock fields are server-authoritative.
// Input:  { entryId: string, content: string }

export const bereanUpdateMemory = functions.onCall(
  { enforceAppCheck: true, region: 'us-central1' },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError('unauthenticated', 'Authentication required.')
    }

    const uid = request.auth.uid
    const { entryId, content } = request.data as { entryId: string; content: string }

    if (!entryId || typeof entryId !== 'string') {
      throw new functions.HttpsError('invalid-argument', 'entryId is required.')
    }
    if (!content || typeof content !== 'string' || content.trim().length === 0) {
      throw new functions.HttpsError('invalid-argument', 'content must be a non-empty string.')
    }

    const ref = db.doc(`users/${uid}/bereanMemory/${entryId}`)
    const snap = await ref.get()

    if (!snap.exists) {
      throw new functions.HttpsError('not-found', 'Memory entry not found.')
    }
    if (snap.data()?.locked === true) {
      throw new functions.HttpsError(
        'failed-precondition',
        'This memory entry is locked and cannot be edited. Unlock it first.'
      )
    }

    await ref.update({ content, updatedAt: admin.firestore.FieldValue.serverTimestamp() })
    return { success: true }
  }
)

// ── 6. bereanDeleteAllMemory ──────────────────────────────────────────────────
// Deletes ALL memory entries for the authenticated user (GDPR / Right to Erasure).
// Locked entries are also deleted when the user explicitly requests full erasure.

export const bereanDeleteAllMemory = functions.onCall(
  { enforceAppCheck: true, region: 'us-central1' },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError('unauthenticated', 'Authentication required.')
    }

    const uid = request.auth.uid
    await deleteAllUserMemory(uid)
    return { success: true }
  }
)

// ── 7. bereanSubmitFeedback ───────────────────────────────────────────────────
// Captures thumbs-up / thumbs-down feedback on a pipeline response.
// Input:  { traceId: string, sessionId: string, rating: 'positive' | 'negative', comment?: string }

export const bereanSubmitFeedback = functions.onCall(
  { enforceAppCheck: true, region: 'us-central1' },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError('unauthenticated', 'Authentication required.')
    }

    const uid = request.auth.uid
    const { traceId, sessionId, rating, comment } = request.data as {
      traceId: string
      sessionId: string
      rating: 'positive' | 'negative'
      comment?: string
    }

    if (!traceId || typeof traceId !== 'string') {
      throw new functions.HttpsError('invalid-argument', 'traceId is required.')
    }
    if (!sessionId || typeof sessionId !== 'string') {
      throw new functions.HttpsError('invalid-argument', 'sessionId is required.')
    }
    if (rating !== 'positive' && rating !== 'negative') {
      throw new functions.HttpsError('invalid-argument', 'rating must be "positive" or "negative".')
    }

    const feedbackId = await submitFeedback({ userId: uid, traceId, sessionId, rating, comment })
    return { success: true, feedbackId }
  }
)

// ── 8. bereanRunEvals ─────────────────────────────────────────────────────────
// Runs the full eval suite across all categories and returns pass rates + gate check.
// Admin-only (user document must have admin: true in Firestore).
// Returns: { results: EvalResults, gateCheck: DeploymentGateResult }

export const bereanRunEvals = functions.onCall(
  {
    enforceAppCheck: true,
    region: 'us-central1',
    timeoutSeconds: 540,
    memory: '2GiB',
    secrets: ['ANTHROPIC_API_KEY', 'GEMINI_API_KEY', 'BIBLE_API_KEY'],
  },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError('unauthenticated', 'Authentication required.')
    }

    // Admin role check — user document must have admin: true
    const userDoc = await db.doc(`users/${request.auth.uid}`).get()
    if (userDoc.data()?.admin !== true) {
      throw new functions.HttpsError(
        'permission-denied',
        'Only admin users may run the eval suite.'
      )
    }

    const categories = Array.from(new Set(EVAL_TEST_CASES.map((tc) => tc.category)))
    const results = await runEvalSuite(categories)
    const gateCheck = checkDeploymentGate(results)

    // Persist eval run for audit trail
    await db.collection('bereanEvalRuns').doc(Date.now().toString()).set({
      runAt: admin.firestore.FieldValue.serverTimestamp(),
      triggeredBy: request.auth.uid,
      results,
      gateCheck,
    })

    return { results, gateCheck }
  }
)

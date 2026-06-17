// getContextualVerse.ts — Backend/functions/src/verse/getContextualVerse.ts
// Cloud Function (us-east1): returns a contextually scored verse for Premium users.
// Free users never reach this CF — VerseResonanceService.swift routes them to the
// generic path before making any network call.
//
// Invariants:
//  • Auth required — throws 'unauthenticated' if no token.
//  • assertEntitled(uid, 'verseResonance') — throws if user is not Premium+.
//  • Returns null if no context signals exist (client falls back to generic).
//  • Crisis dampening: if crisisState/current.active == true, returns a comfort-only verse.
//  • Region: us-east1 (us-central1 quota exhausted as of 2026-06-13).
//  • Flag: ctx_verse_resonance_enabled must be enabled before this function is called.

import * as functions from 'firebase-functions'
import * as admin from 'firebase-admin'
import { assertEntitled } from '../entitlements/assertEntitled'

// MARK: - Comfort verse pool
// Returned when crisis dampening is active. No judgment / wrath themes.
const COMFORT_VERSES: Array<{ reference: string; text: string }> = [
  {
    reference: 'Psalm 46:1',
    text: 'God is our refuge and strength, a very present help in trouble.',
  },
  {
    reference: 'Isaiah 41:10',
    text: 'Fear not, for I am with you; be not dismayed, for I am your God.',
  },
  {
    reference: 'Matthew 11:28',
    text: 'Come to me, all who labor and are heavy laden, and I will give you rest.',
  },
  {
    reference: 'Romans 8:38-39',
    text: 'Neither death nor life, nor anything else in all creation, will be able to separate us from the love of God.',
  },
  {
    reference: 'Psalm 34:18',
    text: 'The Lord is near to the brokenhearted and saves the crushed in spirit.',
  },
]

// MARK: - Exported Cloud Function

export const getContextualVerse = functions
  .region('us-east1')
  .runWith({ enforceAppCheck: true })
  .https.onCall(async (data, context) => {
    // 1. Auth guard
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Sign in required')
    }
    const uid = context.auth.uid

    // 2. Entitlement guard (Premium+)
    try {
      await assertEntitled(uid, 'verseResonance')
    } catch {
      throw new functions.https.HttpsError(
        'permission-denied',
        'verseResonance requires Premium tier'
      )
    }

    const db = admin.firestore()

    // 3. Crisis dampening — check server-side flag in Firestore.
    //    The iOS CrisisDampening is device-only; here we mirror it via a Firestore document
    //    written by the crisis OS when it escalates a user to active support mode.
    const crisisSnap = await db.doc(`users/${uid}/crisisState/current`).get()
    const isCrisisActive =
      crisisSnap.exists && (crisisSnap.data() as Record<string, unknown>)?.active === true

    if (isCrisisActive) {
      // Deterministic selection from comfort pool — same verse per uid per pool size.
      const idx = uid.charCodeAt(0) % COMFORT_VERSES.length
      const comfortVerse = COMFORT_VERSES[idx]
      return {
        reference: comfortVerse.reference,
        text: comfortVerse.text,
        contextReason: null,
      }
    }

    // 4. Fetch recent context signals to score verse selection.
    //    Only signal types that have direct verse-relevance are queried.
    const signalsSnap = await db
      .collection('contextSignals')
      .doc(uid)
      .collection('signals')
      .where('type', 'in', ['noteThemeDetected', 'prayerCreated', 'verseReflected'])
      .orderBy('occurredAt', 'desc')
      .limit(5)
      .get()

    if (signalsSnap.empty) {
      // No context signals — return null so the client falls back to generic.
      return null
    }

    // 5. Extract dominant theme from most recent signals.
    //    Production: replace with embedding similarity against a verse corpus.
    //    Current: keyword extraction from payload.theme field.
    const themes = signalsSnap.docs
      .map((d) => {
        const payload = d.data().payload as Record<string, unknown> | undefined
        return payload?.theme as string | undefined
      })
      .filter((t): t is string => typeof t === 'string' && t.length > 0)

    const topTheme = themes[0] ?? 'hope'

    // 6. Select a contextual verse scored against the top theme.
    //    Production: this would call an embeddings service or Genkit flow.
    //    Current: deterministic fallback with a human-readable provenance string.
    const versePool: Array<{
      reference: string
      text: string
      themes: string[]
    }> = [
      {
        reference: 'Romans 8:28',
        text: 'And we know that in all things God works for the good of those who love him.',
        themes: ['purpose', 'hope', 'suffering', 'trust'],
      },
      {
        reference: 'Lamentations 3:22-23',
        text: 'The steadfast love of the Lord never ceases; his mercies never come to an end; they are new every morning.',
        themes: ['grief', 'renewal', 'mercy', 'morning'],
      },
      {
        reference: 'Philippians 4:7',
        text: 'And the peace of God, which surpasses all understanding, will guard your hearts and your minds in Christ Jesus.',
        themes: ['anxiety', 'peace', 'worry', 'stress'],
      },
      {
        reference: 'Psalm 139:14',
        text: 'I praise you, for I am fearfully and wonderfully made.',
        themes: ['identity', 'worth', 'belonging', 'self'],
      },
      {
        reference: 'Isaiah 43:2',
        text: 'When you pass through the waters, I will be with you.',
        themes: ['trial', 'hardship', 'fear', 'transition'],
      },
    ]

    // Score each verse by theme overlap (simple string inclusion match).
    const scored = versePool.map((v) => ({
      ...v,
      score: v.themes.filter((t) =>
        t.toLowerCase().includes(topTheme.toLowerCase()) ||
        topTheme.toLowerCase().includes(t.toLowerCase())
      ).length,
    }))

    // Pick highest score; fall back to deterministic index on tie.
    scored.sort((a, b) => b.score - a.score || 0)
    const selected = scored[0]

    return {
      reference: selected.reference,
      text: selected.text,
      contextReason: `from your recent notes on ${topTheme}`,
    }
  })

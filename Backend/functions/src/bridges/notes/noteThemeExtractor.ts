// noteThemeExtractor.ts
// AMEN Backend — bridges/notes
//
// Cloud Functions (us-east1) for the note→match and note→give bridges.
//
// Functions exported:
//   extractNoteThemes    — called by iOS when a note is saved with Tier-C consent
//   getVettedOrgForTheme — called by NoteGiveBridge to fetch a verified giving org
//
// Deploy (from repo root, targeting creator codebase, never bare):
//   firebase deploy --only functions:creator:extractNoteThemes --project <project>
//   firebase deploy --only functions:creator:getVettedOrgForTheme --project <project>
//
// Invariants:
//   • Both functions require authentication — unauthenticated calls throw 'unauthenticated'
//   • extractNoteThemes never stores PII; it stores theme labels + noteID only
//   • getVettedOrgForTheme only returns orgs where verified == true (ECFA/CharityNavigator)
//   • All new Firestore writes go to pendingSignals/{uid}/signals (consumed by ContextBus)
//   • Theme taxonomy is keyword-based now; swap inner loop for embedding cosine sim later
//   • consentEdgeRequired field matches ConsentEdge Swift enum rawValues exactly

import * as functions from 'firebase-functions'
import * as admin from 'firebase-admin'

// ---------------------------------------------------------------------------
// Theme taxonomy
// ---------------------------------------------------------------------------

const THEME_TAXONOMY: string[] = [
  'expository-teaching',
  'missions',
  'worship',
  'prayer',
  'community',
  'justice',
  'discipleship',
  'evangelism',
  'healing',
  'spiritual-formation',
  'grief',
  'hope',
  'faith',
  'grace',
  'family',
  'leadership'
]

// ---------------------------------------------------------------------------
// extractNoteThemes
// ---------------------------------------------------------------------------

/**
 * Called by iOS when a note is saved and the user has granted
 * ConsentEdge.notesToMatching. Detects up to 3 themes from `noteContent`
 * and writes pending ContextSignal records to Firestore for the ContextBus
 * iOS-side fan-out to NoteMatchBridge.
 *
 * Request: { noteContent: string, noteID: string }
 * Response: { themes: string[] }
 */
export const extractNoteThemes = functions
  .region('us-east1')
  .runWith({ enforceAppCheck: true })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Sign in required')
    }
    const uid = context.auth.uid
    const { noteContent, noteID } = data as { noteContent: string; noteID: string }

    if (!noteContent || typeof noteContent !== 'string') {
      return { themes: [] }
    }

    // Keyword-based theme detection — O(|taxonomy| × |keywords|), sub-ms for
    // this vocabulary size. Swap with embedding cosine similarity when infra
    // is ready without changing the contract shape.
    const content = noteContent.toLowerCase()
    const detectedThemes = THEME_TAXONOMY.filter(theme => {
      const keywords = theme.split('-')
      return keywords.some(kw => content.includes(kw))
    })

    if (detectedThemes.length === 0) {
      return { themes: [] }
    }

    // Cap at 3 themes per note to keep churchDNA delta volume bounded.
    const topThemes = detectedThemes.slice(0, 3)

    // Write a pending ContextSignal for each theme so the iOS ContextBus can
    // fan out to NoteMatchBridge on the next session start.
    const db = admin.firestore()
    const batch = db.batch()

    for (const theme of topThemes) {
      const ref = db
        .collection('pendingSignals')
        .doc(uid)
        .collection('signals')
        .doc()

      batch.set(ref, {
        type: 'noteThemeDetected',
        tierCeiling: 'c',                         // Tier-C: may reach server
        payload: { theme, noteID },
        subjectRefs: [{ nodeType: 'note', nodeID: noteID }],
        occurredAt: admin.firestore.FieldValue.serverTimestamp(),
        decayHalfLifeDays: 14,
        consentEdgeRequired: 'notesToMatching'     // matches ConsentEdge Swift rawValue
      })
    }

    await batch.commit()
    return { themes: topThemes }
  })

// ---------------------------------------------------------------------------
// getVettedOrgForTheme
// ---------------------------------------------------------------------------

/**
 * Called by NoteGiveBridge (iOS) to retrieve a verified vetted org whose
 * `themes` array contains the requested theme.
 *
 * Orgs must have `verified == true` (ECFA or CharityNavigator verified)
 * before they appear here. Org seeding is a human step — see
 * Docs/FUNCTION_INVENTORY.md.
 *
 * Request: { theme: string }
 * Response: { name: string | null, id: string | null, ein: string | null }
 */
export const getVettedOrgForTheme = functions
  .region('us-east1')
  .runWith({ enforceAppCheck: true })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Sign in required')
    }

    const { theme } = data as { theme: string }

    if (!theme || typeof theme !== 'string') {
      return { name: null, id: null, ein: null }
    }

    const db = admin.firestore()

    // Only surface verified orgs (ECFA / CharityNavigator).
    const snap = await db
      .collection('vettedOrgs')
      .where('themes', 'array-contains', theme)
      .where('verified', '==', true)
      .limit(1)
      .get()

    if (snap.empty) {
      return { name: null, id: null, ein: null }
    }

    const org = snap.docs[0]
    const orgData = org.data()

    return {
      name: orgData.name ?? null,
      id: org.id,
      ein: orgData.ein ?? null
    }
  })

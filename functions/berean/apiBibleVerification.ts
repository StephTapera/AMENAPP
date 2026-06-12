/**
 * berean/apiBibleVerification.ts — Scripture Verification Callable
 * Berean Trust Architecture · G-1
 *
 * Verifies that AI-produced scripture text matches canonical Bible text.
 * Resolution order: Firestore cache → API.Bible REST API.
 *
 * Security invariants:
 *   - BIBLE_API_KEY is NEVER returned in any response, log, or error message.
 *   - Any error → "unresolvable" (fail-secure; never "verified" on error).
 *   - API.Bible timeout = 5 seconds.
 *   - Per-uid rate limit: 30 calls/min in collection "rateLimits".
 *   - App Check enforced; auth required.
 */

import * as functions from 'firebase-functions/v2/https'
import { logger } from 'firebase-functions'
import * as admin from 'firebase-admin'

// ── Types ─────────────────────────────────────────────────────────────────────

export interface VerifyScriptureRequest {
  references: Array<{
    ref: string           // e.g. "John 3:16"
    claimedText: string   // text AI produced
    translation: 'BSB' | 'WEB' | 'KJV'
  }>
}

export type ScriptureVerdict = 'verified' | 'mismatch' | 'unresolvable'

export interface VerifyScriptureResponse {
  results: Array<{
    ref: string
    verdict: ScriptureVerdict
    canonicalText?: string   // present on "mismatch" or "verified"
    similarity?: number      // 0–1 Jaccard score
  }>
}

// ── Constants ─────────────────────────────────────────────────────────────────

const MAX_REFS_PER_CALL = 20
const JACCARD_VERIFIED_THRESHOLD = 0.85
const API_BIBLE_TIMEOUT_MS = 5000
const RATE_LIMIT_WINDOW_MS = 60_000
const RATE_LIMIT_MAX_CALLS = 30

// API.Bible bible IDs for supported translations.
// These are server-side constants — not exposed to the client.
const TRANSLATION_BIBLE_IDS: Record<'BSB' | 'WEB' | 'KJV', string> = {
  KJV: 'de4e12af7f28f599-01',
  BSB: '', // populated from Secret Manager at runtime via env; see resolveApiBibleId()
  WEB: '', // populated from Secret Manager at runtime via env; see resolveApiBibleId()
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Normalize text for comparison:
 * - strip verse numbers (leading digits + optional colon at start)
 * - remove pilcrows, red-letter markers, bracket content
 * - casefold
 * - collapse all whitespace
 * - strip punctuation
 */
function normalizeText(raw: string): string {
  return raw
    .replace(/^\s*\d+[:.]?\s*/u, '')            // leading verse number
    .replace(/¶/gu, '')                           // pilcrow
    .replace(/\[.*?\]/gu, '')                     // bracketed notes
    .replace(/<[^>]+>/gu, '')                     // any HTML/red-letter tags
    .toLowerCase()
    .replace(/[^\w\s]/gu, '')                     // strip punctuation
    .replace(/\s+/gu, ' ')
    .trim()
}

/**
 * Token-level Jaccard similarity between two normalized strings.
 * Returns a value in [0, 1].
 */
function jaccardSimilarity(a: string, b: string): number {
  const setA = new Set(a.split(' ').filter(Boolean))
  const setB = new Set(b.split(' ').filter(Boolean))
  if (setA.size === 0 && setB.size === 0) return 1
  if (setA.size === 0 || setB.size === 0) return 0
  let intersection = 0
  for (const token of setA) {
    if (setB.has(token)) intersection++
  }
  const union = setA.size + setB.size - intersection
  return intersection / union
}

/**
 * Resolve the API.Bible bibleId for a translation.
 * BSB and WEB IDs come from environment variables set by Secret Manager
 * (APIBIBLE_ID_BSB, APIBIBLE_ID_WEB), matching the iOS bundle config key pattern.
 */
function resolveApiBibleId(translation: 'BSB' | 'WEB' | 'KJV'): string {
  if (translation === 'KJV') return TRANSLATION_BIBLE_IDS.KJV
  if (translation === 'BSB') return process.env['APIBIBLE_ID_BSB'] ?? ''
  if (translation === 'WEB') return process.env['APIBIBLE_ID_WEB'] ?? ''
  return ''
}

/**
 * Parse a human-readable scripture reference into API.Bible passage ID.
 * Returns null if parsing fails.
 * Example: "John 3:16" → "JHN.3.16"
 */
function parseRefToPassageId(ref: string): string | null {
  const BOOK_MAP: Record<string, string> = {
    'genesis': 'GEN', 'exodus': 'EXO', 'leviticus': 'LEV', 'numbers': 'NUM',
    'deuteronomy': 'DEU', 'joshua': 'JOS', 'judges': 'JDG', 'ruth': 'RUT',
    '1 samuel': '1SA', '2 samuel': '2SA', '1 kings': '1KI', '2 kings': '2KI',
    '1 chronicles': '1CH', '2 chronicles': '2CH', 'ezra': 'EZR', 'nehemiah': 'NEH',
    'esther': 'EST', 'job': 'JOB', 'psalms': 'PSA', 'psalm': 'PSA',
    'proverbs': 'PRO', 'ecclesiastes': 'ECC', 'song of solomon': 'SNG',
    'isaiah': 'ISA', 'jeremiah': 'JER', 'lamentations': 'LAM', 'ezekiel': 'EZK',
    'daniel': 'DAN', 'hosea': 'HOS', 'joel': 'JOL', 'amos': 'AMO', 'obadiah': 'OBA',
    'jonah': 'JON', 'micah': 'MIC', 'nahum': 'NAM', 'habakkuk': 'HAB',
    'zephaniah': 'ZEP', 'haggai': 'HAG', 'zechariah': 'ZEC', 'malachi': 'MAL',
    'matthew': 'MAT', 'mark': 'MRK', 'luke': 'LUK', 'john': 'JHN',
    'acts': 'ACT', 'romans': 'ROM', '1 corinthians': '1CO', '2 corinthians': '2CO',
    'galatians': 'GAL', 'ephesians': 'EPH', 'philippians': 'PHP', 'colossians': 'COL',
    '1 thessalonians': '1TH', '2 thessalonians': '2TH', '1 timothy': '1TI',
    '2 timothy': '2TI', 'titus': 'TIT', 'philemon': 'PHM', 'hebrews': 'HEB',
    'james': 'JAS', '1 peter': '1PE', '2 peter': '2PE', '1 john': '1JN',
    '2 john': '2JN', '3 john': '3JN', 'jude': 'JUD', 'revelation': 'REV',
  }

  const trimmed = ref.trim()
  // Match: optional leading number + book name + chapter:verse
  const match = trimmed.match(/^(\d\s)?([a-zA-Z\s]+)\s+(\d+):(\d+)$/u)
  if (!match) return null

  const prefix = match[1] ? match[1].trim() : ''
  const bookRaw = (prefix ? `${prefix} ${match[2].trim()}` : match[2].trim()).toLowerCase()
  const chapter = match[3]
  const verse = match[4]

  const bookCode = BOOK_MAP[bookRaw]
  if (!bookCode) return null

  return `${bookCode}.${chapter}.${verse}`
}

/**
 * Fetch canonical text from API.Bible REST API.
 * Times out after API_BIBLE_TIMEOUT_MS.
 * Returns null on any error (caller maps to "unresolvable").
 * NEVER logs the API key.
 */
async function fetchFromApiBible(
  passageId: string,
  bibleId: string,
  apiKey: string
): Promise<string | null> {
  const url = `https://api.scripture.api.bible/v1/bibles/${bibleId}/verses/${passageId}?content-type=text&include-notes=false&include-titles=false&include-chapter-numbers=false&include-verse-numbers=false&include-verse-spans=false`

  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), API_BIBLE_TIMEOUT_MS)

  try {
    const response = await fetch(url, {
      headers: { 'api-key': apiKey },
      signal: controller.signal,
    })

    if (!response.ok) {
      logger.warn('[verifyScriptureText] API.Bible non-OK status', {
        status: response.status,
        passageId,
      })
      return null
    }

    const json = (await response.json()) as { data?: { content?: string } }
    const raw = json?.data?.content ?? null
    return raw ? normalizeText(raw) : null
  } catch (err: unknown) {
    const isAbort =
      err instanceof Error &&
      (err.name === 'AbortError' || err.message.includes('abort'))
    logger.warn('[verifyScriptureText] API.Bible fetch error', {
      passageId,
      isTimeout: isAbort,
      // explicitly NOT logging apiKey, url (which doesn't contain key), or bibleId
    })
    return null
  } finally {
    clearTimeout(timer)
  }
}

/**
 * Enforce per-uid rate limit using Firestore counter.
 * Collection: "rateLimits", doc: "{uid}_verifyScripture"
 * Fields: count (number), windowStart (Timestamp)
 * Window: 60 seconds, limit: 30 calls.
 * Throws HttpsError('resource-exhausted') if limit exceeded.
 */
async function enforceRateLimit(
  uid: string,
  db: admin.firestore.Firestore
): Promise<void> {
  const rateLimitRef = db.doc(`rateLimits/${uid}_verifyScripture`)

  await db.runTransaction(async (txn) => {
    const snap = await txn.get(rateLimitRef)
    const now = Date.now()

    if (!snap.exists) {
      txn.set(rateLimitRef, {
        count: 1,
        windowStart: admin.firestore.Timestamp.fromMillis(now),
      })
      return
    }

    const data = snap.data() as { count: number; windowStart: admin.firestore.Timestamp }
    const windowStartMs = data.windowStart.toMillis()

    if (now - windowStartMs > RATE_LIMIT_WINDOW_MS) {
      // New window
      txn.set(rateLimitRef, {
        count: 1,
        windowStart: admin.firestore.Timestamp.fromMillis(now),
      })
      return
    }

    if (data.count >= RATE_LIMIT_MAX_CALLS) {
      throw new functions.HttpsError(
        'resource-exhausted',
        'Rate limit exceeded. Maximum 30 verifyScriptureText calls per minute.'
      )
    }

    txn.update(rateLimitRef, {
      count: admin.firestore.FieldValue.increment(1),
    })
  })
}

// ── Single-ref resolution ─────────────────────────────────────────────────────

async function resolveOneRef(
  ref: string,
  claimedText: string,
  translation: 'BSB' | 'WEB' | 'KJV',
  db: admin.firestore.Firestore,
  apiKey: string
): Promise<VerifyScriptureResponse['results'][number]> {
  let canonicalNormalized: string | null = null

  // 1. Try Firestore cache first
  const cacheDocId = `${translation}:${ref}`
  try {
    const cacheSnap = await db.doc(`bibleVerses/${cacheDocId}`).get()
    if (cacheSnap.exists) {
      const text = cacheSnap.data()?.text as string | undefined
      if (text) {
        canonicalNormalized = normalizeText(text)
      }
    }

    // Fallback: KJV uses the seeded collection with {BookName}_{chapter}_{verse} keys.
    if (!canonicalNormalized && translation === 'KJV') {
      // Try to build the seeded collection doc ID from the ref.
      const m = ref.trim().match(/^(\d\s)?([a-zA-Z\s]+)\s+(\d+):(\d+)$/u)
      if (m) {
        const prefix = m[1] ? m[1].trim() : ''
        const bookName = prefix ? `${prefix} ${m[2].trim()}` : m[2].trim()
        const chapter = m[3]
        const verse = m[4]
        const seededDocId = `${bookName.replace(/\s+/g, '_')}_${chapter}_${verse}`
        const seededSnap = await db.doc(`bibleVerses/${seededDocId}`).get()
        if (seededSnap.exists) {
          const text = seededSnap.data()?.text as string | undefined
          if (text) {
            canonicalNormalized = normalizeText(text)
          }
        }
      }
    }
  } catch (cacheErr) {
    logger.warn('[verifyScriptureText] Firestore cache read error', { ref, translation })
    // Continue to API fallback
  }

  // 2. On cache miss: fetch from API.Bible
  if (!canonicalNormalized) {
    const passageId = parseRefToPassageId(ref)
    if (!passageId) {
      // Structural parse failure → unresolvable
      return { ref, verdict: 'unresolvable' }
    }

    const bibleId = resolveApiBibleId(translation)
    if (!bibleId) {
      logger.warn('[verifyScriptureText] No bibleId for translation', { translation })
      return { ref, verdict: 'unresolvable' }
    }

    const fetched = await fetchFromApiBible(passageId, bibleId, apiKey)
    if (!fetched) {
      return { ref, verdict: 'unresolvable' }
    }

    canonicalNormalized = fetched

    // Write to cache (fire-and-forget; don't block response or fail on write error)
    db.doc(`bibleVerses/${cacheDocId}`)
      .set({
        ref,
        translation,
        text: fetched,
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      })
      .catch((writeErr) => {
        logger.warn('[verifyScriptureText] Cache write error', { ref })
      })
  }

  // 3. Compare claimed vs canonical
  const claimedNormalized = normalizeText(claimedText)
  const similarity = jaccardSimilarity(claimedNormalized, canonicalNormalized)

  if (similarity >= JACCARD_VERIFIED_THRESHOLD) {
    return { ref, verdict: 'verified', canonicalText: canonicalNormalized, similarity }
  } else {
    return { ref, verdict: 'mismatch', canonicalText: canonicalNormalized, similarity }
  }
}

// ── Callable export ───────────────────────────────────────────────────────────

export const verifyScriptureText = functions.onCall(
  {
    enforceAppCheck: true,
    region: 'us-central1',
    secrets: ['BIBLE_API_KEY'],
  },
  async (request): Promise<VerifyScriptureResponse> => {
    // Auth guard
    if (!request.auth) {
      throw new functions.HttpsError('unauthenticated', 'Authentication required.')
    }

    const uid = request.auth.uid
    const db = admin.firestore()

    // Input validation
    const data = request.data as VerifyScriptureRequest
    if (!data?.references || !Array.isArray(data.references)) {
      throw new functions.HttpsError('invalid-argument', '"references" must be a non-empty array.')
    }
    if (data.references.length === 0) {
      throw new functions.HttpsError('invalid-argument', '"references" array must not be empty.')
    }
    if (data.references.length > MAX_REFS_PER_CALL) {
      throw new functions.HttpsError(
        'invalid-argument',
        `Maximum ${MAX_REFS_PER_CALL} references per call. Received ${data.references.length}.`
      )
    }
    for (const item of data.references) {
      if (!item.ref || typeof item.ref !== 'string' || item.ref.trim().length === 0) {
        throw new functions.HttpsError('invalid-argument', 'Each reference must have a non-empty "ref" string.')
      }
      if (!item.claimedText || typeof item.claimedText !== 'string') {
        throw new functions.HttpsError('invalid-argument', 'Each reference must have a "claimedText" string.')
      }
      if (item.translation !== 'BSB' && item.translation !== 'WEB' && item.translation !== 'KJV') {
        throw new functions.HttpsError('invalid-argument', '"translation" must be one of: BSB, WEB, KJV.')
      }
    }

    // Rate limit
    await enforceRateLimit(uid, db)

    // Read API key once — it is available in the function environment as a secret
    const apiKey = process.env['BIBLE_API_KEY'] ?? ''

    // Resolve all refs (in parallel, fail-secure per ref)
    const results = await Promise.all(
      data.references.map(async (item) => {
        try {
          return await resolveOneRef(
            item.ref,
            item.claimedText,
            item.translation,
            db,
            apiKey
          )
        } catch (err) {
          // Catch-all: any unexpected error → unresolvable, no key leak
          logger.error('[verifyScriptureText] Unexpected error resolving ref', {
            ref: item.ref,
            // deliberately not logging apiKey or full error
          })
          return { ref: item.ref, verdict: 'unresolvable' as ScriptureVerdict }
        }
      })
    )

    return { results }
  }
)

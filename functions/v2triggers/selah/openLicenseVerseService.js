/**
 * openLicenseVerseService.js — Open-licensed verse text service for Agent C (discernment engine).
 *
 * Provides ONLY BSB / WEB / KJV text to the AI citation path.
 * Licensed translations (ESV, NIV, NLT, NASB, CSB, NKJV) are HARD-BLOCKED by
 * assertOpenTranslationJS before any network call is attempted.
 *
 * Exported functions:
 *   getOpenLicenseVersesForContext(inputText, preferredTranslation?)
 *     — Agent C's primary entry point: extracts references from text, fetches them in
 *       parallel, and supplements with topic-driven passages. Fail graceful (returns []).
 *
 *   getVersesByReference(references, translation)
 *     — Targeted lookup for Agent C when it already knows the references it wants.
 *       Fail graceful (returns []). assertOpenTranslationJS runs before any work.
 *
 *   assertOpenTranslationJS(translation)
 *     — Re-exported for callers that need the boundary check standalone.
 *
 * HARD CONSTRAINTS (from selah.contracts.ts):
 *   1. NEVER fetch ESV/NIV/NLT/NASB/CSB/NKJV — assertOpenTranslationJS throws first.
 *   2. Fail gracefully — network errors return [] not thrown errors (Agent C handles empty corpus).
 *   3. Cache — CompositeOpenLicenseProvider caches per invocation; no duplicate fetches.
 *   4. No fabrication — if a reference isn't found, return empty Citation[], never a generated verse.
 *   5. Translation label — every Citation carries the correct OpenTranslation value.
 *
 * DEFAULT_DISCERNMENT_TRANSLATION = 'BSB' (from selah.contracts.ts Section 4)
 */

"use strict";

const {
  CompositeOpenLicenseProvider,
  assertOpenTranslationJS,
} = require("./bibleProviderAdapter");

// ---------------------------------------------------------------------------
// CONSTANTS
// ---------------------------------------------------------------------------

/** Mirrors DEFAULT_DISCERNMENT_TRANSLATION from selah.contracts.ts */
const DEFAULT_DISCERNMENT_TRANSLATION = "BSB";

const FETCH_TIMEOUT_MS = 5000;

// ---------------------------------------------------------------------------
// REFERENCE EXTRACTION
// ---------------------------------------------------------------------------

/**
 * SCRIPTURE_REFERENCE_REGEX — matches common scripture reference patterns:
 *   "John 3:16"
 *   "1 Corinthians 13:4-7"
 *   "Psalm 23"
 *   "Romans 8:28"
 *   "3 John 1:4"
 *   "Song of Solomon 2:4"
 *
 * Group 1: book name (with optional leading digit, e.g. "1 John", "Song of Solomon")
 * Group 2: chapter
 * Group 3: optional start verse
 * Group 4: optional end verse
 */
const SCRIPTURE_REFERENCE_REGEX =
  /\b((?:[123]\s)?(?:Song\sof\sSolomon|Song\sof\sSongs|[A-Z][a-z]+(?:\s[A-Z][a-z]+)?))\s+(\d+)(?::(\d+)(?:-(\d+))?)?\b/g;

/**
 * extractScriptureReferences — parse all scripture reference patterns from
 * free text. Returns deduplicated array of canonical reference strings.
 *
 * @param {string} text
 * @returns {string[]}
 */
function extractScriptureReferences(text) {
  if (!text || typeof text !== "string") return [];

  const matches = [];
  let match;
  const regex = new RegExp(SCRIPTURE_REFERENCE_REGEX.source, "g");

  while ((match = regex.exec(text)) !== null) {
    const book = match[1].trim();
    const chapter = match[2];
    const startVerse = match[3];
    const endVerse = match[4];

    let ref = `${book} ${chapter}`;
    if (startVerse) {
      ref += `:${startVerse}`;
      if (endVerse) ref += `-${endVerse}`;
    }

    matches.push(ref);
  }

  // Deduplicate while preserving order
  return [...new Set(matches)];
}

// ---------------------------------------------------------------------------
// TOPIC-DRIVEN CONTEXTUAL PASSAGES
// ---------------------------------------------------------------------------

/**
 * TOPIC_PASSAGES — hardcoded (NOT AI-generated) topic → reference mappings.
 * These are well-known key passages for common theological topics.
 * Agent C may call this service and receive supplementary context even when
 * the input text contains no explicit scripture references.
 *
 * Each entry: [keyword, reference]
 * All references will be fetched in the caller's preferred open translation.
 */
const TOPIC_PASSAGES = [
  // Grace
  ["grace",       "Ephesians 2:8"],
  ["grace",       "Romans 5:8"],
  // Faith
  ["faith",       "Hebrews 11:1"],
  ["faith",       "James 2:17"],
  // Love
  ["love",        "1 Corinthians 13:4"],
  ["love",        "John 3:16"],
  // Sin
  ["sin",         "Romans 3:23"],
  ["sin",         "1 John 1:9"],
  // Salvation
  ["salvation",   "Romans 10:9"],
  ["salvation",   "Acts 4:12"],
  // Hope
  ["hope",        "Romans 8:28"],
  ["hope",        "Jeremiah 29:11"],
  // Prayer
  ["prayer",      "Philippians 4:6"],
  ["prayer",      "Matthew 6:9"],
  // Forgiveness
  ["forgiveness", "Matthew 6:14"],
  ["forgiveness", "Ephesians 4:32"],
  // Worship
  ["worship",     "John 4:24"],
  ["worship",     "Psalm 95:1"],
  // Wisdom
  ["wisdom",      "James 1:5"],
  ["wisdom",      "Proverbs 3:5"],
  // Peace
  ["peace",       "John 14:27"],
  ["peace",       "Philippians 4:7"],
  // Suffering
  ["suffering",   "Romans 5:3"],
  ["suffering",   "2 Corinthians 12:9"],
  // Repentance
  ["repentance",  "Acts 3:19"],
  ["repentance",  "2 Chronicles 7:14"],
  // Righteousness
  ["righteousness", "Matthew 5:6"],
  ["righteousness", "Romans 3:22"],
  // Creation
  ["creation",    "Genesis 1:1"],
  ["creation",    "Colossians 1:16"],
  // Redemption
  ["redemption",  "Galatians 3:13"],
  ["redemption",  "1 Peter 1:18"],
  // Holy Spirit
  ["holy spirit", "Acts 2:38"],
  ["spirit",      "John 14:26"],
  // Sanctification
  ["sanctification", "1 Thessalonians 4:3"],
  ["sanctification", "Hebrews 12:14"],
  // Judgment
  ["judgment",    "Romans 14:10"],
  ["judgment",    "Hebrews 9:27"],
  // Resurrection
  ["resurrection", "1 Corinthians 15:22"],
  ["resurrection", "John 11:25"],
  // Church
  ["church",      "Matthew 16:18"],
  ["church",      "Ephesians 4:12"],
  // Scripture / Word
  ["scripture",   "2 Timothy 3:16"],
  ["word",        "Psalm 119:105"],
  // Obedience
  ["obedience",   "John 14:15"],
  ["obedience",   "Romans 5:19"],
  // Doubt
  ["doubt",       "James 1:6"],
  ["doubt",       "Matthew 14:31"],
  // Healing
  ["healing",     "James 5:16"],
  ["healing",     "Psalm 103:3"],
  // Fear
  ["fear",        "Psalm 23:4"],
  ["fear",        "Isaiah 41:10"],
  // Joy
  ["joy",         "Psalm 16:11"],
  ["joy",         "Nehemiah 8:10"],
  // Truth
  ["truth",       "John 8:32"],
  ["truth",       "John 14:6"],
  // Justice
  ["justice",     "Micah 6:8"],
  ["justice",     "Isaiah 1:17"],
  // Mercy
  ["mercy",       "Lamentations 3:22"],
  ["mercy",       "Matthew 5:7"],
];

/**
 * getTopicReferences — look for theological keywords in the input text and
 * return up to 2 hardcoded key passages per matched keyword (max 6 total
 * to keep the citation corpus focused).
 *
 * @param {string} text
 * @returns {string[]} deduplicated reference strings
 */
function getTopicReferences(text) {
  if (!text || typeof text !== "string") return [];

  const lower = text.toLowerCase();
  const found = new Set();

  for (const [keyword, reference] of TOPIC_PASSAGES) {
    if (found.size >= 6) break;
    if (lower.includes(keyword)) {
      found.add(reference);
    }
  }

  return [...found];
}

// ---------------------------------------------------------------------------
// DEDUPLICATION
// ---------------------------------------------------------------------------

/**
 * deduplicateCitations — remove duplicate Citation objects by reference+translation.
 * Preserves first occurrence.
 *
 * @param {Array<{reference: string, translation: string, text: string}>} citations
 * @returns {Array<{reference: string, translation: string, text: string}>}
 */
function deduplicateCitations(citations) {
  const seen = new Set();
  return citations.filter((c) => {
    const key = `${c.reference}:${c.translation}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

// ---------------------------------------------------------------------------
// CORE: fetch a single reference (fail graceful)
// ---------------------------------------------------------------------------

/**
 * fetchOneReference — fetch a single reference from the composite provider.
 * Returns Citation[] on success, [] on any error (fail graceful).
 *
 * @param {CompositeOpenLicenseProvider} provider
 * @param {string} reference
 * @param {string} translation
 * @returns {Promise<Array<{reference: string, translation: string, text: string}>>}
 */
async function fetchOneReference(provider, reference, translation) {
  try {
    const results = await provider.getVerses(reference, translation);
    if (!Array.isArray(results)) {
      console.warn(`[openLicenseVerseService] Non-array result for "${reference}" (${translation})`);
      return [];
    }
    // Filter out empty text entries — no fabrication
    return results.filter((c) => c.text && c.text.trim().length > 0);
  } catch (err) {
    // Fail gracefully: log the miss, return empty
    console.warn(
      `[openLicenseVerseService] Fetch failed for "${reference}" (${translation}): ${err.message}`
    );
    return [];
  }
}

// ---------------------------------------------------------------------------
// EXPORTED FUNCTION 1: getOpenLicenseVersesForContext
// ---------------------------------------------------------------------------

/**
 * getOpenLicenseVersesForContext — Agent C's primary entry point.
 *
 * 1. Extracts explicit scripture references from inputText (regex-based).
 * 2. Looks up topic-driven passages for theological keywords in inputText.
 * 3. Fetches all detected references in parallel (Promise.all, 5s timeout each).
 * 4. Returns deduplicated Citation[] keyed by reference + translation.
 *
 * Fail graceful: any individual fetch failure returns [] for that reference.
 * The entire function never throws — it returns [] if everything fails.
 *
 * @param {string} inputText — the post-moderation text passed to Agent C
 * @param {string} [preferredTranslation='BSB'] — must be 'BSB', 'WEB', or 'KJV'
 * @returns {Promise<Array<{reference: string, translation: string, text: string}>>}
 */
async function getOpenLicenseVersesForContext(inputText, preferredTranslation) {
  const translation = preferredTranslation || DEFAULT_DISCERNMENT_TRANSLATION;

  // Hard constraint at entry point — reject licensed translations immediately
  try {
    assertOpenTranslationJS(translation);
  } catch (err) {
    console.error(`[getOpenLicenseVersesForContext] ${err.message}`);
    return [];
  }

  if (!inputText || typeof inputText !== "string" || inputText.trim().length === 0) {
    console.warn("[getOpenLicenseVersesForContext] Empty or invalid inputText — returning []");
    return [];
  }

  // One provider instance per call — its Map cache deduplicates within this invocation
  const provider = new CompositeOpenLicenseProvider();

  // Step 1: explicit references
  const explicitRefs = extractScriptureReferences(inputText);
  console.log(
    `[getOpenLicenseVersesForContext] Explicit references extracted (${explicitRefs.length}):`,
    explicitRefs.length > 0 ? explicitRefs : "(none)"
  );

  // Step 2: topic-driven contextual references
  const topicRefs = getTopicReferences(inputText);
  console.log(
    `[getOpenLicenseVersesForContext] Topic references (${topicRefs.length}):`,
    topicRefs.length > 0 ? topicRefs : "(none)"
  );

  // Merge, deduplicate reference strings, then fetch
  const allRefs = [...new Set([...explicitRefs, ...topicRefs])];

  if (allRefs.length === 0) {
    console.log("[getOpenLicenseVersesForContext] No references to fetch — returning []");
    return [];
  }

  // Step 3: parallel fetch with per-reference 5s timeout (enforced inside fetchWithTimeout)
  const fetchPromises = allRefs.map((ref) =>
    fetchOneReference(provider, ref, translation)
  );

  let results;
  try {
    results = await Promise.all(fetchPromises);
  } catch (err) {
    // Promise.all with individual fail-graceful wrappers should never throw,
    // but guard defensively
    console.error(`[getOpenLicenseVersesForContext] Unexpected Promise.all failure: ${err.message}`);
    return [];
  }

  // Step 4: flatten + deduplicate
  const flat = results.flat();
  const deduplicated = deduplicateCitations(flat);

  console.log(
    `[getOpenLicenseVersesForContext] Returning ${deduplicated.length} citations ` +
    `(${translation}) for ${allRefs.length} reference(s)`
  );

  return deduplicated;
}

// ---------------------------------------------------------------------------
// EXPORTED FUNCTION 2: getVersesByReference
// ---------------------------------------------------------------------------

/**
 * getVersesByReference — targeted lookup for Agent C when it already knows
 * the exact references it wants. Fetches in parallel, fails gracefully.
 *
 * @param {string[]} references — array of reference strings (e.g. ["John 3:16", "Romans 8:28"])
 * @param {string} translation — must be 'BSB', 'WEB', or 'KJV'
 * @returns {Promise<Array<{reference: string, translation: string, text: string}>>}
 */
async function getVersesByReference(references, translation) {
  // Hard constraint at entry — throws for licensed translations
  try {
    assertOpenTranslationJS(translation);
  } catch (err) {
    console.error(`[getVersesByReference] ${err.message}`);
    return [];
  }

  if (!Array.isArray(references) || references.length === 0) {
    console.warn("[getVersesByReference] Empty references array — returning []");
    return [];
  }

  const provider = new CompositeOpenLicenseProvider();

  const fetchPromises = references.map((ref) =>
    fetchOneReference(provider, ref, translation)
  );

  let results;
  try {
    results = await Promise.all(fetchPromises);
  } catch (err) {
    console.error(`[getVersesByReference] Unexpected Promise.all failure: ${err.message}`);
    return [];
  }

  const flat = results.flat();
  const deduplicated = deduplicateCitations(flat);

  console.log(
    `[getVersesByReference] Returning ${deduplicated.length} citations ` +
    `(${translation}) for ${references.length} reference(s)`
  );

  return deduplicated;
}

// ---------------------------------------------------------------------------
// MODULE EXPORTS
// ---------------------------------------------------------------------------

module.exports = {
  getOpenLicenseVersesForContext,
  getVersesByReference,
  assertOpenTranslationJS,
  // Exported for testing
  extractScriptureReferences,
  getTopicReferences,
  deduplicateCitations,
  DEFAULT_DISCERNMENT_TRANSLATION,
};

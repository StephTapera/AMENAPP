/**
 * bibleProviderAdapter.js — Provider pattern for open-license Bible translations (Node.js).
 *
 * Mirrors the Swift SelahBibleTranslationProvider protocol in Node.js.
 * Provides three providers:
 *   - BibleApiProvider      — fetches KJV and WEB from bible-api.com (free, no key)
 *   - BollsLifeProvider     — fetches BSB from bolls.life (free, no key)
 *   - CompositeOpenLicenseProvider — routes by translation, in-memory cache per invocation
 *
 * HARD LEGAL CONSTRAINT:
 *   Only BSB, WEB, and KJV may flow through these providers.
 *   assertOpenTranslationJS MUST be called at every boundary.
 *   Licensed translations (ESV, NIV, NLT, NASB, CSB, NKJV) throw before any network call.
 *
 * Network: uses native fetch (Node 22). All external calls are wrapped in a 5-second timeout.
 */

"use strict";

// ---------------------------------------------------------------------------
// CONSTANTS
// ---------------------------------------------------------------------------

const OPEN_TRANSLATIONS = ["BSB", "WEB", "KJV"];
const FETCH_TIMEOUT_MS = 5000;

// bible-api.com translation parameter names
const BIBLE_API_TRANSLATION_MAP = {
  KJV: "kjv",
  WEB: "web",
};

// Bolls.life book number map — Old Testament (1–39) + New Testament (40–66)
// Full 66-book canonical Protestant Bible mapping.
const BOLLS_BOOK_NUMBER_MAP = {
  // Old Testament
  Genesis: 1,     Exodus: 2,       Leviticus: 3,    Numbers: 4,
  Deuteronomy: 5, Joshua: 6,       Judges: 7,       Ruth: 8,
  "1 Samuel": 9,  "2 Samuel": 10,  "1 Kings": 11,   "2 Kings": 12,
  "1 Chronicles": 13, "2 Chronicles": 14, Ezra: 15, Nehemiah: 16,
  Esther: 17,     Job: 18,         Psalms: 19,       Proverbs: 20,
  Ecclesiastes: 21, "Song of Solomon": 22, Isaiah: 23, Jeremiah: 24,
  Lamentations: 25, Ezekiel: 26,   Daniel: 27,       Hosea: 28,
  Joel: 29,       Amos: 30,        Obadiah: 31,      Jonah: 32,
  Micah: 33,      Nahum: 34,       Habakkuk: 35,     Zephaniah: 36,
  Haggai: 37,     Zechariah: 38,   Malachi: 39,
  // New Testament
  Matthew: 40,    Mark: 41,        Luke: 42,         John: 43,
  Acts: 44,       Romans: 45,      "1 Corinthians": 46, "2 Corinthians": 47,
  Galatians: 48,  Ephesians: 49,   Philippians: 50,  Colossians: 51,
  "1 Thessalonians": 52, "2 Thessalonians": 53,
  "1 Timothy": 54, "2 Timothy": 55, Titus: 56,       Philemon: 57,
  Hebrews: 58,    James: 59,       "1 Peter": 60,    "2 Peter": 61,
  "1 John": 62,   "2 John": 63,    "3 John": 64,     Jude: 65,
  Revelation: 66,
};

// Aliases for common shorthand book names → canonical for BOLLS_BOOK_NUMBER_MAP lookup
const BOOK_NAME_ALIASES = {
  Gen: "Genesis",         Ge: "Genesis",          Gn: "Genesis",
  Exo: "Exodus",          Ex: "Exodus",
  Lev: "Leviticus",       Lv: "Leviticus",
  Num: "Numbers",         Nu: "Numbers",          Nm: "Numbers",
  Deu: "Deuteronomy",     Dt: "Deuteronomy",      Deut: "Deuteronomy",
  Jos: "Joshua",          Josh: "Joshua",
  Jdg: "Judges",          Jud: "Judges",
  Rut: "Ruth",
  "1Sam": "1 Samuel",     "1 Sam": "1 Samuel",    "1Sa": "1 Samuel",
  "2Sam": "2 Samuel",     "2 Sam": "2 Samuel",    "2Sa": "2 Samuel",
  "1Ki": "1 Kings",       "1 Ki": "1 Kings",      "1Kgs": "1 Kings",    "1 Kings": "1 Kings",
  "2Ki": "2 Kings",       "2 Ki": "2 Kings",      "2Kgs": "2 Kings",    "2 Kings": "2 Kings",
  "1Ch": "1 Chronicles",  "1 Chr": "1 Chronicles","1Chron": "1 Chronicles",
  "2Ch": "2 Chronicles",  "2 Chr": "2 Chronicles","2Chron": "2 Chronicles",
  Ezr: "Ezra",
  Neh: "Nehemiah",
  Est: "Esther",          Esth: "Esther",
  Ps: "Psalms",           Psa: "Psalms",          Psalm: "Psalms",
  Pro: "Proverbs",        Prov: "Proverbs",       Prv: "Proverbs",
  Ecc: "Ecclesiastes",    Eccl: "Ecclesiastes",   Qoh: "Ecclesiastes",
  "Song": "Song of Solomon", Sol: "Song of Solomon", "SS": "Song of Solomon",
  "Sos": "Song of Solomon", "Song of Songs": "Song of Solomon",
  Isa: "Isaiah",          Is: "Isaiah",
  Jer: "Jeremiah",
  Lam: "Lamentations",
  Eze: "Ezekiel",         Ezk: "Ezekiel",
  Dan: "Daniel",          Dn: "Daniel",
  Hos: "Hosea",
  Joe: "Joel",            Jl: "Joel",
  Amo: "Amos",            Am: "Amos",
  Oba: "Obadiah",         Ob: "Obadiah",
  Jon: "Jonah",
  Mic: "Micah",
  Nah: "Nahum",           Na: "Nahum",
  Hab: "Habakkuk",
  Zep: "Zephaniah",       Zph: "Zephaniah",
  Hag: "Haggai",
  Zec: "Zechariah",       Zch: "Zechariah",
  Mal: "Malachi",
  Mat: "Matthew",         Mt: "Matthew",          Matt: "Matthew",
  Mar: "Mark",            Mk: "Mark",             Mrk: "Mark",
  Luk: "Luke",            Lk: "Luke",
  Joh: "John",            Jn: "John",
  Act: "Acts",
  Rom: "Romans",          Ro: "Romans",           Rm: "Romans",
  "1Co": "1 Corinthians", "1 Co": "1 Corinthians","1Cor": "1 Corinthians",
  "2Co": "2 Corinthians", "2 Co": "2 Corinthians","2Cor": "2 Corinthians",
  Gal: "Galatians",       Ga: "Galatians",
  Eph: "Ephesians",
  Phi: "Philippians",     Php: "Philippians",     Phil: "Philippians",
  Col: "Colossians",
  "1Th": "1 Thessalonians", "1 Th": "1 Thessalonians", "1Thess": "1 Thessalonians",
  "2Th": "2 Thessalonians", "2 Th": "2 Thessalonians", "2Thess": "2 Thessalonians",
  "1Ti": "1 Timothy",     "1 Ti": "1 Timothy",    "1Tim": "1 Timothy",
  "2Ti": "2 Timothy",     "2 Ti": "2 Timothy",    "2Tim": "2 Timothy",
  Tit: "Titus",
  Phm: "Philemon",        Phlm: "Philemon",
  Heb: "Hebrews",
  Jam: "James",           Jas: "James",           Jm: "James",
  "1Pe": "1 Peter",       "1 Pe": "1 Peter",      "1Pet": "1 Peter",
  "2Pe": "2 Peter",       "2 Pe": "2 Peter",      "2Pet": "2 Peter",
  "1Jo": "1 John",        "1 Jo": "1 John",       "1Jn": "1 John",
  "2Jo": "2 John",        "2 Jo": "2 John",       "2Jn": "2 John",
  "3Jo": "3 John",        "3 Jo": "3 John",       "3Jn": "3 John",
  Jud: "Jude",            Jde: "Jude",
  Rev: "Revelation",      Re: "Revelation",       Rv: "Revelation",
  Apo: "Revelation",
};

// ---------------------------------------------------------------------------
// HARD CONTRACT ENFORCEMENT
// ---------------------------------------------------------------------------

/**
 * assertOpenTranslationJS — JS runtime re-implementation of the TypeScript
 * assertOpenTranslation helper from selah.contracts.ts.
 *
 * Throws with the same error message contract as the TypeScript version.
 * Must be called at every boundary where a translation enters the AI citation path.
 *
 * @param {string} translation
 * @throws {Error} HARD CONTRACT VIOLATION if translation is not BSB, WEB, or KJV
 */
function assertOpenTranslationJS(translation) {
  if (!OPEN_TRANSLATIONS.includes(translation)) {
    throw new Error(
      `HARD CONTRACT VIOLATION: Translation "${translation}" is not open-licensed. ` +
      `Only BSB/WEB/KJV may appear in AI citation paths. Licensed versions (ESV, NIV, NLT, etc.) ` +
      `are restricted to the human reader path and must never be passed to the AI engine.`
    );
  }
}

// ---------------------------------------------------------------------------
// UTILITY: fetch with timeout
// ---------------------------------------------------------------------------

/**
 * fetchWithTimeout — wraps native fetch with a hard 5-second timeout.
 * Rejects with an Error if the timeout elapses before the response arrives.
 *
 * @param {string} url
 * @param {number} [timeoutMs=FETCH_TIMEOUT_MS]
 * @returns {Promise<Response>}
 */
function fetchWithTimeout(url, timeoutMs = FETCH_TIMEOUT_MS) {
  const timeoutPromise = new Promise((_, reject) =>
    setTimeout(() => reject(new Error(`Fetch timed out after ${timeoutMs}ms: ${url}`)), timeoutMs)
  );
  return Promise.race([fetch(url), timeoutPromise]);
}

// ---------------------------------------------------------------------------
// UTILITY: resolve a human-readable book name to its canonical form
// ---------------------------------------------------------------------------

/**
 * resolveBookName — looks up a book name (any common form) and returns the
 * canonical string used as the key in BOLLS_BOOK_NUMBER_MAP.
 * Returns null if the book cannot be resolved.
 *
 * @param {string} raw
 * @returns {string|null}
 */
function resolveBookName(raw) {
  if (!raw) return null;
  const trimmed = raw.trim();

  // 1. Direct hit in the canonical map
  if (BOLLS_BOOK_NUMBER_MAP[trimmed] !== undefined) return trimmed;

  // 2. Case-insensitive direct hit
  const lower = trimmed.toLowerCase();
  for (const canonical of Object.keys(BOLLS_BOOK_NUMBER_MAP)) {
    if (canonical.toLowerCase() === lower) return canonical;
  }

  // 3. Alias lookup (case-sensitive first, then case-insensitive)
  if (BOOK_NAME_ALIASES[trimmed]) return BOOK_NAME_ALIASES[trimmed];
  for (const [alias, canonical] of Object.entries(BOOK_NAME_ALIASES)) {
    if (alias.toLowerCase() === lower) return canonical;
  }

  return null;
}

// ---------------------------------------------------------------------------
// PROVIDER 1: BibleApiProvider (KJV + WEB via bible-api.com)
// ---------------------------------------------------------------------------

/**
 * BibleApiProvider — fetches KJV and WEB from the free bible-api.com service.
 *
 * Endpoint: https://bible-api.com/{reference}?translation={kjv|web}
 *
 * Response shape:
 *   {
 *     reference: "John 3:16",
 *     text: "For God so loved...",
 *     verses: [
 *       { book_id: "JHN", book_name: "John", chapter: 3, verse: 16, text: "For God so..." }
 *     ]
 *   }
 *
 * Returns: Citation[]
 * Throws: HARD CONTRACT VIOLATION if asked for a non-KJV/WEB translation.
 */
class BibleApiProvider {
  constructor() {
    this._supportedTranslations = ["KJV", "WEB"];
    this._baseUrl = "https://bible-api.com";
  }

  getSupportedTranslations() {
    return [...this._supportedTranslations];
  }

  /**
   * @param {string} reference — e.g. "John 3:16" or "Romans 8:28-30"
   * @param {string} translation — must be 'KJV' or 'WEB'
   * @returns {Promise<Array<{reference: string, translation: string, text: string}>>}
   */
  async getVerses(reference, translation) {
    assertOpenTranslationJS(translation);

    if (!this._supportedTranslations.includes(translation)) {
      throw new Error(
        `BibleApiProvider does not support translation "${translation}". ` +
        `Supported: ${this._supportedTranslations.join(", ")}.`
      );
    }

    const translationParam = BIBLE_API_TRANSLATION_MAP[translation];
    const encodedRef = encodeURIComponent(reference);
    const url = `${this._baseUrl}/${encodedRef}?translation=${translationParam}`;

    const response = await fetchWithTimeout(url);

    if (!response.ok) {
      throw new Error(
        `BibleApiProvider: HTTP ${response.status} fetching "${reference}" (${translation}) from bible-api.com`
      );
    }

    const json = await response.json();

    // Prefer the verses array for granular citation records; fall back to top-level text
    if (Array.isArray(json.verses) && json.verses.length > 0) {
      return json.verses.map((v) => ({
        reference: `${v.book_name} ${v.chapter}:${v.verse}`,
        translation: translation,
        text: (v.text || "").trim(),
      }));
    }

    // Fallback: single citation from top-level fields
    if (json.text && json.reference) {
      return [
        {
          reference: json.reference,
          translation: translation,
          text: json.text.trim(),
        },
      ];
    }

    return [];
  }
}

// ---------------------------------------------------------------------------
// PROVIDER 2: BollsLifeProvider (BSB via bolls.life)
// ---------------------------------------------------------------------------

/**
 * BollsLifeProvider — fetches BSB from the free bolls.life API (no key required).
 *
 * Endpoint: https://bolls.life/get-text/BSB/{bookNumber}/{chapter}/{verseFrom}/{verseTo}/
 *
 * Response shape: Array of verse objects:
 *   [
 *     { pk: 1, verse: 1, text: "In the beginning..." }
 *   ]
 *
 * Returns: Citation[]
 * Throws: HARD CONTRACT VIOLATION if asked for a non-BSB translation.
 */
class BollsLifeProvider {
  constructor() {
    this._supportedTranslations = ["BSB"];
    this._baseUrl = "https://bolls.life/get-text/BSB";
  }

  getSupportedTranslations() {
    return [...this._supportedTranslations];
  }

  /**
   * @param {string} reference — e.g. "John 3:16" or "Romans 8:28-30"
   * @param {string} translation — must be 'BSB'
   * @returns {Promise<Array<{reference: string, translation: string, text: string}>>}
   */
  async getVerses(reference, translation) {
    assertOpenTranslationJS(translation);

    if (!this._supportedTranslations.includes(translation)) {
      throw new Error(
        `BollsLifeProvider does not support translation "${translation}". Supported: BSB.`
      );
    }

    const parsed = this._parseReference(reference);
    if (!parsed) {
      throw new Error(`BollsLifeProvider: Cannot parse reference "${reference}"`);
    }

    const bookNumber = BOLLS_BOOK_NUMBER_MAP[parsed.bookCanonical];
    if (!bookNumber) {
      throw new Error(
        `BollsLifeProvider: Unknown book "${parsed.bookRaw}" (canonical: "${parsed.bookCanonical}") in reference "${reference}"`
      );
    }

    const { chapter, startVerse, endVerse } = parsed;
    const verseTo = endVerse || startVerse;
    const url = `${this._baseUrl}/${bookNumber}/${chapter}/${startVerse}/${verseTo}/`;

    const response = await fetchWithTimeout(url);

    if (!response.ok) {
      throw new Error(
        `BollsLifeProvider: HTTP ${response.status} fetching "${reference}" (BSB) from bolls.life`
      );
    }

    const json = await response.json();

    if (!Array.isArray(json) || json.length === 0) {
      return [];
    }

    return json.map((v) => {
      const verseNum = v.verse ?? startVerse;
      return {
        reference: `${parsed.bookCanonical} ${chapter}:${verseNum}`,
        translation: "BSB",
        text: (v.text || "").trim(),
      };
    });
  }

  /**
   * Parse a human-readable scripture reference into its components.
   * Handles: "John 3:16", "1 Corinthians 13:4-7", "Psalm 23"
   *
   * @param {string} reference
   * @returns {{ bookRaw: string, bookCanonical: string, chapter: number, startVerse: number, endVerse: number|null }|null}
   */
  _parseReference(reference) {
    // Pattern: optional leading number, book name, chapter, optional :verse(-endVerse)
    const pattern =
      /^((?:[123]\s)?[A-Za-z]+(?:\s[A-Za-z]+)*)\s+(\d+)(?::(\d+)(?:-(\d+))?)?$/;
    const match = reference.trim().match(pattern);
    if (!match) return null;

    const bookRaw = match[1].trim();
    const chapter = parseInt(match[2], 10);
    const startVerse = match[3] ? parseInt(match[3], 10) : 1;
    const endVerse = match[4] ? parseInt(match[4], 10) : null;

    const bookCanonical = resolveBookName(bookRaw);
    if (!bookCanonical) return null;

    return { bookRaw, bookCanonical, chapter, startVerse, endVerse };
  }
}

// ---------------------------------------------------------------------------
// PROVIDER 3: CompositeOpenLicenseProvider
// ---------------------------------------------------------------------------

/**
 * CompositeOpenLicenseProvider — routes by translation to the appropriate
 * sub-provider. Mirrors the Swift SelahCompositeBibleProvider pattern.
 *
 * Caches results in-memory keyed by "{reference}:{translation}" to avoid
 * duplicate network calls within a single Cloud Function invocation.
 *
 * HARD RULE: assertOpenTranslationJS is called before any fetch or cache lookup.
 * Licensed translations throw at this boundary — no network call is ever made.
 */
class CompositeOpenLicenseProvider {
  constructor() {
    this._bibleApiProvider = new BibleApiProvider();
    this._bollsLifeProvider = new BollsLifeProvider();
    /** @type {Map<string, Array<{reference: string, translation: string, text: string}>>} */
    this._cache = new Map();
  }

  getSupportedTranslations() {
    return [
      ...this._bibleApiProvider.getSupportedTranslations(),
      ...this._bollsLifeProvider.getSupportedTranslations(),
    ];
  }

  /**
   * Fetch verses for a reference in the given open-licensed translation.
   * Results are cached in-memory for the lifetime of this instance (one invocation).
   *
   * @param {string} reference
   * @param {string} translation — must be 'BSB', 'WEB', or 'KJV'
   * @returns {Promise<Array<{reference: string, translation: string, text: string}>>}
   */
  async getVerses(reference, translation) {
    // Hard constraint: throw before any network or cache access for licensed translations
    assertOpenTranslationJS(translation);

    const cacheKey = `${reference}:${translation}`;
    if (this._cache.has(cacheKey)) {
      console.log(
        `[CompositeOpenLicenseProvider] Cache hit: ${cacheKey}`
      );
      return this._cache.get(cacheKey);
    }

    let citations;

    if (translation === "BSB") {
      citations = await this._bollsLifeProvider.getVerses(reference, translation);
    } else {
      // KJV or WEB → bible-api.com
      citations = await this._bibleApiProvider.getVerses(reference, translation);
    }

    this._cache.set(cacheKey, citations);
    return citations;
  }
}

// ---------------------------------------------------------------------------
// MODULE EXPORTS
// ---------------------------------------------------------------------------

module.exports = {
  assertOpenTranslationJS,
  BibleApiProvider,
  BollsLifeProvider,
  CompositeOpenLicenseProvider,
  OPEN_TRANSLATIONS,
  BOLLS_BOOK_NUMBER_MAP,
  resolveBookName,
  fetchWithTimeout,
};

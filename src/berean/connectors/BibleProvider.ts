/**
 * BibleProvider.ts — Provider-swappable Bible adapter
 * Phase 2D: Berean Connectors
 *
 * Supported adapters: BSB (default), WEB, KJV
 * YouVersion: BLOCKED stub — written commercial agreement required.
 * Generic productivity connectors: REJECTED — faith-native only.
 *
 * SECURITY: No API keys on the client. All Bible lookups route through the
 * `bereanBibleLookup` Cloud Function callable (BIBLE_API_KEY stays server-side).
 */

import { getFunctions, httpsCallable } from 'firebase/functions';
import { getApp } from 'firebase/app';

// ─────────────────────────────────────────────────────────────────────────────
// CORE INTERFACES
// ─────────────────────────────────────────────────────────────────────────────

export interface BibleVerse {
  reference: string;   // e.g. "John 3:16"
  text: string;
  translation: string; // e.g. "BSB"
  book: string;
  chapter: number;
  verse: number;
}

export interface BibleProviderAdapter {
  id: string;
  name: string;
  translations: string[];
  getVerse(ref: string, translation?: string): Promise<BibleVerse>;
  getPassage(book: string, chapter: number, translation?: string): Promise<BibleVerse[]>;
}

export interface BibleProviderConfig {
  BIBLE_PROVIDER?: 'bsb' | 'web' | 'kjv';
}

// ─────────────────────────────────────────────────────────────────────────────
// CF CALLABLE HELPER
// All three adapters use this — BIBLE_API_KEY stays on the server in
// the bereanBibleLookup CF. Never exposed to the client bundle.
// ─────────────────────────────────────────────────────────────────────────────

interface BibleLookupRequest {
  reference: string;
  translation: string;
  type: 'verse' | 'passage';
}

interface BibleLookupResponse {
  reference: string;
  translation: string;
  text: string;
  bibleId: string;
}

async function callBibleLookup(req: BibleLookupRequest): Promise<BibleLookupResponse> {
  const functions = getFunctions(getApp(), 'us-central1');
  const fn = httpsCallable<BibleLookupRequest, BibleLookupResponse>(functions, 'bereanBibleLookup');
  const result = await fn(req);
  return result.data;
}

// ─────────────────────────────────────────────────────────────────────────────
// REFERENCE PARSING
// ─────────────────────────────────────────────────────────────────────────────

function parseVerseRef(ref: string): { book: string; chapter: number; verse: number } {
  const match = ref.match(/^(.+?)\s+(\d+):(\d+)$/);
  if (!match) {
    throw new Error(`Invalid verse reference: "${ref}". Expected "Book Chapter:Verse".`);
  }
  return {
    book: match[1].trim(),
    chapter: parseInt(match[2], 10),
    verse: parseInt(match[3], 10),
  };
}

const BOOK_ID_MAP: Record<string, string> = {
  Genesis: 'GEN', Exodus: 'EXO', Leviticus: 'LEV', Numbers: 'NUM',
  Deuteronomy: 'DEU', Joshua: 'JOS', Judges: 'JDG', Ruth: 'RUT',
  '1 Samuel': '1SA', '2 Samuel': '2SA', '1 Kings': '1KI', '2 Kings': '2KI',
  '1 Chronicles': '1CH', '2 Chronicles': '2CH', Ezra: 'EZR', Nehemiah: 'NEH',
  Esther: 'EST', Job: 'JOB', Psalms: 'PSA', Psalm: 'PSA', Proverbs: 'PRO',
  Ecclesiastes: 'ECC', 'Song of Solomon': 'SNG', Isaiah: 'ISA', Jeremiah: 'JER',
  Lamentations: 'LAM', Ezekiel: 'EZK', Daniel: 'DAN', Hosea: 'HOS',
  Joel: 'JOL', Amos: 'AMO', Obadiah: 'OBA', Jonah: 'JON', Micah: 'MIC',
  Nahum: 'NAM', Habakkuk: 'HAB', Zephaniah: 'ZEP', Haggai: 'HAG',
  Zechariah: 'ZEC', Malachi: 'MAL', Matthew: 'MAT', Mark: 'MRK',
  Luke: 'LUK', John: 'JHN', Acts: 'ACT', Romans: 'ROM',
  '1 Corinthians': '1CO', '2 Corinthians': '2CO', Galatians: 'GAL',
  Ephesians: 'EPH', Philippians: 'PHP', Colossians: 'COL',
  '1 Thessalonians': '1TH', '2 Thessalonians': '2TH', '1 Timothy': '1TI',
  '2 Timothy': '2TI', Titus: 'TIT', Philemon: 'PHM', Hebrews: 'HEB',
  James: 'JAS', '1 Peter': '1PE', '2 Peter': '2PE', '1 John': '1JN',
  '2 John': '2JN', '3 John': '3JN', Jude: 'JUD', Revelation: 'REV',
};

// ─────────────────────────────────────────────────────────────────────────────
// BSB ADAPTER — Berean Standard Bible (open license, default)
// ─────────────────────────────────────────────────────────────────────────────

export class BsbAdapter implements BibleProviderAdapter {
  readonly id = 'bsb';
  readonly name = 'Berean Standard Bible';
  readonly translations = ['BSB'];

  async getVerse(ref: string): Promise<BibleVerse> {
    const { book, chapter, verse } = parseVerseRef(ref);
    const result = await callBibleLookup({ reference: ref, translation: 'bsb', type: 'verse' });
    return { reference: result.reference, text: result.text, translation: 'BSB', book, chapter, verse };
  }

  async getPassage(book: string, chapter: number): Promise<BibleVerse[]> {
    const ref = `${book} ${chapter}`;
    const result = await callBibleLookup({ reference: ref, translation: 'bsb', type: 'passage' });
    return splitPassageIntoVerses(result, book, chapter, 'BSB');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WEB ADAPTER — World English Bible (public domain)
// ─────────────────────────────────────────────────────────────────────────────

export class WebAdapter implements BibleProviderAdapter {
  readonly id = 'web';
  readonly name = 'World English Bible';
  readonly translations = ['WEB'];

  async getVerse(ref: string): Promise<BibleVerse> {
    const { book, chapter, verse } = parseVerseRef(ref);
    const result = await callBibleLookup({ reference: ref, translation: 'web', type: 'verse' });
    return { reference: result.reference, text: result.text, translation: 'WEB', book, chapter, verse };
  }

  async getPassage(book: string, chapter: number): Promise<BibleVerse[]> {
    const result = await callBibleLookup({ reference: `${book} ${chapter}`, translation: 'web', type: 'passage' });
    return splitPassageIntoVerses(result, book, chapter, 'WEB');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KJV ADAPTER — King James Version (public domain)
// ─────────────────────────────────────────────────────────────────────────────

export class KjvAdapter implements BibleProviderAdapter {
  readonly id = 'kjv';
  readonly name = 'King James Version';
  readonly translations = ['KJV'];

  async getVerse(ref: string): Promise<BibleVerse> {
    const { book, chapter, verse } = parseVerseRef(ref);
    const result = await callBibleLookup({ reference: ref, translation: 'kjv', type: 'verse' });
    return { reference: result.reference, text: result.text, translation: 'KJV', book, chapter, verse };
  }

  async getPassage(book: string, chapter: number): Promise<BibleVerse[]> {
    const result = await callBibleLookup({ reference: `${book} ${chapter}`, translation: 'kjv', type: 'passage' });
    return splitPassageIntoVerses(result, book, chapter, 'KJV');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// YOUVERSION ADAPTER — BLOCKED STUB
// ─────────────────────────────────────────────────────────────────────────────

/**
 * BLOCKED: YouVersion requires a written commercial agreement with YouVersion/LifeChurch.
 * Slot preserved for future wiring. Do NOT use without written confirmation.
 */
export class YouVersionAdapter implements BibleProviderAdapter {
  readonly id = 'youversion';
  readonly name = 'YouVersion (Blocked)';
  readonly translations: string[] = [];

  async getVerse(): Promise<BibleVerse> {
    throw new Error('YouVersion adapter blocked pending written agreement');
  }
  async getPassage(): Promise<BibleVerse[]> {
    throw new Error('YouVersion adapter blocked pending written agreement');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PASSAGE SPLITTER
// The CF returns a full passage as a single text string. Split it into
// verse-numbered rows for the ScriptureReadAloud component.
// ─────────────────────────────────────────────────────────────────────────────

function splitPassageIntoVerses(
  result: BibleLookupResponse,
  book: string,
  chapter: number,
  translation: string,
): BibleVerse[] {
  const lines = result.text
    .split(/\n+/)
    .map((l) => l.trim())
    .filter(Boolean);

  return lines.map((line, idx) => ({
    reference: `${book} ${chapter}:${idx + 1}`,
    text:      line,
    translation,
    book,
    chapter,
    verse: idx + 1,
  }));
}

// ─────────────────────────────────────────────────────────────────────────────
// FACTORY
// ─────────────────────────────────────────────────────────────────────────────

export function getBibleProvider(config?: BibleProviderConfig): BibleProviderAdapter {
  switch (config?.BIBLE_PROVIDER ?? 'bsb') {
    case 'web': return new WebAdapter();
    case 'kjv': return new KjvAdapter();
    default:    return new BsbAdapter();
  }
}

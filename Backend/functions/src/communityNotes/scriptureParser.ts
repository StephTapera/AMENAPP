// scriptureParser.ts
// Extracts structured Scripture references from free text.
// Produces: scriptureRefs, scriptureRefStrings, scriptureKeys
// Keys are hierarchical: "MAT.5" (chapter) + "MAT.5.33"..."MAT.5.37" (verses)

export interface ScriptureRef {
  book: string;        // canonical code: "MAT", "JAS", "2PE"
  bookName: string;    // display: "Matthew"
  chapter: number;
  verseStart: number;
  verseEnd: number;
}

export interface ParsedScripture {
  scriptureRefs: ScriptureRef[];
  scriptureRefStrings: string[];
  scriptureKeys: string[];
}

// 66-entry book table: [canonicalCode, displayName, aliases[]]
const BOOKS: [string, string, string[]][] = [
  ["GEN", "Genesis",        ["gen", "ge", "gn"]],
  ["EXO", "Exodus",         ["exo", "ex", "exod"]],
  ["LEV", "Leviticus",      ["lev", "lv"]],
  ["NUM", "Numbers",        ["num", "nu", "nm"]],
  ["DEU", "Deuteronomy",    ["deu", "dt", "deut"]],
  ["JOS", "Joshua",         ["jos", "josh"]],
  ["JDG", "Judges",         ["jdg", "judg"]],
  ["RUT", "Ruth",           ["rut", "ru"]],
  ["1SA", "1 Samuel",       ["1sa", "1sam", "1samuel", "isam"]],
  ["2SA", "2 Samuel",       ["2sa", "2sam", "2samuel", "iisam"]],
  ["1KI", "1 Kings",        ["1ki", "1kgs", "1kings"]],
  ["2KI", "2 Kings",        ["2ki", "2kgs", "2kings"]],
  ["1CH", "1 Chronicles",   ["1ch", "1chr", "1chron"]],
  ["2CH", "2 Chronicles",   ["2ch", "2chr", "2chron"]],
  ["EZR", "Ezra",           ["ezr"]],
  ["NEH", "Nehemiah",       ["neh"]],
  ["EST", "Esther",         ["est", "esth"]],
  ["JOB", "Job",            ["job"]],
  ["PSA", "Psalms",         ["psa", "ps", "psalm", "psalms", "pss"]],
  ["PRO", "Proverbs",       ["pro", "prov", "pr"]],
  ["ECC", "Ecclesiastes",   ["ecc", "eccl", "qoh"]],
  ["SNG", "Song of Solomon", ["sng", "song", "sos", "canticles"]],
  ["ISA", "Isaiah",         ["isa", "is"]],
  ["JER", "Jeremiah",       ["jer", "je"]],
  ["LAM", "Lamentations",   ["lam", "la"]],
  ["EZK", "Ezekiel",        ["ezk", "eze", "ezek"]],
  ["DAN", "Daniel",         ["dan", "da", "dn"]],
  ["HOS", "Hosea",          ["hos", "ho"]],
  ["JOL", "Joel",           ["jol", "joel"]],
  ["AMO", "Amos",           ["amo", "am"]],
  ["OBA", "Obadiah",        ["oba", "obad"]],
  ["JON", "Jonah",          ["jon", "jnh"]],
  ["MIC", "Micah",          ["mic", "mi"]],
  ["NAM", "Nahum",          ["nam", "nah"]],
  ["HAB", "Habakkuk",       ["hab"]],
  ["ZEP", "Zephaniah",      ["zep", "zeph"]],
  ["HAG", "Haggai",         ["hag", "hg"]],
  ["ZEC", "Zechariah",      ["zec", "zech"]],
  ["MAL", "Malachi",        ["mal"]],
  ["MAT", "Matthew",        ["mat", "mt", "matt"]],
  ["MRK", "Mark",           ["mrk", "mk", "mar"]],
  ["LUK", "Luke",           ["luk", "lk"]],
  ["JHN", "John",           ["jhn", "jn", "joh"]],
  ["ACT", "Acts",           ["act", "ac"]],
  ["ROM", "Romans",         ["rom", "ro", "rm"]],
  ["1CO", "1 Corinthians",  ["1co", "1cor", "1corinthians"]],
  ["2CO", "2 Corinthians",  ["2co", "2cor", "2corinthians"]],
  ["GAL", "Galatians",      ["gal", "ga"]],
  ["EPH", "Ephesians",      ["eph"]],
  ["PHP", "Philippians",    ["php", "phil", "philippians"]],
  ["COL", "Colossians",     ["col"]],
  ["1TH", "1 Thessalonians", ["1th", "1thess", "1thes"]],
  ["2TH", "2 Thessalonians", ["2th", "2thess", "2thes"]],
  ["1TI", "1 Timothy",      ["1ti", "1tim", "1timothy"]],
  ["2TI", "2 Timothy",      ["2ti", "2tim", "2timothy"]],
  ["TIT", "Titus",          ["tit"]],
  ["PHM", "Philemon",       ["phm", "phlm", "philem"]],
  ["HEB", "Hebrews",        ["heb"]],
  ["JAS", "James",          ["jas", "jm"]],
  ["1PE", "1 Peter",        ["1pe", "1pet", "1peter"]],
  ["2PE", "2 Peter",        ["2pe", "2pet", "2peter"]],
  ["1JN", "1 John",         ["1jn", "1john", "1jo"]],
  ["2JN", "2 John",         ["2jn", "2john", "2jo"]],
  ["3JN", "3 John",         ["3jn", "3john", "3jo"]],
  ["JUD", "Jude",           ["jud", "jude"]],
  ["REV", "Revelation",     ["rev", "re", "rv", "apocalypse"]],
];

// Build lookup: normalised token -> [code, displayName]
const ALIAS_MAP = new Map<string, [string, string]>();
for (const [code, name, aliases] of BOOKS) {
  // canonical code lowercased
  ALIAS_MAP.set(code.toLowerCase(), [code, name]);
  // display name without spaces
  ALIAS_MAP.set(name.replace(/\s+/g, "").toLowerCase(), [code, name]);
  // every alias
  for (const alias of aliases) {
    ALIAS_MAP.set(alias.toLowerCase(), [code, name]);
  }
}

// Matches: optional leading number + book name token, optional dot, chapter, optional :verse[-verseEnd]
// Supports en-dash (–) and hyphen (-) as range separators
const REF_RE =
  /\b((?:[1-3]\s*)?[A-Za-z]{2,}(?:\s+of\s+[A-Za-z]+)?)\.?\s*(\d{1,3})(?::(\d{1,3})(?:\s*[–\-]\s*(\d{1,3}))?)?/g;

/**
 * Normalise a raw book token to a lookup key.
 * Strips internal spaces and lowercases.
 */
function normalizeToken(raw: string): string {
  return raw.replace(/\s+/g, "").toLowerCase();
}

/**
 * Resolve a raw book token (e.g. "2 Peter", "Ps", "1Cor") to [code, displayName]
 * Returns null if not a recognised book.
 */
function resolveBook(raw: string): [string, string] | null {
  const key = normalizeToken(raw);
  if (ALIAS_MAP.has(key)) return ALIAS_MAP.get(key)!;
  // Also try stripping a trailing period that snuck in
  const stripped = key.replace(/\.$/, "");
  if (ALIAS_MAP.has(stripped)) return ALIAS_MAP.get(stripped)!;
  return null;
}

/**
 * Parse all Scripture references from free text.
 */
export function parseScripture(text: string): ParsedScripture {
  const refs: ScriptureRef[] = [];
  const refStrings: string[] = [];
  const keysSet = new Set<string>();
  const seen = new Set<string>();

  let match: RegExpExecArray | null;
  REF_RE.lastIndex = 0; // reset stateful regex

  while ((match = REF_RE.exec(text)) !== null) {
    const [, rawBook, rawChapter, rawVerseStart, rawVerseEnd] = match;

    const resolved = resolveBook(rawBook);
    if (!resolved) continue;

    const [code, bookName] = resolved;
    const chapter = parseInt(rawChapter, 10);
    const verseStart = rawVerseStart ? parseInt(rawVerseStart, 10) : 0;
    const verseEnd = rawVerseEnd
      ? parseInt(rawVerseEnd, 10)
      : verseStart > 0
      ? verseStart
      : 0;

    // Deduplication signature
    const sig = `${code}|${chapter}|${verseStart}|${verseEnd}`;
    if (seen.has(sig)) continue;
    seen.add(sig);

    refs.push({ book: code, bookName, chapter, verseStart, verseEnd });

    // Build human-readable reference string
    let refStr = `${bookName} ${chapter}`;
    if (verseStart > 0) {
      refStr += `:${verseStart}`;
      if (verseEnd > verseStart) refStr += `-${verseEnd}`;
    }
    refStrings.push(refStr);

    // Chapter key always emitted
    keysSet.add(`${code}.${chapter}`);

    // Verse keys: one per verse in range, capped at span of 60
    if (verseStart > 0) {
      const end = verseEnd >= verseStart ? verseEnd : verseStart;
      const cap = Math.min(end, verseStart + 59);
      for (let v = verseStart; v <= cap; v++) {
        keysSet.add(`${code}.${chapter}.${v}`);
      }
    }
  }

  return {
    scriptureRefs: refs,
    scriptureRefStrings: refStrings,
    scriptureKeys: Array.from(keysSet),
  };
}

/**
 * Trim body to at most `max` characters on a word boundary, appending '…'.
 */
export function buildExcerpt(body: string, max = 240): string {
  if (body.length <= max) return body;
  const trimmed = body.slice(0, max);
  const lastSpace = trimmed.lastIndexOf(" ");
  return (lastSpace > 0 ? trimmed.slice(0, lastSpace) : trimmed) + "…";
}

"use strict";
// capabilities/scripture/referenceParser.ts — Deterministic scripture reference parser (Wave 1: Lane B)
//
// NO LLM. Pure TypeScript string parsing.
// Returns OSIS-format refs: "Rom.6.1-Rom.6.4", "Jhn.3.16", etc.
//
// False-positive prevention:
//   - Requires a known book name/abbreviation as whole word before chapter:verse
//   - Will NOT match "at 3:16 pm", "see figure 2:1", "chapter 3:16 of the report"
Object.defineProperty(exports, "__esModule", { value: true });
exports.detectReferences = detectReferences;
exports.parseRefs = parseRefs;
exports.detectReferencesInBlocks = detectReferencesInBlocks;
// prettier-ignore
const BOOK_ENTRIES = [
    // Old Testament
    { names: ["genesis", "gen", "ge"], osis: "Gen", fullName: "Genesis" },
    { names: ["exodus", "exo", "ex"], osis: "Exod", fullName: "Exodus" },
    { names: ["leviticus", "lev", "le"], osis: "Lev", fullName: "Leviticus" },
    { names: ["numbers", "num", "nu"], osis: "Num", fullName: "Numbers" },
    { names: ["deuteronomy", "deut", "deu", "dt"], osis: "Deut", fullName: "Deuteronomy" },
    { names: ["joshua", "josh", "jos"], osis: "Josh", fullName: "Joshua" },
    { names: ["judges", "judg", "jdg", "jg"], osis: "Judg", fullName: "Judges" },
    { names: ["ruth"], osis: "Ruth", fullName: "Ruth" },
    { names: ["1 samuel", "1samuel", "1sam", "1sa", "1 sam"], osis: "1Sam", fullName: "1 Samuel" },
    { names: ["2 samuel", "2samuel", "2sam", "2sa", "2 sam"], osis: "2Sam", fullName: "2 Samuel" },
    { names: ["1 kings", "1kings", "1kgs", "1ki", "1 kgs"], osis: "1Kgs", fullName: "1 Kings" },
    { names: ["2 kings", "2kings", "2kgs", "2ki", "2 kgs"], osis: "2Kgs", fullName: "2 Kings" },
    { names: ["1 chronicles", "1chronicles", "1chr", "1ch", "1 chr"], osis: "1Chr", fullName: "1 Chronicles" },
    { names: ["2 chronicles", "2chronicles", "2chr", "2ch", "2 chr"], osis: "2Chr", fullName: "2 Chronicles" },
    { names: ["ezra", "ezr"], osis: "Ezra", fullName: "Ezra" },
    { names: ["nehemiah", "neh", "ne"], osis: "Neh", fullName: "Nehemiah" },
    { names: ["esther", "esth", "est"], osis: "Esth", fullName: "Esther" },
    { names: ["job"], osis: "Job", fullName: "Job" },
    { names: ["psalms", "psalm", "psa", "ps"], osis: "Ps", fullName: "Psalm" },
    { names: ["proverbs", "prov", "pro", "pr"], osis: "Prov", fullName: "Proverbs" },
    { names: ["ecclesiastes", "eccl", "ecc", "ec"], osis: "Eccl", fullName: "Ecclesiastes" },
    { names: ["song of solomon", "song of songs", "song", "sos", "sng", "ss", "so"], osis: "Song", fullName: "Song of Solomon" },
    { names: ["isaiah", "isa"], osis: "Isa", fullName: "Isaiah" },
    { names: ["jeremiah", "jer"], osis: "Jer", fullName: "Jeremiah" },
    { names: ["lamentations", "lam"], osis: "Lam", fullName: "Lamentations" },
    { names: ["ezekiel", "ezek", "eze"], osis: "Ezek", fullName: "Ezekiel" },
    { names: ["daniel", "dan"], osis: "Dan", fullName: "Daniel" },
    { names: ["hosea", "hos"], osis: "Hos", fullName: "Hosea" },
    { names: ["joel"], osis: "Joel", fullName: "Joel" },
    { names: ["amos"], osis: "Amos", fullName: "Amos" },
    { names: ["obadiah", "obad", "ob"], osis: "Obad", fullName: "Obadiah" },
    { names: ["jonah", "jon"], osis: "Jonah", fullName: "Jonah" },
    { names: ["micah", "mic"], osis: "Mic", fullName: "Micah" },
    { names: ["nahum", "nah"], osis: "Nah", fullName: "Nahum" },
    { names: ["habakkuk", "hab"], osis: "Hab", fullName: "Habakkuk" },
    { names: ["zephaniah", "zeph", "zep"], osis: "Zeph", fullName: "Zephaniah" },
    { names: ["haggai", "hag"], osis: "Hag", fullName: "Haggai" },
    { names: ["zechariah", "zech", "zec"], osis: "Zech", fullName: "Zechariah" },
    { names: ["malachi", "mal"], osis: "Mal", fullName: "Malachi" },
    // New Testament
    { names: ["matthew", "matt", "mt"], osis: "Matt", fullName: "Matthew" },
    { names: ["mark", "mk", "mr"], osis: "Mark", fullName: "Mark" },
    { names: ["luke", "lk", "lu"], osis: "Luke", fullName: "Luke" },
    { names: ["john", "jn", "joh"], osis: "Jhn", fullName: "John" },
    { names: ["acts", "act"], osis: "Acts", fullName: "Acts" },
    { names: ["romans", "rom"], osis: "Rom", fullName: "Romans" },
    { names: ["1 corinthians", "1corinthians", "1cor", "1co", "1 cor"], osis: "1Co", fullName: "1 Corinthians" },
    { names: ["2 corinthians", "2corinthians", "2cor", "2co", "2 cor"], osis: "2Co", fullName: "2 Corinthians" },
    { names: ["galatians", "gal"], osis: "Gal", fullName: "Galatians" },
    { names: ["ephesians", "eph"], osis: "Eph", fullName: "Ephesians" },
    { names: ["philippians", "phil", "php"], osis: "Phil", fullName: "Philippians" },
    { names: ["colossians", "col"], osis: "Col", fullName: "Colossians" },
    { names: ["1 thessalonians", "1thessalonians", "1thess", "1th", "1 thess"], osis: "1Thess", fullName: "1 Thessalonians" },
    { names: ["2 thessalonians", "2thessalonians", "2thess", "2th", "2 thess"], osis: "2Thess", fullName: "2 Thessalonians" },
    { names: ["1 timothy", "1timothy", "1tim", "1ti", "1 tim"], osis: "1Tim", fullName: "1 Timothy" },
    { names: ["2 timothy", "2timothy", "2tim", "2ti", "2 tim"], osis: "2Tim", fullName: "2 Timothy" },
    { names: ["titus", "tit"], osis: "Titus", fullName: "Titus" },
    { names: ["philemon", "phlm", "phm"], osis: "Phlm", fullName: "Philemon" },
    { names: ["hebrews", "heb"], osis: "Heb", fullName: "Hebrews" },
    { names: ["james", "jas"], osis: "Jas", fullName: "Jas" },
    { names: ["1 peter", "1peter", "1pet", "1pe", "1 pet"], osis: "1Pet", fullName: "1 Peter" },
    { names: ["2 peter", "2peter", "2pet", "2pe", "2 pet"], osis: "2Pet", fullName: "2 Peter" },
    { names: ["1 john", "1john", "1jn", "1jo", "1 jn"], osis: "1Jn", fullName: "1 John" },
    { names: ["2 john", "2john", "2jn", "2jo", "2 jn"], osis: "2Jn", fullName: "2 John" },
    { names: ["3 john", "3john", "3jn", "3jo", "3 jn"], osis: "3Jn", fullName: "3 John" },
    { names: ["jude"], osis: "Jude", fullName: "Jude" },
    { names: ["revelation", "rev", "re"], osis: "Rev", fullName: "Revelation" },
];
// Build lookup: lowercase alias → { osis, fullName }
const BOOK_LOOKUP = new Map();
for (const entry of BOOK_ENTRIES) {
    for (const name of entry.names) {
        BOOK_LOOKUP.set(name.toLowerCase(), { osis: entry.osis, fullName: entry.fullName });
    }
}
// ── Regex components ──────────────────────────────────────────────────────────
// Numbered prefix: "1 " "2 " "3 " (with optional space — e.g. "1Cor")
const NUM_PREFIX = "(?:[123]\\s*)";
// Book name core: must start at a word boundary
// We match either a full name (multi-word like "Song of Solomon") or single token
// The actual book lookup validates the matched token.
// Chapter:verse range patterns:
//   3:16        — single verse
//   3:16-18     — same-chapter verse range
//   3:16-4:1    — cross-chapter range
//   13           — whole chapter (no colon)
const CV_PATTERN = "(\\d{1,3})(?::(\\d{1,3})(?:-(\\d{1,3}(?::(\\d{1,3}))?))?)?";
;
/**
 * detectReferences — parse all scripture references in a text string.
 *
 * @param text    - The text to search
 * @param blockId - The block identifier to attach to results
 * @returns       - Array of ScriptureDetection objects
 */
function detectReferences(text, blockId) {
    const results = [];
    const refs = parseRefs(text);
    for (const ref of refs) {
        results.push({
            blockId,
            range: { start: ref.start, end: ref.end },
            osisRef: ref.osisRef,
            display: ref.display,
        });
    }
    return results;
}
/**
 * parseRefs — low-level parser that returns ParsedRef objects with character offsets.
 */
function parseRefs(text) {
    const results = [];
    // We use a two-pass approach:
    // 1. Find all possible book token positions via a broad regex
    // 2. For each match, look up the book and parse the chapter/verse that follows
    // This regex matches:
    //   - Optional number prefix (1-3)
    //   - One or more word characters (book name token)
    //   - Optionally followed by more words (for "Song of Solomon")
    // We also handle special multi-word books first.
    // Multi-word book names to check first (longest match wins)
    const multiWordBooks = [
        "song of solomon",
        "song of songs",
        "1 samuel", "2 samuel",
        "1 kings", "2 kings",
        "1 chronicles", "2 chronicles",
        "1 corinthians", "2 corinthians",
        "1 thessalonians", "2 thessalonians",
        "1 timothy", "2 timothy",
        "1 peter", "2 peter",
        "1 john", "2 john", "3 john",
    ];
    const candidates = [];
    const lowerText = text.toLowerCase();
    // Try multi-word books first
    for (const multiName of multiWordBooks) {
        let searchIdx = 0;
        while (searchIdx < lowerText.length) {
            const idx = lowerText.indexOf(multiName, searchIdx);
            if (idx === -1)
                break;
            // Verify word boundary at start
            const beforeIdx = idx - 1;
            const beforeChar = beforeIdx >= 0 ? lowerText[beforeIdx] : " ";
            if (beforeIdx >= 0 && /\w/.test(beforeChar)) {
                searchIdx = idx + 1;
                continue;
            }
            // Verify word boundary at end
            const afterIdx = idx + multiName.length;
            const afterChar = afterIdx < lowerText.length ? lowerText[afterIdx] : " ";
            if (/\w/.test(afterChar)) {
                searchIdx = idx + 1;
                continue;
            }
            const entry = BOOK_LOOKUP.get(multiName);
            if (entry) {
                candidates.push({
                    bookEntry: entry,
                    rawBook: text.slice(idx, idx + multiName.length),
                    start: idx,
                    end: idx + multiName.length,
                });
            }
            searchIdx = idx + multiName.length;
        }
    }
    // Single-word (possibly numbered) books
    // Pattern: optional number + optional space + word chars
    const singleBookRegex = /\b((?:[123]\s*)?[A-Za-z]+)\b/g;
    let m;
    while ((m = singleBookRegex.exec(text)) !== null) {
        const matchedText = m[1];
        const matchStart = m.index;
        const matchEnd = matchStart + m[0].length;
        // Skip if overlapping with a multi-word candidate
        const overlaps = candidates.some((c) => matchStart < c.end && matchEnd > c.start);
        if (overlaps)
            continue;
        const lookup = matchedText.toLowerCase().replace(/\s+/g, " ");
        const entry = BOOK_LOOKUP.get(lookup);
        if (!entry)
            continue;
        candidates.push({
            bookEntry: entry,
            rawBook: matchedText,
            start: matchStart,
            end: matchEnd,
        });
    }
    // Sort candidates by position
    candidates.sort((a, b) => a.start - b.start);
    // For each candidate, try to parse chapter/verse after it
    const usedRanges = [];
    for (const cand of candidates) {
        // Skip if position already consumed
        if (usedRanges.some((r) => cand.start < r.end && cand.end > r.start)) {
            continue;
        }
        const afterBook = text.slice(cand.end);
        // Try to match chapter/verse: optional whitespace then digit(s) then optional :verse
        // Match: " 3:16-4:1" or " 3:16-18" or " 3:16,17" or " 3" etc.
        const cvMatch = afterBook.match(/^(\s+)(\d{1,3})(?::(\d{1,3})(?:-(\d{1,3})(?::(\d{1,3}))?)?)?/);
        if (!cvMatch) {
            // No chapter/verse follows — could be a bare book mention, skip for now
            // (We only detect references with explicit chapter or chapter:verse)
            continue;
        }
        const sep = cvMatch[1]; // whitespace separator
        const chapter = parseInt(cvMatch[2], 10);
        const startVerse = cvMatch[3] !== undefined ? parseInt(cvMatch[3], 10) : undefined;
        const rangeEnd = cvMatch[4] !== undefined ? parseInt(cvMatch[4], 10) : undefined;
        const rangeEndChapter = cvMatch[5] !== undefined ? parseInt(cvMatch[5], 10) : undefined;
        if (chapter < 1)
            continue;
        if (startVerse !== undefined && startVerse < 1)
            continue;
        if (rangeEnd !== undefined && startVerse !== undefined && rangeEnd < startVerse && rangeEndChapter === undefined)
            continue;
        // Compute end position of the full match in original text
        const matchLength = cand.end - cand.start + sep.length + cvMatch[2].length +
            (cvMatch[3] !== undefined ? 1 + cvMatch[3].length : 0) +
            (cvMatch[4] !== undefined ? 1 + cvMatch[4].length : 0) +
            (cvMatch[5] !== undefined ? 1 + cvMatch[5].length : 0);
        const refEnd = cand.start + matchLength;
        // Build OSIS ref and display string
        const { osisRef, display } = buildOsisRef(cand.bookEntry, chapter, startVerse, rangeEnd, rangeEndChapter);
        usedRanges.push({ start: cand.start, end: refEnd });
        results.push({ osisRef, display, start: cand.start, end: refEnd });
    }
    // Sort by start position
    results.sort((a, b) => a.start - b.start);
    return results;
}
// ── OSIS builder ──────────────────────────────────────────────────────────────
function buildOsisRef(book, chapter, startVerse, endVerse, endChapter) {
    const code = book.osis;
    const name = book.fullName;
    // Whole chapter (e.g. "1 Cor 13")
    if (startVerse === undefined) {
        return {
            osisRef: `${code}.${chapter}`,
            display: `${name} ${chapter}`,
        };
    }
    // Single verse (e.g. "John 3:16")
    if (endVerse === undefined) {
        return {
            osisRef: `${code}.${chapter}.${startVerse}`,
            display: `${name} ${chapter}:${startVerse}`,
        };
    }
    // Verse range (e.g. "Romans 6:1-4")
    if (endChapter === undefined) {
        // Same chapter
        return {
            osisRef: `${code}.${chapter}.${startVerse}-${code}.${chapter}.${endVerse}`,
            display: `${name} ${chapter}:${startVerse}-${endVerse}`,
        };
    }
    // Cross-chapter range (e.g. "1 Cor 13:1-14:1")
    return {
        osisRef: `${code}.${chapter}.${startVerse}-${code}.${endChapter}.${endVerse}`,
        display: `${name} ${chapter}:${startVerse}-${endChapter}:${endVerse}`,
    };
}
// ── Batch entry point (for callables) ─────────────────────────────────────────
/**
 * detectReferencesInBlocks — detect scripture refs across multiple blocks.
 *
 * @param blocks - Array of { blockId, text } objects (max 50)
 * @returns      - Array of all ScriptureDetection objects across all blocks
 */
function detectReferencesInBlocks(blocks) {
    const all = [];
    for (const block of blocks) {
        const refs = detectReferences(block.text, block.blockId);
        all.push(...refs);
    }
    return all;
}

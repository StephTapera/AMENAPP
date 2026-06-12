# NIS Wave 1 — Lane C Build Notes

**Lane:** C (scripture-quote detector)
**Date:** 2026-06-12
**Branch:** safety-hardening

---

## Commit Hashes

| Commit | Description |
|--------|-------------|
| `a5e15b57` | feat(nis/lane-c): add scriptureQuoteDetector — pattern-matching corpus, 28 verses, threshold 0.72 |
| `decfa5fc` | feat(nis/lane-c): wire index.ts stub to call scriptureQuoteDetector implementation |

---

## tsc --noEmit Output

```
(no output — zero errors, exit code 0)
```

Verified with:
```
cd Backend/functions && ./node_modules/.bin/tsc --noEmit
```

---

## Corpus Size

**28 verses indexed** covering the following verseIds:

| verseId | Reference |
|---------|-----------|
| john.3.16 | John 3:16 |
| psalm.23.1 | Psalm 23:1 |
| romans.8.28 | Romans 8:28 |
| philippians.4.13 | Philippians 4:13 |
| jeremiah.29.11 | Jeremiah 29:11 |
| isaiah.40.31 | Isaiah 40:31 |
| joshua.1.9 | Joshua 1:9 |
| matthew.6.33 | Matthew 6:33 |
| romans.10.9 | Romans 10:9 |
| john.14.6 | John 14:6 |
| revelation.3.20 | Revelation 3:20 |
| proverbs.3.5 | Proverbs 3:5 |
| proverbs.3.6 | Proverbs 3:6 |
| ephesians.2.8 | Ephesians 2:8 |
| ephesians.2.9 | Ephesians 2:9 |
| genesis.1.1 | Genesis 1:1 |
| john.1.1 | John 1:1 |
| psalm.46.10 | Psalm 46:10 |
| 1corinthians.13.4 | 1 Corinthians 13:4 |
| 1corinthians.13.7 | 1 Corinthians 13:7 |
| matthew.11.28 | Matthew 11:28 |
| galatians.5.22 | Galatians 5:22 |
| colossians.3.23 | Colossians 3:23 |
| hebrews.11.1 | Hebrews 11:1 |
| romans.6.23 | Romans 6:23 |
| 2timothy.3.16 | 2 Timothy 3:16 |
| psalm.119.105 | Psalm 119:105 |
| matthew.28.19 | Matthew 28:19 |
| matthew.28.20 | Matthew 28:20 |
| 1john.4.8 | 1 John 4:8 |
| romans.12.2 | Romans 12:2 |
| philippians.4.7 | Philippians 4:7 |

Total: 32 verse entries (28 unique root verses, some split across verse numbers e.g. Prov 3:5/3:6, Eph 2:8/2:9, Matt 28:19/28:20, 1 Cor 13:4/13:7)

---

## Implementation Notes

- **Algorithm:** Trigram Dice coefficient + substring-containment bonus (+0.15)
- **Threshold:** 0.72 (lower than Pinecone embedding threshold of 0.86; pattern-matching is less precise)
- **Short-sentence guard:** sentences < 8 words are skipped
- **Deduplication:** highest-scoring fragment per sentence is returned (one result per sentence max)
- **Wave 2+ upgrade path:** `nisDetectScriptureQuote` in `index.ts` delegates via `_nisDetectScriptureQuoteImpl`; swapping to Pinecone in Wave 2 only requires updating `scriptureQuoteDetector.ts` — no signature changes needed anywhere
- **Contract:** frozen at `async function nisDetectScriptureQuote(sentences: string[], noteId: string): Promise<Array<{sentence: string, verseId: string, score: number}>>`
- **verseId format:** lowercase dot-separated `book.chapter.verse` (e.g. `john.3.16`, `psalm.23.1`)

---

## Files Changed

- `Backend/functions/src/nis/scriptureQuoteDetector.ts` — CREATED (Lane C implementation)
- `Backend/functions/src/nis/index.ts` — MODIFIED (stub now delegates to real impl)

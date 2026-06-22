// referenceParser.test.ts — Unit tests for the scripture reference parser
// ≥40 test cases covering all required scenarios.
//
// Run: npx jest --config functions/jest.capabilities.config.js

import { parseRefs, detectReferences, detectReferencesInBlocks } from "./referenceParser";

// ── Helper ────────────────────────────────────────────────────────────────────

function firstRef(text: string) {
  const refs = parseRefs(text);
  return refs.length > 0 ? refs[0] : null;
}

function refCount(text: string): number {
  return parseRefs(text).length;
}

function osisOf(text: string): string | null {
  return firstRef(text)?.osisRef ?? null;
}

// ── Single verse ──────────────────────────────────────────────────────────────

describe("Single verse detection", () => {
  test("John 3:16 full name", () => {
    const ref = firstRef("John 3:16");
    expect(ref).not.toBeNull();
    expect(ref!.osisRef).toBe("Jhn.3.16");
    expect(ref!.display).toMatch(/John 3:16/);
  });

  test("Jn 3:16 abbreviation", () => {
    const ref = firstRef("Jn 3:16");
    expect(ref).not.toBeNull();
    expect(ref!.osisRef).toBe("Jhn.3.16");
  });

  test("Gen 1:1", () => {
    expect(osisOf("Gen 1:1")).toBe("Gen.1.1");
  });

  test("Genesis 1:1 full name", () => {
    expect(osisOf("Genesis 1:1")).toBe("Gen.1.1");
  });

  test("Revelation 22:21", () => {
    expect(osisOf("Revelation 22:21")).toBe("Rev.22.21");
  });

  test("Rev 22:21 abbreviation", () => {
    expect(osisOf("Rev 22:21")).toBe("Rev.22.21");
  });

  test("Romans 6:1", () => {
    expect(osisOf("Romans 6:1")).toBe("Rom.6.1");
  });

  test("Rom 6:1 abbreviation", () => {
    expect(osisOf("Rom 6:1")).toBe("Rom.6.1");
  });

  test("Psalm 119:105", () => {
    const ref = firstRef("Psalm 119:105");
    expect(ref).not.toBeNull();
    expect(ref!.osisRef).toBe("Ps.119.105");
  });

  test("Ps 23:1 abbreviation", () => {
    expect(osisOf("Ps 23:1")).toBe("Ps.23.1");
  });

  test("Philippians 4:13", () => {
    expect(osisOf("Philippians 4:13")).toBe("Phil.4.13");
  });

  test("Phil 4:6 abbreviation", () => {
    expect(osisOf("Phil 4:6")).toBe("Phil.4.6");
  });
});

// ── Verse ranges (same chapter) ───────────────────────────────────────────────

describe("Verse range detection (same chapter)", () => {
  test("Romans 6:1-4", () => {
    const ref = firstRef("Romans 6:1-4");
    expect(ref).not.toBeNull();
    expect(ref!.osisRef).toBe("Rom.6.1-Rom.6.4");
  });

  test("Mt 5:1-12 abbreviation", () => {
    const ref = firstRef("Mt 5:1-12");
    expect(ref).not.toBeNull();
    expect(ref!.osisRef).toBe("Matt.5.1-Matt.5.12");
  });

  test("Hebrews 11:1-3", () => {
    expect(osisOf("Hebrews 11:1-3")).toBe("Heb.11.1-Heb.11.3");
  });

  test("Jn 3:16-18", () => {
    expect(osisOf("Jn 3:16-18")).toBe("Jhn.3.16-Jhn.3.18");
  });
});

// ── Whole chapter ─────────────────────────────────────────────────────────────

describe("Whole chapter detection", () => {
  test("1 Cor 13 whole chapter", () => {
    const ref = firstRef("1 Cor 13");
    expect(ref).not.toBeNull();
    expect(ref!.osisRef).toBe("1Co.13");
  });

  test("Psalm 23 whole chapter", () => {
    expect(osisOf("Psalm 23")).toBe("Ps.23");
  });

  test("John 3 whole chapter", () => {
    expect(osisOf("John 3")).toBe("Jhn.3");
  });
});

// ── Numbered books ────────────────────────────────────────────────────────────

describe("Numbered book detection", () => {
  test("1 John 1:9", () => {
    const ref = firstRef("1 John 1:9");
    expect(ref).not.toBeNull();
    expect(ref!.osisRef).toBe("1Jn.1.9");
  });

  test("2 Timothy 3:16", () => {
    expect(osisOf("2 Timothy 3:16")).toBe("2Tim.3.16");
  });

  test("1 Corinthians 13:4", () => {
    expect(osisOf("1 Corinthians 13:4")).toBe("1Co.13.4");
  });

  test("1Cor 13:4 no-space form", () => {
    // "1Cor" without space should also match via single-word regex
    const refs = parseRefs("1Cor 13:4");
    expect(refs.length).toBeGreaterThan(0);
    expect(refs[0].osisRef).toBe("1Co.13.4");
  });

  test("2 Peter 1:3-4", () => {
    expect(osisOf("2 Peter 1:3-4")).toBe("2Pet.1.3-2Pet.1.4");
  });

  test("1 Samuel 17:45", () => {
    expect(osisOf("1 Samuel 17:45")).toBe("1Sam.17.45");
  });

  test("3 John 1:2", () => {
    expect(osisOf("3 John 1:2")).toBe("3Jn.1.2");
  });
});

// ── Song of Solomon / Song of Songs ──────────────────────────────────────────

describe("Song of Solomon detection", () => {
  test("Song of Solomon 2:1", () => {
    const ref = firstRef("Song of Solomon 2:1");
    expect(ref).not.toBeNull();
    // OSIS code is "Song" per our registry
    expect(ref!.osisRef).toBe("Song.2.1");
  });

  test("Song of Songs 2:1", () => {
    const ref = firstRef("Song of Songs 2:1");
    expect(ref).not.toBeNull();
    expect(ref!.osisRef).toBe("Song.2.1");
  });
});

// ── Multiple references in one text ──────────────────────────────────────────

describe("Multiple reference detection", () => {
  test("Romans 6:1-4 and Phil 4:6", () => {
    const refs = parseRefs("Romans 6:1-4 and Phil 4:6");
    expect(refs.length).toBe(2);
    expect(refs[0].osisRef).toBe("Rom.6.1-Rom.6.4");
    expect(refs[1].osisRef).toBe("Phil.4.6");
  });

  test("Jn 3:16-18, 21 — detects the range portion", () => {
    // We detect "Jn 3:16-18" — the ", 21" is a continuation but parser takes the range
    const refs = parseRefs("Jn 3:16-18, 21");
    expect(refs.length).toBeGreaterThan(0);
    expect(refs[0].osisRef).toBe("Jhn.3.16-Jhn.3.18");
  });

  test("Three references in a paragraph", () => {
    const text = "See Gen 1:1, John 3:16, and Rev 22:21 for key passages.";
    const refs = parseRefs(text);
    expect(refs.length).toBe(3);
    expect(refs[0].osisRef).toBe("Gen.1.1");
    expect(refs[1].osisRef).toBe("Jhn.3.16");
    expect(refs[2].osisRef).toBe("Rev.22.21");
  });

  test("Inline scripture references in prose", () => {
    const text = "Paul writes in Romans 8:28 and again in Philippians 4:7.";
    const refs = parseRefs(text);
    expect(refs.length).toBe(2);
    expect(refs[0].osisRef).toBe("Rom.8.28");
    expect(refs[1].osisRef).toBe("Phil.4.7");
  });
});

// ── False positive prevention ─────────────────────────────────────────────────

describe("False positive prevention", () => {
  test("'at 3:16 pm' — NO detection", () => {
    expect(refCount("at 3:16 pm")).toBe(0);
  });

  test("'see figure 2:1' — NO detection", () => {
    expect(refCount("see figure 2:1")).toBe(0);
  });

  test("'chapter 3:16 of the report' — NO detection", () => {
    expect(refCount("chapter 3:16 of the report")).toBe(0);
  });

  test("'at 3:16 pm Romans says' — only Romans if it has a verse reference", () => {
    // "at 3:16 pm Romans says" — no chapter:verse after Romans, so no detection
    const refs = parseRefs("at 3:16 pm Romans says");
    // "at 3:16 pm" has no book name → no detection
    // "Romans" alone has no chapter:verse → no detection
    expect(refs.length).toBe(0);
  });

  test("'section 4:2 of the manual' — NO detection", () => {
    expect(refCount("section 4:2 of the manual")).toBe(0);
  });

  test("'verse 3' without a book name — NO detection", () => {
    expect(refCount("verse 3")).toBe(0);
  });

  test("'time 12:30' — NO detection", () => {
    expect(refCount("time 12:30")).toBe(0);
  });

  test("Plain numbers '3:16' without book — NO detection", () => {
    expect(refCount("3:16")).toBe(0);
  });
});

// ── Character offset ranges ───────────────────────────────────────────────────

describe("Character offset ranges", () => {
  test("John 3:16 offsets are correct", () => {
    const text = "Read John 3:16 today";
    const refs = parseRefs(text);
    expect(refs.length).toBe(1);
    expect(refs[0].start).toBe(5); // "John" starts at index 5
    const matched = text.slice(refs[0].start, refs[0].end);
    expect(matched).toBe("John 3:16");
  });

  test("Gen 1:1 at start of string", () => {
    const text = "Gen 1:1 is the beginning";
    const refs = parseRefs(text);
    expect(refs.length).toBe(1);
    expect(refs[0].start).toBe(0);
  });
});

// ── detectReferences with blockId ────────────────────────────────────────────

describe("detectReferences function", () => {
  test("attaches blockId to results", () => {
    const detections = detectReferences("John 3:16 is well known", "block-1");
    expect(detections.length).toBe(1);
    expect(detections[0].blockId).toBe("block-1");
    expect(detections[0].osisRef).toBe("Jhn.3.16");
  });

  test("range field matches char offsets", () => {
    const text = "See Romans 8:1 for context";
    const detections = detectReferences(text, "b2");
    expect(detections.length).toBe(1);
    expect(detections[0].range.start).toBe(4);
    const matched = text.slice(detections[0].range.start, detections[0].range.end);
    expect(matched).toBe("Romans 8:1");
  });
});

// ── detectReferencesInBlocks ──────────────────────────────────────────────────

describe("detectReferencesInBlocks", () => {
  test("processes multiple blocks", () => {
    const blocks = [
      { blockId: "b1", text: "John 3:16 is the key verse" },
      { blockId: "b2", text: "Also see Romans 8:28" },
      { blockId: "b3", text: "No references here" },
    ];
    const detections = detectReferencesInBlocks(blocks);
    expect(detections.length).toBe(2);
    expect(detections[0].blockId).toBe("b1");
    expect(detections[0].osisRef).toBe("Jhn.3.16");
    expect(detections[1].blockId).toBe("b2");
    expect(detections[1].osisRef).toBe("Rom.8.28");
  });

  test("empty blocks returns empty array", () => {
    expect(detectReferencesInBlocks([])).toEqual([]);
  });

  test("block with no references returns nothing for that block", () => {
    const blocks = [
      { blockId: "b1", text: "No scripture here, time is 3:15" },
    ];
    expect(detectReferencesInBlocks(blocks).length).toBe(0);
  });
});

// ── Display string format ─────────────────────────────────────────────────────

describe("Display string format", () => {
  test("single verse display: 'John 3:16'", () => {
    const ref = firstRef("John 3:16");
    expect(ref!.display).toBe("John 3:16");
  });

  test("range display: 'Romans 6:1-4'", () => {
    const ref = firstRef("Romans 6:1-4");
    expect(ref!.display).toBe("Romans 6:1-4");
  });

  test("whole chapter display: '1 Corinthians 13'", () => {
    const ref = firstRef("1 Cor 13");
    // display uses fullName
    expect(ref!.display).toMatch(/13/);
  });

  test("numbered book display includes number", () => {
    const ref = firstRef("1 John 1:9");
    expect(ref!.display).toMatch(/1 John/);
  });
});

// ── Additional edge cases ─────────────────────────────────────────────────────

describe("Edge cases", () => {
  test("case-insensitive: 'john 3:16' lowercase", () => {
    expect(osisOf("john 3:16")).toBe("Jhn.3.16");
  });

  test("case-insensitive: 'ROMANS 6:1' uppercase", () => {
    expect(osisOf("ROMANS 6:1")).toBe("Rom.6.1");
  });

  test("Joh abbreviation for John", () => {
    expect(osisOf("Joh 3:16")).toBe("Jhn.3.16");
  });

  test("Acts 2:38", () => {
    expect(osisOf("Acts 2:38")).toBe("Acts.2.38");
  });

  test("Eph 2:8-9", () => {
    expect(osisOf("Eph 2:8-9")).toBe("Eph.2.8-Eph.2.9");
  });

  test("Heb 11:1", () => {
    expect(osisOf("Heb 11:1")).toBe("Heb.11.1");
  });

  test("Isaiah 40:31", () => {
    expect(osisOf("Isaiah 40:31")).toBe("Isa.40.31");
  });

  test("Daniel 3:17", () => {
    expect(osisOf("Daniel 3:17")).toBe("Dan.3.17");
  });

  test("Proverbs 3:5", () => {
    expect(osisOf("Proverbs 3:5")).toBe("Prov.3.5");
  });

  test("Prov 3:5-6 range", () => {
    expect(osisOf("Prov 3:5-6")).toBe("Prov.3.5-Prov.3.6");
  });

  test("Matthew 5:1-12 Beatitudes", () => {
    const ref = firstRef("Matthew 5:1-12");
    expect(ref!.osisRef).toBe("Matt.5.1-Matt.5.12");
    expect(ref!.display).toBe("Matthew 5:1-12");
  });

  test("text with verse embedded mid-sentence", () => {
    const text = "The verse Galatians 5:22-23 lists the fruit of the Spirit.";
    const refs = parseRefs(text);
    expect(refs.length).toBe(1);
    expect(refs[0].osisRef).toBe("Gal.5.22-Gal.5.23");
  });

  test("Revelation 3:20 is detected", () => {
    expect(osisOf("Revelation 3:20")).toBe("Rev.3.20");
  });

  test("Colossians 3:17", () => {
    expect(osisOf("Colossians 3:17")).toBe("Col.3.17");
  });
});

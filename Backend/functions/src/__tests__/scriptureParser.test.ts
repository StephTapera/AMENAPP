import { parseScripture } from "../communityNotes/scriptureParser";

describe("parseScripture", () => {
  test("2 Peter 1:5-7 — verse range with chapter key + verse keys", () => {
    const r = parseScripture("See 2 Peter 1:5-7 for the progression of faith.");
    expect(r.scriptureRefs).toHaveLength(1);
    expect(r.scriptureRefs[0]).toMatchObject({ book: "2PE", chapter: 1, verseStart: 5, verseEnd: 7 });
    expect(r.scriptureKeys).toContain("2PE.1");
    expect(r.scriptureKeys).toContain("2PE.1.5");
    expect(r.scriptureKeys).toContain("2PE.1.6");
    expect(r.scriptureKeys).toContain("2PE.1.7");
    expect(r.scriptureRefStrings[0]).toBe("2 Peter 1:5-7");
  });

  test("Ps 23 — abbreviation, chapter-only", () => {
    const r = parseScripture("Ps 23 is the shepherd psalm.");
    expect(r.scriptureRefs[0]).toMatchObject({ book: "PSA", chapter: 23, verseStart: 0 });
    expect(r.scriptureKeys).toContain("PSA.23");
    expect(r.scriptureRefStrings[0]).toBe("Psalms 23");
  });

  test("1 Cor 13 — numbered book abbreviation", () => {
    const r = parseScripture("Read 1 Cor 13 for the love chapter.");
    expect(r.scriptureRefs[0]).toMatchObject({ book: "1CO", chapter: 13 });
    expect(r.scriptureKeys).toContain("1CO.13");
  });

  test("Matthew 5:33–37 — en-dash verse range", () => {
    const r = parseScripture("Matthew 5:33–37 teaches about oaths.");
    expect(r.scriptureRefs[0]).toMatchObject({ book: "MAT", chapter: 5, verseStart: 33, verseEnd: 37 });
    expect(r.scriptureKeys).toContain("MAT.5.33");
    expect(r.scriptureKeys).toContain("MAT.5.37");
  });

  test("Non-reference — no false positive for person name", () => {
    const r = parseScripture("John went to the store today.");
    expect(r.scriptureRefs).toHaveLength(0);
    expect(r.scriptureKeys).toHaveLength(0);
  });

  test("Deduplicates repeated refs", () => {
    const r = parseScripture("Romans 8:28 is key. Romans 8:28 again.");
    expect(r.scriptureRefs).toHaveLength(1);
  });

  test("Multiple refs in one text", () => {
    const r = parseScripture("James 1:2-4 and Philippians 4:13 both discuss strength.");
    expect(r.scriptureRefs).toHaveLength(2);
    expect(r.scriptureKeys).toContain("JAS.1");
    expect(r.scriptureKeys).toContain("PHP.4");
  });
});

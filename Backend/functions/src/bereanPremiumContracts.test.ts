import * as fs from "fs";
import * as path from "path";
import {
  REQUIRED_BEREAN_CALLABLES,
  detectSafetyLabels,
  parseReferences,
  routeBereanMode,
} from "./berean/controllers/premiumBereanCallables";

const root = path.resolve(__dirname, "..", "..", "..");

function read(relativePath: string): string {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

describe("Berean premium callable surface", () => {
  it("exports every production callable name from functions index", () => {
    const index = read("Backend/functions/src/index.ts");
    const controller = read("Backend/functions/src/berean/controllers/premiumBereanCallables.ts");

    expect(index).toContain('export * from "./berean/controllers/premiumBereanCallables"');
    for (const callable of REQUIRED_BEREAN_CALLABLES) {
      expect(controller + read("Backend/functions/src/bereanExtended.ts")).toContain(`export const ${callable}`);
    }
  });

  it("requires App Check on all premium callables", () => {
    const controller = read("Backend/functions/src/berean/controllers/premiumBereanCallables.ts");
    const extended = read("Backend/functions/src/bereanExtended.ts");
    for (const callable of REQUIRED_BEREAN_CALLABLES) {
      const source = controller.includes(`export const ${callable}`) ? controller : extended;
      const start = source.indexOf(`export const ${callable}`);
      const end = source.indexOf(");", start);
      expect(source.slice(start, end)).toContain("enforceAppCheck: true");
    }
  });
});

describe("Berean mode routing and safety classification", () => {
  it("routes exact Bible references to Scripture Study", () => {
    expect(routeBereanMode("Explain Romans 8:1-4 in context")).toBe("scripture_study");
  });

  it("routes decisions to Discernment", () => {
    expect(routeBereanMode("What should I do about this job decision?")).toBe("discernment");
  });

  it("routes prayer language to Prayer Companion", () => {
    expect(routeBereanMode("Help me pray through grief")).toBe("prayer_companion");
  });

  it("routes media/transcript requests to Media Insight", () => {
    expect(routeBereanMode("Summarize this sermon transcript")).toBe("media_insight");
  });

  it("detects Christian-specific safety labels", () => {
    expect(detectSafetyLabels("God told me you must submit without question")).toEqual(
      expect.arrayContaining(["spiritual_manipulation", "false_certainty"])
    );
  });
});

describe("Berean scripture retrieval contract", () => {
  it("parses references without fabricating Bible text", () => {
    const refs = parseReferences("Romans 8:1-2 and John 3:16", "KJV");
    expect(refs).toHaveLength(2);
    expect(refs[0]).toMatchObject({
      book: "Romans",
      chapter: 8,
      verseStart: 1,
      verseEnd: 2,
      translation: "KJV",
      text: null,
      contextBefore: null,
      contextAfter: null,
      source: "reference_parser",
    });
  });
});

describe("Berean Firestore privacy rules", () => {
  it("protects private Berean collections and blocks trusted client safety writes", () => {
    const rules = read("AMENAPP/firestore.deploy.rules");
    expect(rules).toContain("match /users/{userId}/bereanInsights/{insightId}");
    expect(rules).toContain("match /users/{userId}/prayerEntries/{entryId}");
    expect(rules).toContain("match /users/{userId}/discernmentResults/{resultId}");
    expect(rules).toContain("match /users/{userId}/walkWithChristPath/{pathItemId}");
    expect(rules).toContain("!request.resource.data.keys().hasAny(['serverSafetyLabels', 'trustedSafetyLabels'])");
    expect(rules).toContain("match /scriptureReferences/{referenceId}");
    expect(rules).toContain("allow create, update, delete: if false;");
  });

  it("keeps prayer entries private by server contract", () => {
    const controller = read("Backend/functions/src/berean/controllers/premiumBereanCallables.ts");
    expect(controller).toContain("privateByDefault: true");
    expect(controller).toContain('privacyLevel: "private"');
  });
});

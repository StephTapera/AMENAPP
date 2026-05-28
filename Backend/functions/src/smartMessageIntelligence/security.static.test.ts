import fs from "fs";
import path from "path";

const routerPath = path.join(__dirname, "smartMessageRouter.ts");
const routerSource = fs.readFileSync(routerPath, "utf8");
const monitoringPath = path.join(__dirname, "monitoring.ts");
const monitoringSource = fs.readFileSync(monitoringPath, "utf8");

describe("smart message callable security posture", () => {
  const callables = [
    "analyzeSmartMessage",
    "detectScriptureReferences",
    "detectSmartDateEvents",
    "detectPrayerRequest",
    "summarizeDiscussion",
    "getContextualBereanActions",
    "extractDiscussionTopics",
    "semanticSearchAmenSpace",
    "startSmartStudyMode",
    "transcribeVoiceMessage",
    "buildKnowledgeGraphMemory",
    "backfillSmartMessageVectorIndex",
    "getSmartMessageVectorIndexStatus",
  ];

  it("exports every required callable", () => {
    for (const callable of callables) {
      expect(routerSource).toContain(`export const ${callable}`);
    }
  });

  it("exports scheduled vector backfill without requiring client data", () => {
    expect(routerSource).toContain("export const scheduledSmartMessageVectorBackfill");
    expect(routerSource).toContain("smart_message_vector_scheduled_backfill_completed");
  });

  it("requires App Check and authentication helpers", () => {
    expect(routerSource).toContain("enforceAppCheck: true");
    expect(routerSource.match(/requireAuthAndAppCheck/g)?.length ?? 0).toBeGreaterThanOrEqual(callables.length);
  });

  it("validates membership for space/thread operations", () => {
    expect(routerSource.match(/requireSpaceMember/g)?.length ?? 0).toBeGreaterThanOrEqual(9);
  });

  it("uses shared rate limiting", () => {
    expect(routerSource.match(/enforceRateLimit/g)?.length ?? 0).toBeGreaterThanOrEqual(callables.length);
  });

  it("does not expose hidden personal memory in semantic search", () => {
    expect(routerSource).not.toContain("smartMessageMemory");
    expect(routerSource).toContain("semanticSearchAmenSpace");
  });

  it("records rollout metrics without raw message or prayer content", () => {
    expect(routerSource).toContain("recordSmartMessageMetric");
    expect(monitoringSource).toContain("/text|body|transcript|summary|prayer/i");
  });
});

import { detectScriptures } from "./scriptureDetection";
import { detectDateEvents } from "./dateEventDetection";
import { detectPrayerRequests } from "./prayerDetection";
import { extractTopics } from "./topicExtraction";
import { buildExtractiveDiscussionInsight } from "./discussionSummary";
import { contextualBereanActions } from "./contextualBereanActions";
import { transcriptEntity } from "./voiceIntelligence";
import { vectorSearchEnabled } from "./semanticSearch";

describe("smartMessageIntelligence detectors", () => {
  it("detects multiple scripture references", () => {
    const entities = detectScriptures("Read John 3:16 and Romans 8:28 before group.");
    expect(entities.map((entity) => entity.normalizedValue)).toEqual(["John 3:16", "Romans 8:28"]);
  });

  it("detects numbered scripture books", () => {
    const entities = detectScriptures("Remember 1 John 4:8 tonight.");
    expect(entities[0].normalizedValue).toBe("1 John 4:8");
  });

  it("detects event language without creating an event", () => {
    const entities = detectDateEvents("Men's Bible Study Friday at 7pm in Building C");
    expect(entities.some((entity) => entity.type === "dateTime")).toBe(true);
  });

  it("classifies prayer requests", () => {
    const entities = detectPrayerRequests("Please pray for my surgery tomorrow.");
    expect(entities[0].normalizedValue).toBe("health");
  });

  it("extracts spiritual topics", () => {
    const entities = extractTopics("We talked about grace, anxiety, and discipleship.");
    expect(entities.map((entity) => entity.normalizedValue)).toEqual(expect.arrayContaining(["grace", "anxiety", "discipleship"]));
  });

  it("builds extractive summaries without fake AI claims", () => {
    const insight = buildExtractiveDiscussionInsight([
      "Paul encouraged us to read Romans 8:28 this week.",
      "Please pray for my family as we make a decision.",
      "What does forgiveness look like here?",
    ]);
    expect(insight.scriptures).toContain("Romans 8:28");
    expect(insight.prayerRequests.length).toBeGreaterThan(0);
    expect(insight.unresolvedQuestions.length).toBe(1);
  });

  it("returns contextual Berean actions", () => {
    const actions = contextualBereanActions("I am struggling with anxiety", "message", "m1");
    expect(actions.map((action) => action.title)).toEqual(expect.arrayContaining(["Explain", "Find Scripture", "Pray Through This"]));
  });

  it("refuses voice intelligence without provider transcript", () => {
    expect(() => transcriptEntity("", "m1")).toThrow();
  });

  it("enables Firebase-native vector search behind the explicit flag", () => {
    const previousEnabled = process.env.SMART_MESSAGE_VECTOR_ENABLED;
    const previousProvider = process.env.SMART_MESSAGE_VECTOR_PROVIDER;
    const previousURL = process.env.SMART_MESSAGE_VECTOR_API_URL;
    const previousKey = process.env.SMART_MESSAGE_VECTOR_API_KEY;
    delete process.env.SMART_MESSAGE_VECTOR_ENABLED;
    delete process.env.SMART_MESSAGE_VECTOR_PROVIDER;
    delete process.env.SMART_MESSAGE_VECTOR_API_URL;
    delete process.env.SMART_MESSAGE_VECTOR_API_KEY;
    expect(vectorSearchEnabled()).toBe(false);
    process.env.SMART_MESSAGE_VECTOR_ENABLED = "true";
    process.env.SMART_MESSAGE_VECTOR_PROVIDER = "firestore";
    expect(vectorSearchEnabled()).toBe(true);
    process.env.SMART_MESSAGE_VECTOR_PROVIDER = "external";
    expect(vectorSearchEnabled()).toBe(false);
    process.env.SMART_MESSAGE_VECTOR_API_URL = "https://vectors.example.com";
    process.env.SMART_MESSAGE_VECTOR_API_KEY = "test-key";
    expect(vectorSearchEnabled()).toBe(true);
    if (previousEnabled === undefined) delete process.env.SMART_MESSAGE_VECTOR_ENABLED;
    else process.env.SMART_MESSAGE_VECTOR_ENABLED = previousEnabled;
    if (previousProvider === undefined) delete process.env.SMART_MESSAGE_VECTOR_PROVIDER;
    else process.env.SMART_MESSAGE_VECTOR_PROVIDER = previousProvider;
    if (previousURL === undefined) delete process.env.SMART_MESSAGE_VECTOR_API_URL;
    else process.env.SMART_MESSAGE_VECTOR_API_URL = previousURL;
    if (previousKey === undefined) delete process.env.SMART_MESSAGE_VECTOR_API_KEY;
    else process.env.SMART_MESSAGE_VECTOR_API_KEY = previousKey;
  });
});

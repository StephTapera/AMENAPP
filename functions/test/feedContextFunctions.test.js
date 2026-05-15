const test = require("node:test");
const assert = require("node:assert/strict");

const {
  DEFAULT_MINIMUMS,
  buildContextPayload,
  buildRankedFeedResponse,
  computeContextScore,
  validateFeedbackAction,
} = require("../feedContextFunctions");

function makeRequest(overrides = {}) {
  return {
    posts: [],
    interests: {
      engagedTopics: {},
      engagedAuthors: {},
      preferredCategories: {},
      onboardingGoals: [],
    },
    followingIds: [],
    sessionCardsServed: 0,
    sessionCap: 25,
    ...overrides,
  };
}

function makeUserContext(overrides = {}) {
  return {
    churchId: undefined,
    city: undefined,
    communityId: undefined,
    interests: [],
    scriptureTopics: [],
    prayerInterests: [],
    ...overrides,
  };
}

function makePost(overrides = {}) {
  return {
    id: "post-1",
    authorId: "author-1",
    content: "Romans 8 and patient faith in hard seasons.",
    category: "scripture",
    topicTag: "Faith",
    amenCount: 42,
    commentCount: 9,
    createdAt: Math.floor(Date.now() / 1000) - 1800,
    verseRef: "Romans 8:28",
    churchId: null,
    communityId: null,
    linkedPrayerRequestId: null,
    lowTrustAuthor: false,
    flaggedForReview: false,
    removed: false,
    ...overrides,
  };
}

test("computeContextScore produces a bounded score", () => {
  const score = computeContextScore(makePost(), makeRequest(), makeUserContext());
  assert.ok(score.contextScore >= 0);
  assert.ok(score.contextScore <= 1);
});

test("buildContextPayload returns scripture metadata for strong scripture posts", () => {
  const request = makeRequest({
    followingIds: ["author-1"],
    interests: {
      engagedTopics: {faith: 1.8},
      engagedAuthors: {"author-1": 4},
      preferredCategories: {scripture: 1},
      onboardingGoals: ["faith"],
    },
  });
  const userContext = makeUserContext({
    scriptureTopics: ["faith"],
    interests: ["Romans"],
  });

  const payload = buildContextPayload(makePost(), request, userContext);
  assert.ok(payload);
  assert.equal(payload.contextType, "scriptureFocus");
  assert.equal(payload.contextDestinationType, "scriptureCluster");
  assert.equal(payload.contextTitle, "Romans 8:28");
});

test("sensitive unsupported context types are suppressed", () => {
  const request = makeRequest({
    interests: {
      engagedTopics: {politics: 2},
      engagedAuthors: {},
      preferredCategories: {discussion: 1},
      onboardingGoals: ["politics"],
    },
  });
  const userContext = makeUserContext({interests: ["politics"]});
  const payload = buildContextPayload(makePost({
    id: "post-sensitive",
    content: "Politics and war are dominating this discussion.",
    category: "discussion",
    topicTag: "Politics",
    verseRef: null,
    amenCount: 18,
    commentCount: 16,
  }), request, userContext);

  assert.equal(payload, null);
});

test("malformed posts do not build a payload", () => {
  const payload = buildContextPayload(makePost({
    topicTag: "  ",
    category: " ",
    verseRef: null,
    content: "ok",
  }), makeRequest(), makeUserContext());
  assert.equal(payload, null);
});

test("ranked feed response includes context metadata alongside ranked ids", () => {
  const request = makeRequest({
    posts: [
      makePost({id: "top", amenCount: 50, commentCount: 12}),
      makePost({id: "next", authorId: "author-2", amenCount: 6, commentCount: 1, verseRef: null, content: "General reflection"}),
    ],
  });
  const response = buildRankedFeedResponse(request, makeUserContext({scriptureTopics: ["faith"]}));

  assert.deepEqual(response.rankedIds, ["top", "next"]);
  assert.ok(response.contextsByPostId.top);
  assert.equal(response.contextsByPostId.top.contextTitle, "Romans 8:28");
});

test("feedback validation only permits supported actions", () => {
  assert.equal(validateFeedbackAction("tap"), true);
  assert.equal(validateFeedbackAction("report_issue"), true);
  assert.equal(validateFeedbackAction("delete_everything"), false);
});

test("default minimums remain stable", () => {
  assert.deepEqual(DEFAULT_MINIMUMS, {
    normal: 0.72,
    sensitive: 0.86,
    livePrayer: 0.80,
    bereanInsight: 0.78,
  });
});

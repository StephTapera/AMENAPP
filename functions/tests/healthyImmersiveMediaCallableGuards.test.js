const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp({projectId: "demo-amen-media-callables"});
}

const media = require("../healthyImmersiveMedia");

test("healthy media callables use App Check enforcing callable options", () => {
  assert.equal(media._internal.callableOptions.enforceAppCheck, true);
  assert.equal(media._internal.callableOptions.region, "us-central1");
  assert.equal(media._internal.callableOptions.timeoutSeconds, 60);
});

test("healthy media callable exports are callable v2 endpoints", () => {
  for (const name of media._internal.mediaCallableNames) {
    assert.equal(typeof media[name], "function", `${name} should be exported`);
    assert.equal(media[name].__endpoint?.platform, "gcfv2", `${name} should be a v2 function`);
    assert.deepEqual(media[name].__endpoint?.region, ["us-central1"]);
    assert.ok(media[name].__endpoint?.callableTrigger, `${name} should be callable`);
  }
});

test("healthy media auth guard rejects unauthenticated requests", () => {
  assert.throws(
      () => media._internal.requireAuth({data: {}}),
      (error) => error.code === "unauthenticated",
  );
});

test("healthy media auth guard returns authenticated uid", () => {
  assert.equal(media._internal.requireAuth({auth: {uid: "user-a"}, data: {}}), "user-a");
});

test("healthy media callables fail closed on risky client-controlled system fields", () => {
  const forbidden = [
    "moderationStatus",
    "rankingScore",
    "trustScore",
    "syntheticRiskScore",
    "provenanceConfidence",
    "generatedMetadataApproved",
    "creatorApprovedAiMetadata",
    "systemSafetyLabels",
    "queueRankingSignals",
    "recommendationReasonInternal",
    "safety",
    "moderationVersion",
    "reviewedAt",
    "reviewedBy",
  ];

  for (const field of forbidden) {
    assert.throws(
        () => media._internal.rejectForbiddenClientFields({[field]: "spoof"}, "test"),
        (error) => error.code === "invalid-argument" && error.message.includes(field),
        `${field} should be rejected`,
    );
  }
});

test("healthy media schema helpers reject missing strings, invalid types, and oversized strings", () => {
  assert.throws(
      () => media._internal.requiredString({}, "postId"),
      (error) => error.code === "invalid-argument",
  );
  assert.throws(
      () => media._internal.requiredString({postId: 44}, "postId"),
      (error) => error.code === "invalid-argument",
  );
  assert.throws(
      () => media._internal.requiredString({postId: "x".repeat(205)}, "postId", 200),
      (error) => error.code === "invalid-argument",
  );
  assert.equal(media._internal.requiredString({postId: " post-1 "}, "postId"), "post-1");
});

test("healthy media bounded number helper rejects out-of-range and non-numeric input", () => {
  assert.throws(
      () => media._internal.boundedNumber({limit: "many"}, "limit", 1, 12, 3),
      (error) => error.code === "invalid-argument",
  );
  assert.throws(
      () => media._internal.boundedNumber({limit: 99}, "limit", 1, 12, 3),
      (error) => error.code === "invalid-argument",
  );
  assert.equal(media._internal.boundedNumber({}, "limit", 1, 12, 3), 3);
  assert.equal(media._internal.boundedNumber({limit: "6"}, "limit", 1, 12, 3), 6);
});

test("healthy media finite-session contracts expose only bounded session types and queues", () => {
  assert.equal(media._internal.allowedSessionTypes.has("fiveMinuteSelah"), true);
  assert.equal(media._internal.allowedSessionTypes.has("infiniteAutoplayFeed"), false);
  assert.equal(media._internal.allowedQueueTypes.has("prayerQueue"), true);
  assert.equal(media._internal.allowedQueueTypes.has("doomScrollLater"), false);
});

test("healthy media analytics allow healthy events and reject addictive/feed-loop events", () => {
  assert.equal(media._internal.healthyEvents.has("media_reflected"), true);
  assert.equal(media._internal.healthyEvents.has("media_take_break"), true);
  assert.equal(media._internal.healthyEvents.has("autoplay_next_started"), false);
  assert.equal(media._internal.healthyEvents.has("infinite_feed_scrolled"), false);
});

test("healthy media callable exports include approval, canonical upload, session, and reporting gates", () => {
  const required = [
    "createMediaUploadSession",
    "finalizeMediaUpload",
    "generateMediaDraftMetadata",
    "approveMediaMetadata",
    "rejectMediaMetadata",
    "createMediaSession",
    "getNextSessionItems",
    "completeMediaSession",
    "reportMedia",
    "createTimestampedComment",
  ];

  for (const name of required) {
    assert.equal(media._internal.mediaCallableNames.includes(name), true, `${name} should be exported`);
  }
});

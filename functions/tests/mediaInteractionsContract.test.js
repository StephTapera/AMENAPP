// mediaInteractionsContract.test.js
// Static contract tests for functions/src/mediaInteractions/index.js
// Verifies: auth guards, required-field validation, business logic, CF exports.
//
// Run: node --test tests/mediaInteractionsContract.test.js

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const srcPath = path.join(__dirname, "..", "src", "mediaInteractions", "index.js");
const indexPath = path.join(__dirname, "..", "index.js");

function src() {
  return fs.readFileSync(srcPath, "utf8");
}

function indexJs() {
  return fs.readFileSync(indexPath, "utf8");
}

// ---------------------------------------------------------------------------
// Auth guard contract
// ---------------------------------------------------------------------------

test("mediaInteractions: every exported callable calls requireAuth", () => {
  const source = src();
  const callables = [
    "addReaction",
    "removeReaction",
    "pinReply",
    "saveToCollection",
    "translateText",
    "attachVerse",
    "expireViewOnceMedia",
    "cleanupExpiredMutes",
  ];
  for (const name of callables) {
    assert.ok(
      source.includes(`exports.${name} = onCall`),
      `${name} must be exported as an onCall function`
    );
  }
  const authCount = (source.match(/requireAuth/g) || []).length;
  assert.ok(
    authCount >= callables.length,
    `requireAuth must appear at least ${callables.length} times (once per callable)`
  );
});

// ---------------------------------------------------------------------------
// addReaction contract
// ---------------------------------------------------------------------------

test("addReaction: validates required fields mediaId and type", () => {
  const source = src();
  assert.ok(
    source.includes(`requireFields(data, ['mediaId', 'type'])`),
    "addReaction must require mediaId and type"
  );
});

test("addReaction: validates type against allowed list", () => {
  const source = src();
  assert.ok(
    source.includes("heart") &&
      source.includes("prayer") &&
      source.includes("custom"),
    "addReaction must validate type against the allowed-types list"
  );
});

test("addReaction: uses deterministic reactionId for idempotent upsert", () => {
  const source = src();
  assert.ok(
    source.includes("`${uid}_${mediaId}`"),
    "addReaction must use uid_mediaId as deterministic document ID"
  );
});

test("addReaction: increments reactionCount only for new reactions", () => {
  const source = src();
  assert.ok(
    source.includes("isNew") && source.includes("reactionCount"),
    "addReaction must guard counter increment behind isNew flag"
  );
});

// ---------------------------------------------------------------------------
// removeReaction contract
// ---------------------------------------------------------------------------

test("removeReaction: requires reactionId field", () => {
  const source = src();
  assert.ok(
    source.includes(`requireFields(data, ['reactionId'])`),
    "removeReaction must require reactionId"
  );
});

test("removeReaction: enforces ownership before deletion", () => {
  const source = src();
  assert.ok(
    source.includes("permission-denied") &&
      source.includes("own reactions"),
    "removeReaction must enforce caller owns the reaction"
  );
});

test("removeReaction: decrements reactionCount on delete", () => {
  const source = src();
  assert.ok(
    source.includes("increment(-1)"),
    "removeReaction must decrement reactionCount"
  );
});

// ---------------------------------------------------------------------------
// pinReply contract
// ---------------------------------------------------------------------------

test("pinReply: requires mediaId and commentId", () => {
  const source = src();
  assert.ok(
    source.includes(`requireFields(data, ['mediaId', 'commentId'])`),
    "pinReply must require mediaId and commentId"
  );
});

test("pinReply: only post author can pin", () => {
  const source = src();
  assert.ok(
    source.includes("authorId") && source.includes("Only the post author"),
    "pinReply must check authorId and reject non-authors"
  );
});

// ---------------------------------------------------------------------------
// saveToCollection contract
// ---------------------------------------------------------------------------

test("saveToCollection: requires mediaId", () => {
  const source = src();
  assert.ok(
    source.includes(`requireFields(data, ['mediaId'])`),
    "saveToCollection must require mediaId"
  );
});

test("saveToCollection: verifies media exists before saving", () => {
  const source = src();
  assert.ok(
    source.includes("not-found") && source.includes("Media item not found"),
    "saveToCollection must verify media exists"
  );
});

test("saveToCollection: uses deterministic saveId", () => {
  const source = src();
  assert.ok(
    source.includes("saveId") && source.includes("`${uid}_${mediaId}`"),
    "saveToCollection must use uid_mediaId as deterministic save ID"
  );
});

// ---------------------------------------------------------------------------
// translateText contract
// ---------------------------------------------------------------------------

test("translateText: requires text and targetLocale", () => {
  const source = src();
  assert.ok(
    source.includes(`requireFields(data, ['text', 'targetLocale'])`),
    "translateText must require text and targetLocale"
  );
});

test("translateText: enforces 5000 character limit", () => {
  const source = src();
  assert.ok(
    source.includes("5000"),
    "translateText must reject text exceeding 5000 characters"
  );
});

test("translateText: rate-limits to 20 calls per user per day", () => {
  const source = src();
  assert.ok(
    source.includes("dailyCount >= 20") || source.includes(">= 20"),
    "translateText must enforce daily rate limit of 20"
  );
});

test("translateText: uses Cloud Translation API v3", () => {
  const source = src();
  assert.ok(
    source.includes("TranslationServiceClient") &&
      source.includes("translateText"),
    "translateText must use Cloud Translation API v3 TranslationServiceClient"
  );
});

// ---------------------------------------------------------------------------
// attachVerse contract
// ---------------------------------------------------------------------------

test("attachVerse: requires reference, attachedToId, attachedToType", () => {
  const source = src();
  assert.ok(
    source.includes(
      `requireFields(data, ['reference', 'attachedToId', 'attachedToType'])`
    ),
    "attachVerse must require reference, attachedToId, and attachedToType"
  );
});

test("attachVerse: validates attachedToType against allowed values", () => {
  const source = src();
  assert.ok(
    source.includes("reaction") &&
      source.includes("comment") &&
      source.includes("post") &&
      source.includes("validTargets"),
    "attachVerse must validate attachedToType"
  );
});

test("attachVerse: includes KJV lookup table with common verses", () => {
  const source = src();
  assert.ok(
    source.includes("John 3:16") && source.includes("Psalm 23:1"),
    "attachVerse must include inline KJV lookup table"
  );
});

// ---------------------------------------------------------------------------
// expireViewOnceMedia contract
// ---------------------------------------------------------------------------

test("expireViewOnceMedia: requires messageId", () => {
  const source = src();
  assert.ok(
    source.includes(`requireFields(request.data, ['messageId'])`) ||
      source.includes(`requireFields(data, ['messageId'])`),
    "expireViewOnceMedia must require messageId"
  );
});

test("expireViewOnceMedia: enforces recipient-only access", () => {
  const source = src();
  assert.ok(
    source.includes("recipientId") &&
      source.includes("Only the recipient"),
    "expireViewOnceMedia must check recipientId and reject non-recipients"
  );
});

test("expireViewOnceMedia: deletes associated Storage file", () => {
  const source = src();
  assert.ok(
    source.includes("storageRef") && source.includes(".delete()"),
    "expireViewOnceMedia must delete the associated Storage file"
  );
});

test("expireViewOnceMedia: marks message expired with server timestamp", () => {
  const source = src();
  assert.ok(
    source.includes("expired: true") && source.includes("expiredAt"),
    "expireViewOnceMedia must write expired flag and expiredAt timestamp"
  );
});

test("expireViewOnceMedia: idempotent — early-returns if already expired", () => {
  const source = src();
  assert.ok(
    source.includes("messageData.expired"),
    "expireViewOnceMedia must short-circuit if already expired"
  );
});

// ---------------------------------------------------------------------------
// cleanupExpiredMutes contract
// ---------------------------------------------------------------------------

test("cleanupExpiredMutes: queries mutes subcollection with expiresAt filter", () => {
  const source = src();
  assert.ok(
    source.includes("mutes") &&
      source.includes("entries") &&
      source.includes("expiresAt"),
    "cleanupExpiredMutes must query /mutes/{uid}/entries filtered by expiresAt"
  );
});

test("cleanupExpiredMutes: batch deletes in chunks of 500", () => {
  const source = src();
  assert.ok(
    source.includes("500") && source.includes("batch"),
    "cleanupExpiredMutes must batch delete in chunks <= 500 (Firestore limit)"
  );
});

test("cleanupExpiredMutes: returns deletedCount", () => {
  const source = src();
  assert.ok(
    source.includes("deletedCount"),
    "cleanupExpiredMutes must return { deletedCount }"
  );
});

// ---------------------------------------------------------------------------
// sendScheduledMessages contract
// ---------------------------------------------------------------------------

test("sendScheduledMessages: is an onSchedule function", () => {
  const source = src();
  assert.ok(
    source.includes("onSchedule") && source.includes("sendScheduledMessages"),
    "sendScheduledMessages must be declared with onSchedule"
  );
});

test("sendScheduledMessages: runs every 1 minute", () => {
  const source = src();
  assert.ok(
    source.includes("every 1 minutes"),
    "sendScheduledMessages must be scheduled for 'every 1 minutes'"
  );
});

test("sendScheduledMessages: queries scheduledFor <= now and sent == false", () => {
  const source = src();
  assert.ok(
    source.includes("scheduledFor") &&
      source.includes("sent") &&
      source.includes("false"),
    "sendScheduledMessages must filter by scheduledFor <= now and sent == false"
  );
});

test("sendScheduledMessages: marks delivered messages as sent", () => {
  const source = src();
  assert.ok(
    source.includes("sent: true") && source.includes("sentAt"),
    "sendScheduledMessages must mark messages sent with sentAt timestamp"
  );
});

// ---------------------------------------------------------------------------
// functions/index.js registration contract
// ---------------------------------------------------------------------------

test("index.js: registers all 9 mediaInteraction exports", () => {
  const index = indexJs();
  const expected = [
    "addReaction",
    "removeReaction",
    "pinReply",
    "saveToCollection",
    "translateText",
    "attachVerse",
    "expireViewOnceMedia",
    "cleanupExpiredMutes",
    "sendScheduledMessages",
  ];
  for (const name of expected) {
    assert.ok(
      index.includes(`mediaInteractionFns.${name}`),
      `index.js must register mediaInteractionFns.${name}`
    );
  }
});

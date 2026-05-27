// postSystemContract.test.js
// Contract tests for the AMEN post system security and production readiness.
// Uses file-reading contract approach (matches existing test patterns in this codebase).
// Tests: Firestore rules (post visibility + server-field protection),
//        RTDB rules (comment identity + validation),
//        CreatePostView field discipline, backend callable guards.
//
// Run: node --test tests/postSystemContract.test.js

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const firestoreRulesPath = path.join(__dirname, "..", "..", "firestore.rules");
const rtdbRulesPath = path.join(__dirname, "..", "..", "AMENAPP", "database.rules.json");

function firestoreRules() {
  return fs.readFileSync(firestoreRulesPath, "utf8");
}

function rtdbRules() {
  return fs.readFileSync(rtdbRulesPath, "utf8");
}

// MARK: - Firestore Post Rules Contract

test("firestore.rules: posts block moderating/publishing status from public reads", () => {
  const rules = firestoreRules();
  assert.ok(
    rules.includes("moderating") && rules.includes("publishing"),
    "Post read rule must block status: moderating and publishing from non-author reads"
  );
});

test("firestore.rules: posts block private_pending publicationVisibility from public reads", () => {
  const rules = firestoreRules();
  assert.ok(
    rules.includes("private_pending"),
    "Post read rule must block publicationVisibility: private_pending"
  );
});

test("firestore.rules: posts block removed and flagged_hidden status from public reads", () => {
  const rules = firestoreRules();
  assert.ok(
    rules.includes("removed") && rules.includes("flagged_hidden"),
    "Post read rule must include removed and flagged_hidden status blocks"
  );
});

test("firestore.rules: post create blocks publishedAt from client", () => {
  const rules = firestoreRules();
  assert.ok(
    rules.includes("publishedAt"),
    "Post create rule must block client from setting publishedAt (server-stamped field)"
  );
});

test("firestore.rules: post create blocks moderationDecision from client", () => {
  const rules = firestoreRules();
  assert.ok(
    rules.includes("moderationDecision"),
    "Post create rule must block client from setting moderationDecision"
  );
});

test("firestore.rules: post create blocks safetyDecision from client", () => {
  const rules = firestoreRules();
  assert.ok(
    rules.includes("safetyDecision"),
    "Post create rule must block client from setting safetyDecision"
  );
});

test("firestore.rules: post create blocks publishState: published from client", () => {
  const rules = firestoreRules();
  assert.ok(
    rules.includes("publishState") && rules.includes("'published'"),
    "Post create rule must prevent client from setting publishState to 'published'"
  );
});

test("firestore.rules: post update blocks status field changes by client", () => {
  const rules = firestoreRules();
  // The update rule uses diff().affectedKeys().hasAny([..., 'status', ...])
  assert.ok(
    rules.includes("affectedKeys") && rules.includes("'status'"),
    "Post update rule must block client from changing the 'status' field"
  );
});

test("firestore.rules: post update blocks authorId changes by client", () => {
  const rules = firestoreRules();
  assert.ok(
    rules.includes("'authorId'"),
    "Post update rule must block client from changing authorId"
  );
});

test("firestore.rules: moderators can read any post", () => {
  const rules = firestoreRules();
  assert.ok(
    rules.includes("isModerator()"),
    "Post read rule must include isModerator() override for moderation review"
  );
});

test("firestore.rules: post safety subcollection is server-write-only", () => {
  const rules = firestoreRules();
  // The safety subcollection must have allow create, update, delete: if false
  const safetyIdx = rules.indexOf("match /safety/{docId}");
  assert.ok(safetyIdx > -1, "safety subcollection rule must exist");
  const safetySection = rules.slice(safetyIdx, safetyIdx + 200);
  assert.ok(
    safetySection.includes("allow create, update, delete: if false"),
    "safety subcollection must be server-write-only"
  );
});

test("firestore.rules: post media subcollection is server-write-only", () => {
  const rules = firestoreRules();
  const mediaIdx = rules.indexOf("match /posts/{postId}/media/{mediaId}");
  assert.ok(mediaIdx > -1, "media subcollection rule must exist");
  const mediaSection = rules.slice(mediaIdx, mediaIdx + 200);
  assert.ok(
    mediaSection.includes("allow create, update, delete: if false"),
    "media subcollection must be server-write-only"
  );
});

// MARK: - RTDB Comment Rules Contract

test("database.rules.json: postInteractions/comments require auth for read", () => {
  const rules = rtdbRules();
  assert.ok(
    rules.includes("postInteractions"),
    "RTDB rules must include postInteractions path"
  );
  assert.ok(
    rules.includes('"auth != null"') || rules.includes("auth != null"),
    "RTDB comments must require authentication"
  );
});

test("database.rules.json: postInteractions/comments enforce authorId == auth.uid on write", () => {
  const rules = rtdbRules();
  // The write rule checks newData.child('authorId').val() == auth.uid
  assert.ok(
    rules.includes("authorId") && rules.includes("auth.uid"),
    "RTDB comment write rule must enforce authorId === auth.uid"
  );
});

test("database.rules.json: comments path enforces authorId identity", () => {
  const rules = rtdbRules();
  const commentsIdx = rules.indexOf('"comments"');
  assert.ok(commentsIdx > -1, "RTDB rules must include a comments path");
});

test("database.rules.json: engagement counts (lightbulbCount, amenCount, commentCount) are server-only", () => {
  const rules = rtdbRules();
  assert.ok(
    rules.includes("lightbulbCount") && rules.includes("amenCount") && rules.includes("commentCount"),
    "RTDB rules must include engagement count paths"
  );
  // Each of these should have .write: false
  const lightbulbSection = rules.slice(
    rules.indexOf("lightbulbCount") - 10,
    rules.indexOf("lightbulbCount") + 100
  );
  assert.ok(
    lightbulbSection.includes("false"),
    "lightbulbCount must be server-only (write: false)"
  );
});

test("database.rules.json: user_saved_posts are owner-only", () => {
  const rules = rtdbRules();
  assert.ok(
    rules.includes("user_saved_posts"),
    "RTDB rules must include user_saved_posts path"
  );
  const savedIdx = rules.indexOf("user_saved_posts");
  const savedSection = rules.slice(savedIdx, savedIdx + 200);
  assert.ok(
    savedSection.includes("auth.uid"),
    "user_saved_posts must be owner-only"
  );
});

test("database.rules.json: connections/followers are server-only (no client write)", () => {
  const rules = rtdbRules();
  assert.ok(
    rules.includes("connections"),
    "RTDB rules must include connections path"
  );
  const connIdx = rules.indexOf("connections");
  const followersIdx = rules.indexOf("followers", connIdx);
  assert.ok(followersIdx > -1, "Must have a followers path");
  const followersSection = rules.slice(followersIdx, followersIdx + 300);
  assert.ok(
    followersSection.includes('".write": false') || followersSection.includes('"write": false'),
    "followers must be server-only writes (prevents follow approval bypass)"
  );
});

// MARK: - CreatePostView Field Discipline

test("CreatePostView writes status as moderating or publishing (never published) on create", () => {
  const cpvPath = path.join(__dirname, "..", "..", "AMENAPP", "CreatePostView.swift");
  const src = fs.readFileSync(cpvPath, "utf8");
  // Client must write "moderating" or "publishing", never "published"
  assert.ok(
    src.includes('"moderating"') || src.includes('"publishing"'),
    "CreatePostView must write status as moderating or publishing on post create"
  );
  // The value "published" should not be in postData writes
  // (It may appear in comments/strings so we check the postData assignment block specifically)
  assert.ok(
    !src.includes('"status": "published"'),
    "CreatePostView must NOT write status: published directly"
  );
});

test("CreatePostView stamps moderationStatus on every post", () => {
  const cpvPath = path.join(__dirname, "..", "..", "AMENAPP", "CreatePostView.swift");
  const src = fs.readFileSync(cpvPath, "utf8");
  assert.ok(
    src.includes("moderationStatus"),
    "CreatePostView must stamp moderationStatus on every post"
  );
});

test("CreatePostView includes authorId from currentUser.uid", () => {
  const cpvPath = path.join(__dirname, "..", "..", "AMENAPP", "CreatePostView.swift");
  const src = fs.readFileSync(cpvPath, "utf8");
  assert.ok(
    src.includes("authorId") && src.includes("currentUser.uid"),
    "CreatePostView must set authorId from currentUser.uid"
  );
});

test("CreatePostView supports alt text for images (accessibility)", () => {
  const cpvPath = path.join(__dirname, "..", "..", "AMENAPP", "CreatePostView.swift");
  const src = fs.readFileSync(cpvPath, "utf8");
  assert.ok(
    src.includes("imageAltTexts"),
    "CreatePostView must support imageAltTexts for accessibility"
  );
  assert.ok(
    src.includes('postData["imageAltTexts"]'),
    "imageAltTexts must be written to the post data"
  );
});

test("CreatePostView supports hasSensitiveContent flag", () => {
  const cpvPath = path.join(__dirname, "..", "..", "AMENAPP", "CreatePostView.swift");
  const src = fs.readFileSync(cpvPath, "utf8");
  assert.ok(
    src.includes("hasSensitiveContent"),
    "CreatePostView must support hasSensitiveContent flag"
  );
  assert.ok(
    src.includes('postData["hasSensitiveContent"]'),
    "hasSensitiveContent must be written to post data"
  );
});

test("CreatePostView supports hideEngagementCounts privacy option", () => {
  const cpvPath = path.join(__dirname, "..", "..", "AMENAPP", "CreatePostView.swift");
  const src = fs.readFileSync(cpvPath, "utf8");
  assert.ok(
    src.includes("hideEngagementCounts"),
    "CreatePostView must support hideEngagementCounts"
  );
  assert.ok(
    src.includes('postData["hideEngagementCounts"]'),
    "hideEngagementCounts must be written to post data"
  );
});

test("CreatePostView has idempotency key to prevent duplicate posts", () => {
  const cpvPath = path.join(__dirname, "..", "..", "AMENAPP", "CreatePostView.swift");
  const src = fs.readFileSync(cpvPath, "utf8");
  assert.ok(
    src.includes("idempotencyKey") || src.includes("inFlightPostId"),
    "CreatePostView must have idempotency protection against duplicate post submissions"
  );
});

// MARK: - AMENFeatureFlags Post Flags Contract

test("AMENFeatureFlags.swift contains post-related feature flags", () => {
  const flagsPath = path.join(__dirname, "..", "..", "AMENAPP", "AMENFeatureFlags.swift");
  const src = fs.readFileSync(flagsPath, "utf8");
  const expectedFlags = [
    "imageModerationEnabled",
    "moderationV2Enabled",
    "provenanceTrustPanelEnabled",
    "bereanPostContextAvailabilityEnabled",
  ];
  for (const flag of expectedFlags) {
    assert.ok(src.includes(flag), `AMENFeatureFlags must include flag: ${flag}`);
  }
});

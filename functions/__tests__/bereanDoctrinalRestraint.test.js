/**
 * bereanDoctrinalRestraint.test.js
 * Static tests for the BEREAN_DOCTRINAL_RESTRAINT constant in bereanFunctions.js.
 *
 * Run: node --test functions/__tests__/bereanDoctrinalRestraint.test.js
 *
 * These are STATIC CONTRACT TESTS — they verify that the instruction string is
 * present, contains the required neutrality directives, and does NOT contain
 * any language that would encode a doctrinal stance.
 *
 * Runtime LLM behavior (whether the model actually complies) cannot be
 * unit-tested; these tests guard against accidental removal or corruption of
 * the guard text during future refactors.
 *
 * See docs/governance/GOVERNANCE.md §5 for the full doctrinal restraint policy.
 */

"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const path = require("node:path");

// ── Import the real module ────────────────────────────────────────────────────
// We read the source file directly to extract the constant value, since it is
// not exported from bereanFunctions.js (it's an internal module constant).
// This approach is consistent with the project's contract-test strategy.

const fs = require("node:fs");
const srcPath = path.join(__dirname, "..", "bereanFunctions.js");
const srcText = fs.readFileSync(srcPath, "utf8");

// Extract the BEREAN_DOCTRINAL_RESTRAINT value from the source.
// Match the template literal assigned to the constant.
const constMatch = srcText.match(
  /const BEREAN_DOCTRINAL_RESTRAINT\s*=\s*`([\s\S]*?)`;/
);

const BEREAN_DOCTRINAL_RESTRAINT = constMatch ? constMatch[1] : null;

// ── Presence check ────────────────────────────────────────────────────────────

test("BEREAN_DOCTRINAL_RESTRAINT: constant exists in bereanFunctions.js", () => {
  assert.ok(
    constMatch !== null,
    "BEREAN_DOCTRINAL_RESTRAINT constant must be defined in bereanFunctions.js"
  );
  assert.ok(
    typeof BEREAN_DOCTRINAL_RESTRAINT === "string",
    "BEREAN_DOCTRINAL_RESTRAINT must be a string"
  );
  assert.ok(
    BEREAN_DOCTRINAL_RESTRAINT.length > 50,
    "BEREAN_DOCTRINAL_RESTRAINT must be a substantial instruction string (> 50 chars)"
  );
});

// ── Required neutrality directive ────────────────────────────────────────────

test("BEREAN_DOCTRINAL_RESTRAINT: contains DENOMINATIONAL NEUTRALITY header", () => {
  assert.ok(
    BEREAN_DOCTRINAL_RESTRAINT.includes("DENOMINATIONAL NEUTRALITY"),
    'Must contain "DENOMINATIONAL NEUTRALITY" directive header'
  );
});

test("BEREAN_DOCTRINAL_RESTRAINT: references different Christian traditions", () => {
  assert.ok(
    BEREAN_DOCTRINAL_RESTRAINT.includes("different Christian traditions"),
    'Must reference "different Christian traditions" to enforce multi-tradition framing'
  );
});

// ── Contested topic coverage ──────────────────────────────────────────────────

test("BEREAN_DOCTRINAL_RESTRAINT: mentions Calvinist/Arminian debate", () => {
  assert.ok(
    BEREAN_DOCTRINAL_RESTRAINT.toLowerCase().includes("calvinist") ||
    BEREAN_DOCTRINAL_RESTRAINT.toLowerCase().includes("arminian"),
    'Must mention "Calvinist" or "Arminian" as an example of a contested topic'
  );
});

test("BEREAN_DOCTRINAL_RESTRAINT: mentions eschatology / end-times", () => {
  assert.ok(
    BEREAN_DOCTRINAL_RESTRAINT.toLowerCase().includes("eschatology") ||
    BEREAN_DOCTRINAL_RESTRAINT.toLowerCase().includes("end-times"),
    'Must mention "eschatology" or "end-times" as an example of a contested topic'
  );
});

test("BEREAN_DOCTRINAL_RESTRAINT: mentions baptism as a contested topic", () => {
  assert.ok(
    BEREAN_DOCTRINAL_RESTRAINT.toLowerCase().includes("baptism"),
    'Must mention "baptism" as an example of a contested topic'
  );
});

test("BEREAN_DOCTRINAL_RESTRAINT: mentions cessationism as a contested topic", () => {
  assert.ok(
    BEREAN_DOCTRINAL_RESTRAINT.toLowerCase().includes("cessationism"),
    'Must mention "cessationism" as an example of a contested topic'
  );
});

test("BEREAN_DOCTRINAL_RESTRAINT: mentions women in ministry as a contested topic", () => {
  assert.ok(
    BEREAN_DOCTRINAL_RESTRAINT.toLowerCase().includes("women in ministry"),
    'Must mention "women in ministry" as an example of a contested topic'
  );
});

// ── Anti-verdict check ────────────────────────────────────────────────────────
// The constant must NOT contain language that picks a side or declares a verdict.

test('BEREAN_DOCTRINAL_RESTRAINT: does NOT contain "The correct view is"', () => {
  assert.ok(
    !BEREAN_DOCTRINAL_RESTRAINT.includes("The correct view is"),
    'Must NOT contain "The correct view is" — the constant enforces neutrality, not a verdict'
  );
});

test('BEREAN_DOCTRINAL_RESTRAINT: does NOT contain "The correct denomination"', () => {
  assert.ok(
    !BEREAN_DOCTRINAL_RESTRAINT.includes("The correct denomination"),
    'Must NOT contain "The correct denomination"'
  );
});

test('BEREAN_DOCTRINAL_RESTRAINT: does NOT contain "you must believe"', () => {
  assert.ok(
    !BEREAN_DOCTRINAL_RESTRAINT.toLowerCase().includes("you must believe"),
    'Must NOT contain "you must believe" — must not coerce a doctrinal position'
  );
});

// ── Application check: restraint is appended to target functions ──────────────
// Verify that each of the three target functions actually appends the constant.

test("bereanBibleQA: appends BEREAN_DOCTRINAL_RESTRAINT to system prompt", () => {
  // Look for the pattern in the source that concatenates the constant into the
  // bereanBibleQA system prompt. A template-literal or string concat is expected.
  const bibleQASection = srcText.slice(
    srcText.indexOf("exports.bereanBibleQA"),
    srcText.indexOf("exports.bereanBibleQAFallback")
  );
  assert.ok(
    bibleQASection.includes("BEREAN_DOCTRINAL_RESTRAINT"),
    "bereanBibleQA must append BEREAN_DOCTRINAL_RESTRAINT to its system prompt"
  );
});

test("bereanMoralCounsel: appends BEREAN_DOCTRINAL_RESTRAINT to system prompt", () => {
  const moralSection = srcText.slice(
    srcText.indexOf("exports.bereanMoralCounsel"),
    srcText.indexOf("exports.bereanBusinessQA")
  );
  assert.ok(
    moralSection.includes("BEREAN_DOCTRINAL_RESTRAINT"),
    "bereanMoralCounsel must append BEREAN_DOCTRINAL_RESTRAINT to its system prompt"
  );
});

test("bereanChatProxy: appends BEREAN_DOCTRINAL_RESTRAINT to system prompt", () => {
  const chatProxySection = srcText.slice(
    srcText.indexOf("exports.bereanChatProxy"),
    srcText.indexOf("exports.deleteAccount")
  );
  assert.ok(
    chatProxySection.includes("BEREAN_DOCTRINAL_RESTRAINT"),
    "bereanChatProxy must append BEREAN_DOCTRINAL_RESTRAINT to its system prompt"
  );
});

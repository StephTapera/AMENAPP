#!/usr/bin/env node
/**
 * no-spiritual-scoring-render.mjs — CI red line (Wave 6, invariants 1 + 4).
 *
 * Fails the build if any spiritual-performance / scoring field name appears in
 * the SwiftUI sources. Per the red lines `spiritual_surveillance` and
 * `spiritual_scoring`, these fields must never be COMPUTED or RENDERED — so any
 * occurrence in the iOS codebase is a violation, not just a render site.
 *
 * Kept in sync with SPIRITUAL_SURVEILLANCE_KEYS in
 * Backend/functions/src/governance/contracts.ts / amenExclusionValidator.ts.
 *
 * Usage:  node scripts/governance/no-spiritual-scoring-render.mjs [rootDir]
 * Exit:   0 clean, 1 violation(s) found.
 */

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, extname } from "node:path";

// HARD-FAIL identifiers: unambiguous spiritual SCORING / RANKING / profiling.
// These must never be computed or rendered (RED LINES spiritual_scoring +
// spiritual_surveillance). NOT included here: streak/frequency/giving/attendance
// fields — those may map to legitimate existing features and are blocked at the
// EXPORT boundary (amenExclusionValidator) rather than banned from existing.
const FORBIDDEN = [
  "pietyScore", "faithfulnessScore", "faithfulnessRank", "doctrinalSoundnessScore",
  "spiritualGrowthScore", "sanctificationScore", "holinessScore", "devotionScore",
  "spiritualScore", "spiritualRank",
];

// REVIEWED & PERMITTED (invariant 1 — formation over engagement).
// Fields a human reviewer inspected for "streak-as-pressure" risk and explicitly
// CLEARED to remain. This is the recorded verdict that resolves Docs/governance/GAPS.md
// G-1: the audit no longer just "surfaces" prayerStreak each run — the decision is
// codified here, emitted on every run, and is the durable record (invariant 8).
const REVIEWED_PERMITTED = [
  {
    field: "prayerStreak",
    verdict: "PERMITTED — rhythm, not pressure",
    reviewedAtISO: "2026-06-22",
    basis:
      "Count is hidden (vanityMetricsAlwaysHidden); UI reads 'Your prayer rhythm', " +
      "never a number or 'don't break your streak'; private and never compared to " +
      "others; no streak-tied notifications. Meets invariant 1 — no engagement pressure.",
    ref: "Docs/governance/GAPS.md#g-1",
    sites: "BereanPrayer/BereanPrayerService.swift, BereanPrayerModels.swift, BereanPrayerBriefingView.swift",
  },
];

const root = process.argv[2] || "AMENAPP";
const patterns = FORBIDDEN.map((f) => ({ id: f, re: new RegExp(f, "i") }));
const violations = [];

function walk(dir) {
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return;
  }
  for (const name of entries) {
    if (name === "node_modules" || name === ".git" || name.endsWith(".nosync")) continue;
    const full = join(dir, name);
    let st;
    try {
      st = statSync(full);
    } catch {
      continue;
    }
    if (st.isDirectory()) {
      walk(full);
    } else if (extname(full) === ".swift") {
      const text = readFileSync(full, "utf8");
      const lines = text.split("\n");
      lines.forEach((line, i) => {
        for (const p of patterns) {
          if (p.re.test(line)) {
            violations.push(`${full}:${i + 1}: forbidden spiritual-scoring field "${p.id}"`);
          }
        }
      });
    }
  }
}

walk(root);

if (violations.length > 0) {
  console.error("RED LINE VIOLATION — spiritual scoring/surveillance fields found:");
  for (const v of violations) console.error("  " + v);
  console.error(`\n${violations.length} violation(s). Spiritual-performance metrics must never be computed or rendered.`);
  process.exit(1);
}

console.log("OK — no spiritual-scoring/surveillance fields found in Swift sources.");

// Emit the recorded human-review verdicts (invariant 8 — durable record).
for (const r of REVIEWED_PERMITTED) {
  console.log(
    `REVIEWED & PERMITTED: ${r.field} — ${r.verdict} ` +
    `(reviewed ${r.reviewedAtISO}; ${r.ref})`
  );
}
process.exit(0);

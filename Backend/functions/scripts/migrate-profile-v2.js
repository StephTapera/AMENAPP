#!/usr/bin/env node
/**
 * migrate-profile-v2.js
 *
 * Backfills all existing user documents with the Profile Header v2
 * sub-fields under `profile.*`.
 *
 * Fields written (only when NOT already present on the document):
 *   profile.links           — []
 *   profile.pinSlots        — []
 *   profile.roleFlags       — { isMentor, isCreator, isMinistryLeader, isChurchAccount, churchId }
 *   profile.profileMetrics  — { peopleDiscipled, versesShared, yearsWalkingWithChrist, testimoniesGiven, prayersOffered }
 *   profile.bereanAboutOptIn — false
 *
 * Usage:
 *   node migrate-profile-v2.js                  # live run
 *   node migrate-profile-v2.js --dry-run        # preview only — no writes
 *
 * Prerequisites:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 *   OR run inside a Firebase Functions shell / emulator that auto-initialises admin.
 *
 * The script is fully idempotent: fields that already exist are not
 * overwritten because Firestore merge semantics are used and each document
 * is checked before the batch is committed.
 *
 * Processes users in batches of 500 (Firestore batch write limit) and
 * pages through the users collection with cursor-based pagination.
 */

"use strict";

const admin = require("firebase-admin");

// ── Initialise Admin SDK ───────────────────────────────────────────────────

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// ── CLI flags ──────────────────────────────────────────────────────────────

const DRY_RUN = process.argv.includes("--dry-run");

if (DRY_RUN) {
  console.log("[migrate-profile-v2] DRY RUN — no documents will be written.\n");
} else {
  console.log("[migrate-profile-v2] LIVE RUN — documents will be updated.\n");
}

// ── Default values ─────────────────────────────────────────────────────────

const DEFAULT_PROFILE_LINKS = [];
const DEFAULT_PIN_SLOTS = [];
const DEFAULT_ROLE_FLAGS = {
  isMentor: false,
  isCreator: false,
  isMinistryLeader: false,
  isChurchAccount: false,
  churchId: null,
};
const DEFAULT_PROFILE_METRICS = {
  peopleDiscipled: 0,
  versesShared: 0,
  yearsWalkingWithChrist: null,
  testimoniesGiven: 0,
  prayersOffered: 0,
};
const DEFAULT_BEREAN_ABOUT_OPT_IN = false;

// ── Main ───────────────────────────────────────────────────────────────────

const PAGE_SIZE = 500; // Also the Firestore batch write limit

async function main() {
  let totalProcessed = 0;
  let totalSkipped = 0;
  let totalUpdated = 0;
  let totalErrors = 0;
  let cursor = null;
  let pageNumber = 0;

  console.log("[migrate-profile-v2] Starting pagination over users collection...\n");

  while (true) {
    pageNumber++;

    // Build paginated query
    let query = db.collection("users").orderBy("__name__").limit(PAGE_SIZE);
    if (cursor) {
      query = query.startAfter(cursor);
    }

    let snap;
    try {
      snap = await query.get();
    } catch (err) {
      console.error(`[migrate-profile-v2] ERROR: failed to fetch page ${pageNumber}:`, err.message);
      break;
    }

    if (snap.empty) {
      console.log(`[migrate-profile-v2] Page ${pageNumber}: no more documents. Done.\n`);
      break;
    }

    console.log(
      `[migrate-profile-v2] Page ${pageNumber}: processing ${snap.docs.length} users...`
    );

    // Build a single batch for this page
    const batch = db.batch();
    let batchCount = 0;

    for (const doc of snap.docs) {
      totalProcessed++;
      const data = doc.data();
      const existingProfile = data.profile || {};

      // Build the update map — only include fields that are absent
      const update = {};

      if (!("links" in existingProfile)) {
        update["profile.links"] = DEFAULT_PROFILE_LINKS;
      }
      if (!("pinSlots" in existingProfile)) {
        update["profile.pinSlots"] = DEFAULT_PIN_SLOTS;
      }
      if (!("roleFlags" in existingProfile)) {
        update["profile.roleFlags"] = DEFAULT_ROLE_FLAGS;
      }
      if (!("profileMetrics" in existingProfile)) {
        update["profile.profileMetrics"] = DEFAULT_PROFILE_METRICS;
      }
      if (!("bereanAboutOptIn" in existingProfile)) {
        update["profile.bereanAboutOptIn"] = DEFAULT_BEREAN_ABOUT_OPT_IN;
      }

      // If nothing needs updating, skip this document entirely
      if (Object.keys(update).length === 0) {
        totalSkipped++;
        continue;
      }

      if (DRY_RUN) {
        console.log(
          `  [DRY-RUN] Would update ${doc.id}:`,
          Object.keys(update).join(", ")
        );
        totalUpdated++;
        continue;
      }

      // Queue the update in the current batch
      batch.update(doc.ref, update);
      batchCount++;
      totalUpdated++;
    }

    // Commit this page's batch (skip in dry-run, or when nothing was queued)
    if (!DRY_RUN && batchCount > 0) {
      try {
        await batch.commit();
        console.log(
          `  Committed batch: ${batchCount} updates on page ${pageNumber}.`
        );
      } catch (err) {
        totalErrors += batchCount;
        totalUpdated -= batchCount;
        console.error(
          `  ERROR: batch commit failed on page ${pageNumber}:`,
          err.message
        );
      }
    } else if (!DRY_RUN) {
      console.log(`  Page ${pageNumber}: all documents already up-to-date, nothing committed.`);
    }

    // Advance cursor
    cursor = snap.docs[snap.docs.length - 1];

    // Short-circuit if the last page was smaller than PAGE_SIZE
    if (snap.docs.length < PAGE_SIZE) {
      console.log(`[migrate-profile-v2] Reached last page (${snap.docs.length} docs). Done.\n`);
      break;
    }
  }

  // ── Summary ──────────────────────────────────────────────────────────────
  console.log("─────────────────────────────────────────────");
  console.log("[migrate-profile-v2] Migration complete.");
  console.log(`  Total users processed : ${totalProcessed}`);
  console.log(`  Already up-to-date    : ${totalSkipped}`);
  console.log(`  Updated (or would be) : ${totalUpdated}`);
  console.log(`  Errors                : ${totalErrors}`);
  if (DRY_RUN) {
    console.log("\n  DRY RUN — re-run without --dry-run to apply changes.");
  }
  console.log("─────────────────────────────────────────────");
}

main().catch((err) => {
  console.error("[migrate-profile-v2] Fatal error:", err);
  process.exit(1);
});

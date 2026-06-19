#!/usr/bin/env node
/**
 * NG-1 visible backfill — prep for the firestore.rules posts read-gate change.
 *
 * The new read rule requires `visible == true` for non-owner public reads. Already-approved
 * legacy posts that lack the field would otherwise vanish for everyone but their owner.
 * This script sets visible:true on posts that are clearly already approved
 * (NOT removed, NOT flaggedForReview, NOT already visible:true).
 *
 * SAFE BY DEFAULT: dry-run unless you pass --commit.
 *
 *   node scripts/ng1-visible-backfill.js              # dry-run: counts only, no writes
 *   node scripts/ng1-visible-backfill.js --commit     # performs batched writes
 *
 * Requires GOOGLE_APPLICATION_CREDENTIALS pointing at a service-account key with
 * Firestore write access. Run from a trusted machine — HUMAN-approved per CLAUDE.md.
 */

const admin = require("firebase-admin");

const COMMIT = process.argv.includes("--commit");
const BATCH = 400;

admin.initializeApp();
const db = admin.firestore();

async function main() {
  console.log(`NG-1 backfill — mode: ${COMMIT ? "COMMIT (writing)" : "DRY-RUN (no writes)"}`);

  let scanned = 0;
  let needsBackfill = 0;
  let stillPending = 0;
  let written = 0;

  let last = null;
  // Page through all posts. We filter in code (not a query) because `visible` may be
  // unset on legacy docs and Firestore can't query for "field absent".
  // eslint-disable-next-line no-constant-condition
  while (true) {
    let q = db.collection("posts").orderBy(admin.firestore.FieldPath.documentId()).limit(1000);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;

    let batch = db.batch();
    let inBatch = 0;

    for (const doc of snap.docs) {
      scanned++;
      const d = doc.data();
      const visible = d.visible === true;
      const removed = d.removed === true || d.isDeleted === true;
      const flagged = d.flaggedForReview === true;

      if (visible) continue;                 // already correct
      if (removed || flagged) { stillPending++; continue; } // genuinely not approved — leave hidden

      needsBackfill++;
      if (COMMIT) {
        batch.update(doc.ref, { visible: true, ng1BackfilledAt: admin.firestore.FieldValue.serverTimestamp() });
        inBatch++;
        if (inBatch >= BATCH) {
          await batch.commit();
          written += inBatch;
          batch = db.batch();
          inBatch = 0;
        }
      }
    }
    if (COMMIT && inBatch > 0) { await batch.commit(); written += inBatch; }
    last = snap.docs[snap.docs.length - 1];
  }

  console.log("---");
  console.log(`scanned:        ${scanned}`);
  console.log(`already visible: ${scanned - needsBackfill - stillPending}`);
  console.log(`need backfill:   ${needsBackfill}${COMMIT ? ` (written: ${written})` : ""}`);
  console.log(`left hidden (removed/flagged): ${stillPending}`);
  console.log(COMMIT
    ? "DONE. Re-run dry-run to confirm only removed/flagged posts remain non-visible, then deploy the rule."
    : "DRY-RUN only. Re-run with --commit when ready, then deploy: firebase deploy --only firestore:rules");
}

main().catch((e) => { console.error(e); process.exit(1); });

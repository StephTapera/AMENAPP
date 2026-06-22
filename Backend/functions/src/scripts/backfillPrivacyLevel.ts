/**
 * backfillPrivacyLevel.ts
 *
 * C-3 migration: set privacyLevel from visibility for all posts that lack it.
 *
 * WHY THIS EXISTS:
 *   The updated Firestore Rules (2026-06-12) added isFollowersOnlyPost() and
 *   isTrustedCirclePost() helpers that check BOTH privacyLevel and visibility.
 *   However, the post read rule's followers-only and trustedCircle branches
 *   only trigger when the helpers return true — so old posts that only have
 *   visibility set will still be correctly gated.
 *
 *   The backfill is a belt-and-suspenders step that ensures every post has a
 *   canonical privacyLevel field, making future rule simplification possible
 *   and ensuring algoliaSync, aclHelper, and any new code reading only
 *   privacyLevel work correctly for legacy posts.
 *
 * MAPPING (from docs/privacy-model.md §7 — DO NOT deviate):
 *   "Everyone" / "everyone" / ""       → "public"
 *   "Followers" / "followers"          → "followers"
 *   "Community Only" / "community"
 *     / "trustedCircle"                → "trustedCircle"
 *   "church"                           → "church"
 *   "space"                            → "space"
 *   "private"                          → "private"
 *   "deleted"                          → "private"  (soft-deleted, treated as private)
 *   BOTH fields missing                → "public"   (consistent with isEffectivelyPublic() default)
 *
 * IDEMPOTENCY:
 *   - Skips docs that already have privacyLevel set (any non-empty string).
 *   - Re-runnable safely; only touches privacyLevel-absent docs.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=~/.config/gcloud/application_default_credentials.json \
 *   FIREBASE_PROJECT_ID=amen-5e359 \
 *   node ./lib/scripts/backfillPrivacyLevel.js --dry-run
 *
 *   GOOGLE_APPLICATION_CREDENTIALS=~/.config/gcloud/application_default_credentials.json \
 *   FIREBASE_PROJECT_ID=amen-5e359 \
 *   node ./lib/scripts/backfillPrivacyLevel.js
 */

import * as admin from "firebase-admin";

const BATCH_SIZE = 400;
const DRY_RUN = process.argv.includes("--dry-run");

// ─── Canonical visibility → privacyLevel mapping ──────────────────────────────
// Source of truth: docs/privacy-model.md §7

function mapVisibilityToPrivacyLevel(visibility: string | undefined): string {
    if (!visibility || visibility === "") return "public";
    switch (visibility) {
        case "Everyone":
        case "everyone":
        case "public":
            return "public";
        case "Followers":
        case "followers":
            return "followers";
        case "Community Only":
        case "community":
        case "trustedCircle":
            return "trustedCircle";
        case "church":
            return "church";
        case "space":
            return "space";
        case "private":
            return "private";
        case "deleted":
            return "private";
        default:
            // UNKNOWN value — do NOT guess a privacy field. Log and skip.
            return "__UNKNOWN__";
    }
}

type CountMap = Record<string, number>;

async function main(): Promise<void> {
    // ── Init ──────────────────────────────────────────────────────────────────
    if (admin.apps.length === 0) {
        admin.initializeApp({
            projectId: process.env.FIREBASE_PROJECT_ID ?? process.env.GCLOUD_PROJECT ?? "amen-5e359",
        });
    }
    const db = admin.firestore();

    console.log(`
╔══════════════════════════════════════════════════════════════╗
║  backfillPrivacyLevel — C-3 migration                        ║
║  Project: ${(process.env.FIREBASE_PROJECT_ID ?? "amen-5e359").padEnd(49)}║
║  Mode: ${DRY_RUN ? "DRY RUN (no writes)".padEnd(53) : "LIVE WRITE".padEnd(53)}║
╚══════════════════════════════════════════════════════════════╝
`);

    // ── Phase 1: Count docs missing privacyLevel ──────────────────────────────
    // We cannot query "field does not exist" directly in Firestore, so we page
    // through ALL posts and check each doc client-side. Scoped by page cursors.
    let scanned = 0;
    let alreadyHasPrivacyLevel = 0;
    let toMigrate = 0;
    let unknownValues = 0;
    const mappingCounts: CountMap = {};
    const sampleRows: string[] = [];
    let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;

    console.log("Phase 1: scanning posts collection...");

    while (true) {
        let q: FirebaseFirestore.Query = db.collection("posts")
            .orderBy("createdAt", "desc")
            .limit(BATCH_SIZE);
        if (lastDoc) q = q.startAfter(lastDoc);

        const snap = await q.get();
        if (snap.empty) break;

        for (const doc of snap.docs) {
            scanned++;
            const data = doc.data();
            const existingPL = data.privacyLevel as string | undefined;
            const visibility = data.visibility as string | undefined;

            if (existingPL && existingPL.trim() !== "") {
                alreadyHasPrivacyLevel++;
                continue;
            }

            const derivedPL = mapVisibilityToPrivacyLevel(visibility);

            if (derivedPL === "__UNKNOWN__") {
                unknownValues++;
                console.warn(`[UNKNOWN] doc ${doc.id}: visibility="${visibility}" — SKIP`);
                continue;
            }

            toMigrate++;
            mappingCounts[`${visibility ?? "(missing)"} → ${derivedPL}`] =
                (mappingCounts[`${visibility ?? "(missing)"} → ${derivedPL}`] || 0) + 1;

            if (sampleRows.length < 20) {
                sampleRows.push(`  ${doc.id.slice(0, 16)}… visibility="${visibility ?? ""}" → privacyLevel="${derivedPL}"`);
            }
        }

        lastDoc = snap.docs[snap.docs.length - 1];
        process.stdout.write(`\r  Scanned: ${scanned} posts…`);
    }

    console.log(`\n\nPhase 1 complete:`);
    console.log(`  Total scanned:          ${scanned}`);
    console.log(`  Already has privacyLevel: ${alreadyHasPrivacyLevel} (will skip)`);
    console.log(`  To migrate:             ${toMigrate}`);
    console.log(`  UNKNOWN visibility values: ${unknownValues} (SKIPPED — require manual review)`);
    console.log(`\nMapping breakdown:`);
    for (const [mapping, count] of Object.entries(mappingCounts).sort()) {
        console.log(`  ${count.toString().padStart(6)}  ${mapping}`);
    }
    console.log(`\n20-row sample of docs to migrate:`);
    for (const row of sampleRows) console.log(row);

    if (toMigrate === 0) {
        console.log("\n✅ NOTHING TO MIGRATE — all posts already have privacyLevel. Done.");
        return;
    }

    if (DRY_RUN) {
        console.log(`\n🔵 DRY RUN — no writes performed. Re-run without --dry-run to apply.`);
        return;
    }

    // ── Sanity check: count > 2x of any single bucket is suspicious ───────────
    const maxBucket = Math.max(...Object.values(mappingCounts));
    const totalNonPublic = Object.entries(mappingCounts)
        .filter(([k]) => !k.includes("public"))
        .reduce((acc, [, v]) => acc + v, 0);
    if (totalNonPublic > scanned * 0.3) {
        console.error(`\n⚠️  ANOMALY: ${totalNonPublic} posts (${((totalNonPublic/scanned)*100).toFixed(1)}%) would be set to non-public.`);
        console.error(`   This exceeds 30% of total posts — unexpected ratio. STOPPING.`);
        console.error(`   Review the mapping breakdown above before re-running.`);
        process.exit(1);
    }

    // ── Phase 2: Apply migration ──────────────────────────────────────────────
    console.log(`\nPhase 2: applying migration (batches of ${BATCH_SIZE})...`);
    let written = 0;
    let skippedUnknown = 0;
    lastDoc = null;

    while (true) {
        let q: FirebaseFirestore.Query = db.collection("posts")
            .orderBy("createdAt", "desc")
            .limit(BATCH_SIZE);
        if (lastDoc) q = q.startAfter(lastDoc);

        const snap = await q.get();
        if (snap.empty) break;

        const batch = db.batch();
        let batchSize = 0;

        for (const doc of snap.docs) {
            const data = doc.data();
            const existingPL = data.privacyLevel as string | undefined;
            if (existingPL && existingPL.trim() !== "") continue;

            const visibility = data.visibility as string | undefined;
            const derivedPL = mapVisibilityToPrivacyLevel(visibility);

            if (derivedPL === "__UNKNOWN__") {
                skippedUnknown++;
                continue;
            }

            batch.update(doc.ref, {
                privacyLevel: derivedPL,
                privacyLevelBackfilledAt: admin.firestore.FieldValue.serverTimestamp(),
                privacyLevelBackfillSource: "backfillPrivacyLevel-2026-06-12",
            });
            batchSize++;
        }

        if (batchSize > 0) {
            await batch.commit();
            written += batchSize;
        }

        lastDoc = snap.docs[snap.docs.length - 1];
        process.stdout.write(`\r  Written: ${written} / ${toMigrate}…`);
    }

    console.log(`\n\nPhase 2 complete: ${written} docs updated.`);
    if (skippedUnknown > 0) {
        console.warn(`  ⚠️  ${skippedUnknown} docs with UNKNOWN visibility skipped — require manual review.`);
    }

    // ── Phase 3: Verification ─────────────────────────────────────────────────
    console.log(`\nPhase 3: verifying — counting posts still missing privacyLevel...`);
    let stillMissing = 0;
    lastDoc = null;

    while (true) {
        let q: FirebaseFirestore.Query = db.collection("posts")
            .orderBy("createdAt", "desc")
            .limit(BATCH_SIZE);
        if (lastDoc) q = q.startAfter(lastDoc);

        const snap = await q.get();
        if (snap.empty) break;

        for (const doc of snap.docs) {
            const data = doc.data();
            const pl = data.privacyLevel as string | undefined;
            if (!pl || pl.trim() === "") stillMissing++;
        }

        lastDoc = snap.docs[snap.docs.length - 1];
    }

    if (stillMissing === 0) {
        console.log(`\n✅ VERIFICATION PASSED: 0 posts missing privacyLevel. D-2 complete.`);
    } else {
        console.error(`\n❌ VERIFICATION FAILED: ${stillMissing} posts still missing privacyLevel.`);
        console.error(`   Check logs above for UNKNOWN values. Re-run script after investigation.`);
        process.exit(1);
    }
}

main().catch((err) => {
    console.error("Fatal error:", err);
    process.exit(1);
});

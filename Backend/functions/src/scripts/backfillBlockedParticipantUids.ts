/**
 * backfillBlockedParticipantUids.ts
 *
 * W2-C3 migration: for existing blocked conversations, write the
 * blockedParticipantUids array field so the updated Firestore Rules
 * callerIsBlockedInConversation() helper can gate read access.
 *
 * WHY THIS EXISTS:
 *   blockRelationshipCleanup.ts (wave-2) now writes:
 *     blockedParticipantUids: FieldValue.arrayUnion(blockerId, blockedId)
 *   on conversations when a new block is created. However, conversations
 *   where a block was created BEFORE this wave-2 deploy only have the
 *   legacy blockedBetween: ["uid1_uid2"] field (sorted-pair string).
 *
 *   The Firestore Rules callerIsBlockedInConversation() checks
 *   blockedParticipantUids (individual UIDs), not blockedBetween (pair string).
 *   Without this backfill, existing blocked-pair conversations are still
 *   readable by blocked participants.
 *
 * STRATEGY:
 *   1. Query all conversations where blockedBetween is non-empty.
 *      (uses array-contains-any on a sentinel, or scans all conversations
 *       since there's no "array is not empty" query — scans are paged.)
 *   2. For each conversation with blockedBetween entries:
 *      - Parse each "uid1_uid2" sorted-pair string back to individual UIDs.
 *      - Write blockedParticipantUids: [uid1, uid2, ...] (union of all pairs).
 *   3. Verify no conversations with blockedBetween are missing blockedParticipantUids.
 *
 * IDEMPOTENCY:
 *   - Conversations already having blockedParticipantUids with correct entries
 *     are re-written with arrayUnion (no-op if already present).
 *   - Re-runnable safely.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=~/.config/gcloud/application_default_credentials.json \
 *   FIREBASE_PROJECT_ID=amen-5e359 \
 *   node ./lib/scripts/backfillBlockedParticipantUids.js --dry-run
 *
 *   GOOGLE_APPLICATION_CREDENTIALS=~/.config/gcloud/application_default_credentials.json \
 *   FIREBASE_PROJECT_ID=amen-5e359 \
 *   node ./lib/scripts/backfillBlockedParticipantUids.js
 */

import * as admin from "firebase-admin";

const BATCH_SIZE = 400;
const DRY_RUN = process.argv.includes("--dry-run");

/**
 * Parse a sorted-pair string "uid1_uid2" back to two UIDs.
 * The pair is stored sorted, so we can't recover which was blocker/blocked,
 * but for blockedParticipantUids we want BOTH UIDs anyway.
 *
 * Edge case: UIDs may contain "_" themselves. We split on the FIRST "_" that
 * produces two non-empty segments of reasonable length. If we can't cleanly
 * split, we log a warning and skip the pair.
 */
function parsePair(pair: string): [string, string] | null {
    // Firebase UID format is 28 chars (no underscore). Pairs are stored as
    // "{uid1}_{uid2}" where both uids are Firebase auth UIDs.
    // Split at the first underscore that leaves two non-empty segments.
    const idx = pair.indexOf("_");
    if (idx <= 0 || idx >= pair.length - 1) return null;
    const a = pair.slice(0, idx);
    const b = pair.slice(idx + 1);
    if (!a || !b) return null;
    return [a, b];
}

async function main(): Promise<void> {
    if (admin.apps.length === 0) {
        admin.initializeApp({
            projectId: process.env.FIREBASE_PROJECT_ID ?? process.env.GCLOUD_PROJECT ?? "amen-5e359",
        });
    }
    const db = admin.firestore();

    console.log(`
╔══════════════════════════════════════════════════════════════╗
║  backfillBlockedParticipantUids — W2-C3 migration            ║
║  Project: ${(process.env.FIREBASE_PROJECT_ID ?? "amen-5e359").padEnd(49)}║
║  Mode: ${DRY_RUN ? "DRY RUN (no writes)".padEnd(53) : "LIVE WRITE".padEnd(53)}║
╚══════════════════════════════════════════════════════════════╝
`);

    // ── Phase 1: Find conversations with blockedBetween ───────────────────────
    console.log("Phase 1: scanning conversations collection for blockedBetween entries...");

    let scanned = 0;
    let toMigrate = 0;
    let alreadyMigrated = 0;
    let parseErrors = 0;
    const sampleRows: string[] = [];
    let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;

    // candidateConvos: {ref, uidsToAdd}
    const candidates: Array<{
        ref: FirebaseFirestore.DocumentReference;
        uidsToAdd: string[];
    }> = [];

    while (true) {
        let q: FirebaseFirestore.Query = db.collection("conversations")
            .orderBy("__name__")
            .limit(BATCH_SIZE);
        if (lastDoc) q = q.startAfter(lastDoc);

        const snap = await q.get();
        if (snap.empty) break;

        for (const doc of snap.docs) {
            scanned++;
            const data = doc.data();
            const blockedBetween: string[] = data.blockedBetween ?? [];

            if (blockedBetween.length === 0) continue;

            const existingUids: string[] = data.blockedParticipantUids ?? [];
            const uidsNeeded: string[] = [];

            for (const pair of blockedBetween) {
                const parsed = parsePair(pair);
                if (!parsed) {
                    parseErrors++;
                    console.warn(`  [PARSE_ERROR] conv ${doc.id}: cannot parse pair "${pair}" — skip`);
                    continue;
                }
                const [a, b] = parsed;
                if (!existingUids.includes(a)) uidsNeeded.push(a);
                if (!existingUids.includes(b)) uidsNeeded.push(b);
            }

            // Deduplicate
            const dedupedNeeded = [...new Set(uidsNeeded)];

            if (dedupedNeeded.length === 0) {
                alreadyMigrated++;
                continue;
            }

            toMigrate++;
            candidates.push({ ref: doc.ref, uidsToAdd: dedupedNeeded });

            if (sampleRows.length < 20) {
                sampleRows.push(
                    `  ${doc.id.slice(0, 20).padEnd(22)} blockedBetween=[${blockedBetween.join(", ")}] ` +
                    `→ add UIDs: [${dedupedNeeded.join(", ")}]`
                );
            }
        }

        lastDoc = snap.docs[snap.docs.length - 1];
        process.stdout.write(`\r  Scanned: ${scanned} conversations…`);
    }

    console.log(`\n\nPhase 1 complete:`);
    console.log(`  Total conversations scanned: ${scanned}`);
    console.log(`  Already have blockedParticipantUids: ${alreadyMigrated} (will skip / idempotent)`);
    console.log(`  Need backfill: ${toMigrate}`);
    if (parseErrors > 0) {
        console.warn(`  ⚠️  Parse errors (skipped): ${parseErrors} — review logs above.`);
    }
    if (sampleRows.length > 0) {
        console.log(`\n20-conv sample:`);
        for (const row of sampleRows) console.log(row);
    }

    if (toMigrate === 0) {
        console.log("\n✅ NOTHING TO MIGRATE — all blocked conversations already backfilled. Done.");
        return;
    }

    if (DRY_RUN) {
        console.log(`\n🔵 DRY RUN — no writes performed. Re-run without --dry-run to apply.`);
        return;
    }

    // ── Phase 2: Apply migration ──────────────────────────────────────────────
    console.log(`\nPhase 2: writing blockedParticipantUids to ${toMigrate} conversations...`);
    let written = 0;

    for (let i = 0; i < candidates.length; i += 499) {
        const chunk = candidates.slice(i, i + 499); // Firestore batch limit = 500 ops
        const batch = db.batch();

        for (const { ref, uidsToAdd } of chunk) {
            batch.update(ref, {
                blockedParticipantUids: admin.firestore.FieldValue.arrayUnion(...uidsToAdd),
                blockedParticipantUidsBackfilledAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }

        await batch.commit();
        written += chunk.length;
        process.stdout.write(`\r  Written: ${written} / ${toMigrate}…`);
    }

    console.log(`\n\nPhase 2 complete: ${written} conversations updated.`);

    // ── Phase 3: Verification ─────────────────────────────────────────────────
    console.log(`\nPhase 3: verifying — scanning for blockedBetween convos missing blockedParticipantUids...`);
    let stillMissing = 0;
    lastDoc = null;

    while (true) {
        let q: FirebaseFirestore.Query = db.collection("conversations")
            .orderBy("__name__")
            .limit(BATCH_SIZE);
        if (lastDoc) q = q.startAfter(lastDoc);

        const snap = await q.get();
        if (snap.empty) break;

        for (const doc of snap.docs) {
            const data = doc.data();
            const blockedBetween: string[] = data.blockedBetween ?? [];
            if (blockedBetween.length === 0) continue;

            const existingUids: string[] = data.blockedParticipantUids ?? [];
            for (const pair of blockedBetween) {
                const parsed = parsePair(pair);
                if (!parsed) continue;
                const [a, b] = parsed;
                if (!existingUids.includes(a) || !existingUids.includes(b)) {
                    stillMissing++;
                }
            }
        }

        lastDoc = snap.docs[snap.docs.length - 1];
    }

    if (stillMissing === 0) {
        console.log(`\n✅ VERIFICATION PASSED: all blocked conversations have blockedParticipantUids. W2-C3 complete.`);
    } else {
        console.error(`\n❌ VERIFICATION FAILED: ${stillMissing} conversations still missing blockedParticipantUids entries.`);
        console.error(`   This may be due to unparseable pair strings — review parse errors above.`);
        process.exit(1);
    }
}

main().catch((err) => {
    console.error("Fatal error:", err);
    process.exit(1);
});

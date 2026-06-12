/**
 * algoliaPrivacyPurge.ts
 *
 * D-4 (per H-6 deploy order): Delete all non-public posts from the Algolia index.
 *
 * WHY THIS EXISTS:
 *   Before algoliaSync.ts was fixed (2026-06-12), posts with visibility='Followers'
 *   or visibility='Community Only' were indexed in Algolia and appeared in search
 *   results for any user. Algolia cannot enforce per-user follow/block relationships.
 *
 *   algoliaSync.ts now prevents re-introduction going forward. This script purges
 *   the historical backlog.
 *
 * STRATEGY:
 *   1. Fetch all Algolia record objectIDs (browse the entire index, no filter).
 *   2. For each record, read its source Firestore doc.
 *   3. Delete from Algolia if:
 *      - Source doc is missing (deleted post with stale index entry)
 *      - Source doc has isDeleted: true
 *      - Source doc has privacyLevel or visibility that is NOT public/Everyone
 *   4. Keep records whose source is clearly public.
 *
 * RUN D-2 BACKFILL FIRST: this script uses privacyLevel as the canonical field.
 * Running before D-2 may miss legacy posts that only have visibility set — they
 * would be skipped as "public" because privacyLevel is absent. The H-6 deploy
 * order (D-2 → D-3 → D-4) ensures privacyLevel is populated before this runs.
 *
 * Usage:
 *   ALGOLIA_APP_ID=182SCN7O9S \
 *   ALGOLIA_ADMIN_KEY=<admin_api_key> \
 *   ALGOLIA_INDEX_NAME=posts \
 *   GOOGLE_APPLICATION_CREDENTIALS=~/.config/gcloud/application_default_credentials.json \
 *   FIREBASE_PROJECT_ID=amen-5e359 \
 *   node ./lib/scripts/algoliaPrivacyPurge.js --dry-run
 *
 * Flags:
 *   --dry-run    Print what would be deleted, no changes.
 *   --skip-firestore  Skip per-doc Firestore reads; delete based on privacyLevel
 *                     stored in the Algolia record itself (faster, less authoritative).
 */

import * as admin from "firebase-admin";

const DRY_RUN = process.argv.includes("--dry-run");
const SKIP_FIRESTORE = process.argv.includes("--skip-firestore");

const ALGOLIA_APP_ID = process.env.ALGOLIA_APP_ID ?? "182SCN7O9S";
const ALGOLIA_ADMIN_KEY = process.env.ALGOLIA_ADMIN_KEY ?? "";
const INDEX_NAME = process.env.ALGOLIA_INDEX_NAME ?? "posts";

function isPublicPrivacyLevel(pl: string | undefined, visibility: string | undefined): boolean {
    const effective = pl ?? visibility ?? "";
    return effective === "public" || effective === "Everyone" || effective === "everyone" || effective === "";
}

async function algoliaFetch(
    method: string,
    path: string,
    body?: unknown
): Promise<unknown> {
    const url = `https://${ALGOLIA_APP_ID}-dsn.algolia.net/1/indexes/${path}`;
    const resp = await fetch(url, {
        method,
        headers: {
            "Content-Type": "application/json",
            "X-Algolia-Application-Id": ALGOLIA_APP_ID,
            "X-Algolia-API-Key": ALGOLIA_ADMIN_KEY,
        },
        body: body ? JSON.stringify(body) : undefined,
    });
    if (!resp.ok) {
        const text = await resp.text();
        throw new Error(`Algolia ${method} ${path} → ${resp.status}: ${text}`);
    }
    return resp.json();
}

async function main(): Promise<void> {
    if (!ALGOLIA_ADMIN_KEY) {
        console.error("ALGOLIA_ADMIN_KEY env var is required.");
        process.exit(1);
    }

    if (admin.apps.length === 0) {
        admin.initializeApp({
            projectId: process.env.FIREBASE_PROJECT_ID ?? "amen-5e359",
        });
    }
    const db = admin.firestore();

    console.log(`
╔══════════════════════════════════════════════════════════════╗
║  algoliaPrivacyPurge — D-4 non-public record removal         ║
║  Index: ${INDEX_NAME.padEnd(53)}║
║  Mode: ${DRY_RUN ? "DRY RUN (no writes)".padEnd(54) : "LIVE DELETE".padEnd(54)}║
╚══════════════════════════════════════════════════════════════╝
`);

    // ── Phase 1: Browse all Algolia records ───────────────────────────────────
    console.log("Phase 1: browsing Algolia index...");
    const toDelete: string[] = [];
    const reasons: Record<string, string> = {};
    let cursor: string | undefined;
    let totalBrowsed = 0;

    while (true) {
        const browseBody: Record<string, unknown> = {
            attributesToRetrieve: ["objectID", "privacyLevel", "visibility", "authorId"],
            hitsPerPage: 1000,
        };
        if (cursor) browseBody.cursor = cursor;

        const result = await algoliaFetch("POST", `${INDEX_NAME}/browse`, browseBody) as {
            hits: Array<{ objectID: string; privacyLevel?: string; visibility?: string }>;
            cursor?: string;
            nbHits?: number;
        };

        for (const hit of result.hits ?? []) {
            totalBrowsed++;

            if (!SKIP_FIRESTORE) {
                // Authoritative check: read Firestore source doc
                const postSnap = await db.collection("posts").doc(hit.objectID).get();

                if (!postSnap.exists) {
                    toDelete.push(hit.objectID);
                    reasons[hit.objectID] = "Firestore doc missing (stale index entry)";
                    continue;
                }

                const data = postSnap.data()!;
                if (data.isDeleted === true) {
                    toDelete.push(hit.objectID);
                    reasons[hit.objectID] = "isDeleted=true";
                    continue;
                }

                const pl = data.privacyLevel as string | undefined;
                const vis = data.visibility as string | undefined;

                if (!isPublicPrivacyLevel(pl, vis)) {
                    toDelete.push(hit.objectID);
                    reasons[hit.objectID] = `privacyLevel="${pl ?? ""}" visibility="${vis ?? ""}"`;
                }
            } else {
                // Fast path: use privacy fields stored in Algolia record
                if (!isPublicPrivacyLevel(hit.privacyLevel, hit.visibility)) {
                    toDelete.push(hit.objectID);
                    reasons[hit.objectID] = `algolia record: privacyLevel="${hit.privacyLevel ?? ""}"`;
                }
            }
        }

        cursor = result.cursor;
        process.stdout.write(`\r  Browsed: ${totalBrowsed} records, flagged: ${toDelete.length}…`);
        if (!cursor) break;
    }

    console.log(`\n\nPhase 1 complete:`);
    console.log(`  Total records browsed: ${totalBrowsed}`);
    console.log(`  Records to delete:     ${toDelete.length}`);
    console.log(`  Records to keep:       ${totalBrowsed - toDelete.length}`);

    if (toDelete.length > 0) {
        console.log(`\n20-record sample of records flagged for deletion:`);
        for (const id of toDelete.slice(0, 20)) {
            console.log(`  ${id.slice(0, 20).padEnd(22)} reason: ${reasons[id]}`);
        }
    }

    if (toDelete.length === 0) {
        console.log("\n✅ NOTHING TO DELETE — index is already clean. Done.");
        return;
    }

    if (DRY_RUN) {
        console.log(`\n🔵 DRY RUN — no deletes performed. Re-run without --dry-run to apply.`);
        return;
    }

    // ── Sanity check: >50% deletion is suspicious ─────────────────────────────
    if (toDelete.length > totalBrowsed * 0.5) {
        console.error(`\n⚠️  ANOMALY: ${toDelete.length} of ${totalBrowsed} records (${((toDelete.length/totalBrowsed)*100).toFixed(1)}%) flagged for deletion.`);
        console.error(`   This exceeds 50% — unexpected ratio. STOPPING.`);
        console.error(`   Review the sample above. If correct, run with --skip-firestore override after manual confirmation.`);
        process.exit(1);
    }

    // ── Phase 2: Batch delete from Algolia ───────────────────────────────────
    console.log(`\nPhase 2: deleting ${toDelete.length} records from Algolia (batches of 1000)...`);
    let deleted = 0;
    for (let i = 0; i < toDelete.length; i += 1000) {
        const chunk = toDelete.slice(i, i + 1000);
        await algoliaFetch("POST", `${INDEX_NAME}/batch`, {
            requests: chunk.map((id) => ({ action: "deleteObject", body: { objectID: id } })),
        });
        deleted += chunk.length;
        process.stdout.write(`\r  Deleted: ${deleted} / ${toDelete.length}…`);
    }
    console.log(`\n\n✅ Phase 2 complete: ${deleted} records deleted from Algolia.`);

    // ── Phase 3: Verification ─────────────────────────────────────────────────
    console.log(`\nPhase 3: verifying — re-browse index to confirm deletions applied...`);
    await new Promise((r) => setTimeout(r, 3000)); // Algolia indexing lag

    let remaining = 0;
    cursor = undefined;
    while (true) {
        const browseBody: Record<string, unknown> = {
            attributesToRetrieve: ["objectID", "privacyLevel", "visibility"],
            hitsPerPage: 1000,
        };
        if (cursor) browseBody.cursor = cursor;

        const result = await algoliaFetch("POST", `${INDEX_NAME}/browse`, browseBody) as {
            hits: Array<{ objectID: string; privacyLevel?: string; visibility?: string }>;
            cursor?: string;
        };

        for (const hit of result.hits ?? []) {
            if (!isPublicPrivacyLevel(hit.privacyLevel, hit.visibility)) remaining++;
        }

        cursor = result.cursor;
        if (!cursor) break;
    }

    if (remaining === 0) {
        console.log(`\n✅ VERIFICATION PASSED: 0 non-public records in Algolia. D-4 complete.`);
    } else {
        console.error(`\n❌ VERIFICATION FAILED: ${remaining} non-public records still in Algolia.`);
        console.error(`   Re-run the script to catch any records missed in this pass.`);
        process.exit(1);
    }
}

main().catch((err) => {
    console.error("Fatal error:", err);
    process.exit(1);
});

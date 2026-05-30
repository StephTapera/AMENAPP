/**
 * orgDeduplication.ts
 *
 * Cloud Function: `deduplicateOrgs`
 *
 * Finds duplicate org stubs and merges them, keeping the highest-priority
 * source record and preserving both source IDs.
 *
 * Duplicate detection:
 *   - Same `normalizedName` AND within 1 km of each other (GeoPoint distance)
 *   - Records with geo=null are matched by normalizedName + state + city only
 *
 * Merge strategy (source priority, highest first):
 *   nces_ccd > nces_pss > ipeds > irs_bmf > user_created > partner_import
 *
 * On merge:
 *   - The lower-priority doc is deleted
 *   - The higher-priority doc gains `sourceIds: string[]` containing both IDs
 *   - `metadata.mergedSources` records the merge history
 *
 * Dry-run mode reports matching pairs without writing.
 *
 * Request payload:
 *   { dryRun?: boolean, limit?: number }
 *   limit: max orgs to scan per invocation (default: 5000)
 *
 * Security: Admin-only callable.
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import * as FirebaseFirestore from "@google-cloud/firestore";
import { writeOpsRun, isOrgSeedEnabled } from "./orgImportUtils";

const REGION = "us-central1";
const db = admin.firestore();

// ─── Source priority (lower index = higher priority) ─────────────────────────
const SOURCE_PRIORITY: string[] = [
    "nces_ccd",
    "nces_pss",
    "ipeds",
    "irs_bmf",
    "user_created",
    "partner_import",
];

function sourcePriority(source: string): number {
    const idx = SOURCE_PRIORITY.indexOf(source);
    return idx === -1 ? SOURCE_PRIORITY.length : idx;
}

// ─── GeoPoint distance (Haversine approximation) ────────────────────────────

const EARTH_RADIUS_KM = 6371;

function haversineKm(
    lat1: number, lng1: number,
    lat2: number, lng2: number
): number {
    const toRad = (deg: number) => (deg * Math.PI) / 180;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return EARTH_RADIUS_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

const DEDUP_RADIUS_KM = 1.0;

// ─── Types ────────────────────────────────────────────────────────────────────

interface OrgDocData {
    id: string;
    source: string;
    sourceId: string;
    normalizedName: string;
    city: string;
    state: string;
    geo: FirebaseFirestore.GeoPoint | null;
    claimStatus: string;
    metadata: Record<string, unknown>;
    sourceIds?: string[];
}

interface DuplicatePair {
    keep: string;   // doc ID to keep
    drop: string;   // doc ID to delete
    keepSource: string;
    dropSource: string;
    keepSourceId: string;
    dropSourceId: string;
    matchReason: string;
}

// ─── Cloud Function ───────────────────────────────────────────────────────────

export const deduplicateOrgs = onCall(
    { region: REGION, timeoutSeconds: 540, memory: "1GiB" },
    async (request) => {
        if (request.auth?.token?.admin !== true) {
            throw new HttpsError("permission-denied", "Admin privileges required.");
        }

        const flags = await isOrgSeedEnabled();
        if (!flags.orgSeed) {
            logger.warn("[deduplicateOrgs] orgSeedEnabled flag is off — returning early");
            return { skipped: true, reason: "orgSeedEnabled flag is off" };
        }

        const data = request.data as { dryRun?: boolean; limit?: number } | undefined;
        const dryRun = data?.dryRun === true;
        const limit = Math.min(data?.limit ?? 5000, 10000);

        logger.info(`[deduplicateOrgs] Starting — dryRun=${dryRun}, limit=${limit}`);

        const runId = await writeOpsRun({
            job: "deduplicateOrgs",
            source: "all",
            dryRun,
            created: 0,
            updated: 0,
            skipped: 0,
            errors: [],
        });

        const startedAt = Date.now();
        let mergedCount = 0;
        let skippedCount = 0;
        const errors: string[] = [];
        const pairs: DuplicatePair[] = [];

        try {
            // ── Load a page of orgs (unclaimed only — never touch claimed orgs) ──
            const snap = await db
                .collection("organizations")
                .where("claimStatus", "==", "unclaimed")
                .limit(limit)
                .get();

            const docs: OrgDocData[] = snap.docs.map((d) => {
                const data = d.data();
                return {
                    id: d.id,
                    source: data.source as string,
                    sourceId: data.sourceId as string,
                    normalizedName: (data.normalizedName as string) ?? "",
                    city: (data.city as string) ?? "",
                    state: (data.state as string) ?? "",
                    geo: data.geo as FirebaseFirestore.GeoPoint | null,
                    claimStatus: data.claimStatus as string,
                    metadata: (data.metadata as Record<string, unknown>) ?? {},
                    sourceIds: data.sourceIds as string[] | undefined,
                };
            });

            logger.info(`[deduplicateOrgs] Loaded ${docs.length} unclaimed orgs for dedup scan`);

            // ── Build a lookup: normalizedName → list of docs ────────────────
            const byName = new Map<string, OrgDocData[]>();
            for (const doc of docs) {
                if (!doc.normalizedName) continue;
                const group = byName.get(doc.normalizedName) ?? [];
                group.push(doc);
                byName.set(doc.normalizedName, group);
            }

            // ── Track which doc IDs have already been merged this run ────────
            const alreadyProcessed = new Set<string>();

            for (const [, group] of byName) {
                if (group.length < 2) continue;

                // Within this name group, find pairs within 1 km
                for (let i = 0; i < group.length; i++) {
                    for (let j = i + 1; j < group.length; j++) {
                        const a = group[i];
                        const b = group[j];

                        if (alreadyProcessed.has(a.id) || alreadyProcessed.has(b.id)) continue;

                        const isDuplicate = checkDuplicate(a, b);
                        if (!isDuplicate) continue;

                        // Determine keep/drop by source priority
                        const aPriority = sourcePriority(a.source);
                        const bPriority = sourcePriority(b.source);
                        const keep = aPriority <= bPriority ? a : b;
                        const drop = aPriority <= bPriority ? b : a;

                        const pair: DuplicatePair = {
                            keep: keep.id,
                            drop: drop.id,
                            keepSource: keep.source,
                            dropSource: drop.source,
                            keepSourceId: keep.sourceId,
                            dropSourceId: drop.sourceId,
                            matchReason: isDuplicate,
                        };

                        pairs.push(pair);
                        alreadyProcessed.add(keep.id);
                        alreadyProcessed.add(drop.id);
                    }
                }
            }

            logger.info(`[deduplicateOrgs] Found ${pairs.length} duplicate pairs`);

            if (!dryRun) {
                // ── Merge pairs in Firestore batches ────────────────────────
                const BATCH_SIZE = 100; // Each pair = 2 ops (update + delete)
                for (let i = 0; i < pairs.length; i += BATCH_SIZE) {
                    const chunk = pairs.slice(i, i + BATCH_SIZE);
                    const batch = db.batch();

                    for (const pair of chunk) {
                        const keepRef = db.collection("organizations").doc(pair.keep);
                        const dropRef = db.collection("organizations").doc(pair.drop);

                        // Update the keep doc to include both sourceIds
                        batch.update(keepRef, {
                            sourceIds: admin.firestore.FieldValue.arrayUnion(
                                pair.keepSourceId,
                                pair.dropSourceId
                            ),
                            "metadata.mergedSources": admin.firestore.FieldValue.arrayUnion(
                                pair.dropSource
                            ),
                            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                        });

                        // Delete the lower-priority duplicate
                        batch.delete(dropRef);
                    }

                    try {
                        await batch.commit();
                        mergedCount += chunk.length;
                    } catch (batchErr) {
                        const msg = `Merge batch error: ${String(batchErr)}`;
                        errors.push(msg);
                        logger.error(`[deduplicateOrgs] ${msg}`);
                    }
                }
            } else {
                mergedCount = pairs.length; // Report what would be merged
            }
        } catch (err) {
            const msg = `Dedup error: ${String(err)}`;
            errors.push(msg);
            logger.error(`[deduplicateOrgs] ${msg}`);
        }

        const durationMs = Date.now() - startedAt;
        logger.info(`[deduplicateOrgs] Finished — pairs=${pairs.length}, merged=${mergedCount}, dryRun=${dryRun}, durationMs=${durationMs}`);

        await writeOpsRun({
            id: runId,
            job: "deduplicateOrgs",
            source: "all",
            finishedAt: admin.firestore.Timestamp.now(),
            created: 0,
            updated: mergedCount,
            skipped: skippedCount,
            errors: errors.slice(0, 100),
            dryRun,
        });

        const result: {
            runId: string;
            pairsFound: number;
            mergedCount: number;
            dryRun: boolean;
            durationMs: number;
            errorCount: number;
            pairs?: DuplicatePair[];
        } = {
            runId,
            pairsFound: pairs.length,
            mergedCount,
            dryRun,
            durationMs,
            errorCount: errors.length,
        };

        // In dry-run, return the pairs so the caller can inspect them
        if (dryRun) {
            result.pairs = pairs;
        }

        return result;
    }
);

// ─── Duplicate Detection Logic ───────────────────────────────────────────────

/**
 * Returns a match-reason string if a and b are considered duplicates,
 * or false if they are not.
 *
 * Match criteria (ordered — first match wins):
 * 1. Same normalizedName + geo within 1 km
 * 2. Same normalizedName + same state + same city (for records with no geo)
 */
function checkDuplicate(a: OrgDocData, b: OrgDocData): string | false {
    if (a.normalizedName !== b.normalizedName) return false;

    // Geo-based match
    if (a.geo && b.geo) {
        const distKm = haversineKm(
            a.geo.latitude, a.geo.longitude,
            b.geo.latitude, b.geo.longitude
        );
        if (distKm <= DEDUP_RADIUS_KM) {
            return `same_name_within_${distKm.toFixed(2)}km`;
        }
        // Same name but different locations — NOT duplicates (e.g. franchise churches)
        return false;
    }

    // No-geo match: same name + state + city
    if (
        a.state &&
        b.state &&
        a.state.toLowerCase() === b.state.toLowerCase() &&
        a.city &&
        b.city &&
        a.city.toLowerCase() === b.city.toLowerCase()
    ) {
        return "same_name_city_state_no_geo";
    }

    return false;
}

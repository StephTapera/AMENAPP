/**
 * ipedsImport.ts
 *
 * Cloud Function: `importIPEDS`
 *
 * Imports postsecondary institutions from the NCES Integrated Postsecondary
 * Education Data System (IPEDS) directory CSV, streamed from Cloud Storage.
 *
 * Data source: https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx
 * Key fields:
 *   UNITID   — unique institution ID (idempotency key)
 *   INSTNM   — institution name
 *   ADDR     — street address
 *   CITY, STABBR, ZIP — location
 *   LATITUDE, LONGITUDE — coordinates
 *   SECTOR   — 1-2=public, 3-5=private nonprofit, 6-7=for-profit
 *   CONTROL  — 1=public, 2=private nonprofit, 3=private for-profit
 *   RELAFFIL — religious affiliation code (see IPEDS codebook)
 *   ENRTOT   — total enrollment
 *
 * Sector mapping:
 *   SECTOR 1 (Public 4-year) → type: university
 *   SECTOR 2 (Public 2-year) → type: university
 *   SECTOR 3 (Private nonprofit 4-year) → type: university
 *   SECTOR 4 (Private nonprofit 2-year) → type: university
 *   SECTOR 5 (Private nonprofit less than 2-year) → type: university
 *   SECTOR 6 (Private for-profit 4-year) → filtered (not imported)
 *   SECTOR 7 (Private for-profit 2-year) → filtered (not imported)
 *   SECTOR 9 (Public less than 2-year) → type: university
 *
 * Request payload:
 *   { gcsPath: string, dryRun?: boolean }
 *
 * Security: Admin-only callable.
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { parse } from "csv-parse";
import { v4 as uuidv4 } from "uuid";

import {
    normalizeOrgName,
    geoFromLatLng,
    defaultModulesForType,
    batchUpsert,
    writeOpsRun,
    rejectGooglePlacesSource,
    isOrgSeedEnabled,
} from "./orgImportUtils";
import type { OrgStub } from "./orgSeedModels";

const REGION = "us-central1";

const SOURCE_OWNED_FIELDS = [
    "address",
    "city",
    "state",
    "zip",
    "geo",
    "metadata",
    "normalizedName",
    "type",
    "modules",
    "sourceOwned",
    "sourceUpdatedAt",
];

// IPEDS RELAFFIL religious affiliation codes (partial — most common values)
const IPEDS_RELAFFIL_MAP: Record<string, string> = {
    "22": "American Baptist",
    "24": "Roman Catholic",
    "27": "Church of Christ",
    "28": "Church of God",
    "30": "Evangelical Lutheran Church",
    "33": "Jewish",
    "34": "Latter-day Saints",
    "35": "Lutheran Church Missouri Synod",
    "36": "Mennonite",
    "37": "Methodist",
    "38": "Pentecostal",
    "39": "Presbyterian",
    "40": "Protestant Episcopal",
    "41": "Reformed Church",
    "42": "Seventh-day Adventist",
    "43": "Southern Baptist",
    "44": "United Church of Christ",
    "45": "United Methodist",
    "47": "Other Protestant",
    "48": "Muslim",
    "49": "Interdenominational",
    "57": "Assembly of God",
    "58": "Christian Methodist Episcopal",
    "59": "Church of Brethren",
    "60": "Church of the Nazarene",
    "61": "Ecumenical Christian",
    "62": "Evangelical",
    "63": "Free Methodist",
    "64": "Friends",
    "65": "Grace Brethren",
    "66": "Independent Fundamental",
    "67": "International Church of the Foursquare Gospel",
    "68": "Missionary Church",
    "69": "Missionary",
    "71": "Wisconsin Evangelical Lutheran Synod",
    "72": "Other",
    "74": "Baptist",
    "75": "Christian Reformed",
    "76": "Non-denominational",
    "77": "Wesleyan",
};

// SECTOR values to include (public and private nonprofit only; for-profit filtered out)
const INCLUDED_SECTORS = new Set(["1", "2", "3", "4", "5", "9"]);

export const importIPEDS = onCall(
    { region: REGION, timeoutSeconds: 540, memory: "512MiB" },
    async (request) => {
        if (request.auth?.token?.admin !== true) {
            throw new HttpsError("permission-denied", "Admin privileges required.");
        }

        const flags = await isOrgSeedEnabled();
        if (!flags.orgSeed) {
            logger.warn("[importIPEDS] orgSeedEnabled flag is off — returning early");
            return { skipped: true, reason: "orgSeedEnabled flag is off" };
        }

        const data = request.data as { gcsPath?: string; dryRun?: boolean };
        if (!data.gcsPath || typeof data.gcsPath !== "string") {
            throw new HttpsError("invalid-argument", "gcsPath is required");
        }

        rejectGooglePlacesSource("ipeds");

        const dryRun = data.dryRun === true;
        const { bucketName, filePath } = parseGcsPath(data.gcsPath);

        logger.info(`[importIPEDS] Starting — gcsPath=${data.gcsPath}, dryRun=${dryRun}`);

        const runId = await writeOpsRun({
            job: "importIPEDS",
            source: "ipeds",
            dryRun,
            created: 0,
            updated: 0,
            skipped: 0,
            errors: [],
        });

        const startedAt = Date.now();
        let created = 0;
        let updated = 0;
        let skipped = 0;
        const errors: string[] = [];

        try {
            const bucket = admin.storage().bucket(bucketName);
            const stream = bucket.file(filePath).createReadStream();

            const CHUNK_SIZE = 400;
            let rowBuffer: OrgStub[] = [];

            await new Promise<void>((resolve, reject) => {
                const parser = parse({
                    columns: true,
                    skip_empty_lines: true,
                    trim: true,
                    relax_column_count: true,
                });

                parser.on("readable", async () => {
                    let row: Record<string, string>;
                    while ((row = parser.read()) !== null) {
                        try {
                            const stub = mapIPEDSRow(row);
                            if (stub) {
                                rowBuffer.push(stub);
                            } else {
                                skipped++;
                            }

                            if (rowBuffer.length >= CHUNK_SIZE) {
                                parser.pause();
                                const chunkToFlush = rowBuffer.splice(0, CHUNK_SIZE);
                                try {
                                    const stats = await batchUpsert(chunkToFlush, dryRun);
                                    created += stats.created;
                                    updated += stats.updated;
                                    skipped += stats.skipped;
                                } catch (batchErr) {
                                    errors.push(`Batch error: ${String(batchErr)}`);
                                }
                                parser.resume();
                            }
                        } catch (rowErr) {
                            errors.push(`Row error UNITID=${row.UNITID ?? "?"}: ${String(rowErr)}`);
                            skipped++;
                        }
                    }
                });

                parser.on("error", reject);
                parser.on("end", async () => {
                    if (rowBuffer.length > 0) {
                        try {
                            const stats = await batchUpsert(rowBuffer, dryRun);
                            created += stats.created;
                            updated += stats.updated;
                            skipped += stats.skipped;
                        } catch (batchErr) {
                            errors.push(`Final batch error: ${String(batchErr)}`);
                        }
                        rowBuffer = [];
                    }
                    resolve();
                });

                stream.pipe(parser);
            });
        } catch (err) {
            errors.push(`Stream error: ${String(err)}`);
            logger.error("[importIPEDS] Stream error", { err });
        }

        const durationMs = Date.now() - startedAt;
        logger.info(`[importIPEDS] Finished — created=${created}, updated=${updated}, skipped=${skipped}, errors=${errors.length}`);

        await writeOpsRun({
            id: runId,
            job: "importIPEDS",
            source: "ipeds",
            finishedAt: admin.firestore.Timestamp.now(),
            created,
            updated,
            skipped,
            errors: errors.slice(0, 100),
            dryRun,
        });

        return { runId, created, updated, skipped, errorCount: errors.length, durationMs, dryRun };
    }
);

// ─── Row Mapper ───────────────────────────────────────────────────────────────

function mapIPEDSRow(row: Record<string, string>): OrgStub | null {
    const sourceId = (row.UNITID ?? row.unitid ?? "").trim();
    if (!sourceId) return null;

    const name = (row.INSTNM ?? row.instnm ?? "").trim();
    if (!name) return null;

    // Filter out for-profit institutions (sectors 6, 7)
    const sector = (row.SECTOR ?? row.sector ?? "").trim();
    if (sector && !INCLUDED_SECTORS.has(sector)) {
        return null;
    }

    const address = (row.ADDR ?? row.addr ?? "").trim();
    const city = (row.CITY ?? row.city ?? "").trim();
    const state = (row.STABBR ?? row.stabbr ?? "").trim();
    const zip = (row.ZIP ?? row.zip ?? "").trim();
    const geo = geoFromLatLng(
        row.LATITUDE ?? row.latitude ?? "",
        row.LONGITUDE ?? row.longitude ?? ""
    );

    const relaffilRaw = (row.RELAFFIL ?? row.relaffil ?? "").trim();
    const religiousAffiliation = relaffilRaw && relaffilRaw !== "-1" && relaffilRaw !== "-2"
        ? (IPEDS_RELAFFIL_MAP[relaffilRaw] ?? `Code ${relaffilRaw}`)
        : null;

    const enrtotRaw = (row.ENRTOT ?? row.enrtot ?? "").trim();
    const enrollment = enrtotRaw && enrtotRaw !== "." && enrtotRaw !== "-1" && enrtotRaw !== "-2"
        ? parseInt(enrtotRaw, 10)
        : null;

    const controlRaw = (row.CONTROL ?? row.control ?? "").trim();
    const controlLabel = controlRaw === "1"
        ? "public"
        : controlRaw === "2"
        ? "private_nonprofit"
        : controlRaw === "3"
        ? "private_for_profit"
        : null;

    const now = admin.firestore.Timestamp.now();

    const stub: OrgStub = {
        id: uuidv4(),
        type: "university",
        source: "ipeds",
        sourceId,
        name,
        normalizedName: normalizeOrgName(name),
        address,
        city,
        state,
        zip,
        geo,
        metadata: {
            sector: sector || null,
            control: controlLabel,
            religiousAffiliation,
            religiousAffiliationCode: relaffilRaw || null,
            enrollment: isNaN(enrollment as number) ? null : enrollment,
        },
        modules: defaultModulesForType("university"),
        claimStatus: "unclaimed",
        claimedBy: null,
        billing: null,
        schemaVersion: 1,
        searchIndexed: false,
        sourceOwned: SOURCE_OWNED_FIELDS,
        visibility: "public",
        safetyStatus: "sourceImported",
        createdAt: now,
        updatedAt: now,
    };

    return stub;
}

function parseGcsPath(gcsPath: string): { bucketName: string; filePath: string } {
    const match = gcsPath.match(/^gs:\/\/([^/]+)\/(.+)$/);
    if (!match) {
        throw new HttpsError("invalid-argument", `Invalid gcsPath: ${gcsPath}`);
    }
    return { bucketName: match[1], filePath: match[2] };
}

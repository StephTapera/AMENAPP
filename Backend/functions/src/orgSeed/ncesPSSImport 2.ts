/**
 * ncesPSSImport.ts
 *
 * Cloud Function: `importNcesPSS`
 *
 * Imports K-12 private schools from the NCES Private School Universe Survey (PSS)
 * flat-file CSV, streamed from a Cloud Storage bucket.
 *
 * Data source: https://nces.ed.gov/surveys/pss/
 * Key fields:
 *   PPIN     — unique private school ID (idempotency key)
 *   PINST    — school name
 *   PADDRS   — street address
 *   PCITY, PSTATE, PZIP — location
 *   LATITUDE, LONGITUDE — coordinates
 *   PGROUPLO, PGROUPHI  — grade range
 *   PTOTALE  — total enrollment
 *   P140     — religious affiliation code
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

// ─── PSS Religious Affiliation Code Mapping ───────────────────────────────────
// P140 values reference the NCES religious affiliation code list.
// Codes: 1=Non-sectarian, 2=Catholic, 3=Other religious, 4=Baptist, 5=Methodist,
//        6=Lutheran, 7=Presbyterian, 8=Episcopal, 9=United Church of Christ,
//        10=Calvinist, 11=Quaker, 12=Jewish, 13=Seventh Day Adventist,
//        14=Islamic, 15=National Baptist Convention, 16=Southern Baptist Convention,
//        17=Christian (other), 18=Regular Baptist, 19=Christian Reformed,
//        20=Assembly of God, 21=Salvation Army, 22=Mormon, 23=Mennonite,
//        24=Amish, 25=Christian Science, 26=Evangelical, 27=Pentecostal,
//        28=Brethren, 29=Friends, 30=Unitarian, 31=Greek Orthodox,
//        32=Conservative Jewish, 33=Reform Jewish, 34=Coptic Orthodox,
//        35=Armenian, 36=Apostolic, 37=Buddhist, 38=Hindu, 99=Other religious
const PSS_RELIGIOUS_AFFILIATION_MAP: Record<string, string> = {
    "2": "Catholic",
    "3": "Other Religious",
    "4": "Baptist",
    "5": "Methodist",
    "6": "Lutheran",
    "7": "Presbyterian",
    "8": "Episcopal",
    "9": "United Church of Christ",
    "10": "Calvinist",
    "11": "Quaker",
    "12": "Jewish",
    "13": "Seventh Day Adventist",
    "14": "Islamic",
    "15": "National Baptist Convention",
    "16": "Southern Baptist Convention",
    "17": "Christian",
    "18": "Regular Baptist",
    "19": "Christian Reformed",
    "20": "Assembly of God",
    "21": "Salvation Army",
    "22": "Mormon",
    "23": "Mennonite",
    "24": "Amish",
    "25": "Christian Science",
    "26": "Evangelical",
    "27": "Pentecostal",
    "28": "Brethren",
    "29": "Friends",
    "30": "Unitarian",
    "31": "Greek Orthodox",
    "32": "Conservative Jewish",
    "33": "Reform Jewish",
    "34": "Coptic Orthodox",
    "35": "Armenian",
    "36": "Apostolic",
    "37": "Buddhist",
    "38": "Hindu",
    "99": "Other Religious",
};

export const importNcesPSS = onCall(
    { region: REGION, timeoutSeconds: 540, memory: "512MiB" },
    async (request) => {
        if (request.auth?.token?.admin !== true) {
            throw new HttpsError("permission-denied", "Admin privileges required.");
        }

        const flags = await isOrgSeedEnabled();
        if (!flags.orgSeed) {
            logger.warn("[importNcesPSS] orgSeedEnabled flag is off — returning early");
            return { skipped: true, reason: "orgSeedEnabled flag is off" };
        }

        const data = request.data as { gcsPath?: string; dryRun?: boolean };
        if (!data.gcsPath || typeof data.gcsPath !== "string") {
            throw new HttpsError("invalid-argument", "gcsPath is required");
        }

        rejectGooglePlacesSource("nces_pss");

        const dryRun = data.dryRun === true;
        const { bucketName, filePath } = parseGcsPath(data.gcsPath);

        logger.info(`[importNcesPSS] Starting — gcsPath=${data.gcsPath}, dryRun=${dryRun}`);

        const runId = await writeOpsRun({
            job: "importNcesPSS",
            source: "nces_pss",
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
                            const stub = mapPSSRow(row);
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
                            errors.push(`Row error PPIN=${row.PPIN ?? "?"}: ${String(rowErr)}`);
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
            logger.error("[importNcesPSS] Stream error", { err });
        }

        const durationMs = Date.now() - startedAt;
        logger.info(`[importNcesPSS] Finished — created=${created}, updated=${updated}, skipped=${skipped}, errors=${errors.length}`);

        await writeOpsRun({
            id: runId,
            job: "importNcesPSS",
            source: "nces_pss",
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

function mapPSSRow(row: Record<string, string>): OrgStub | null {
    const sourceId = (row.PPIN ?? row.ppin ?? "").trim();
    if (!sourceId) return null;

    const name = (row.PINST ?? row.pinst ?? "").trim();
    if (!name) return null;

    const address = (row.PADDRS ?? row.paddrs ?? "").trim();
    const city = (row.PCITY ?? row.pcity ?? "").trim();
    const state = (row.PSTATE ?? row.pstate ?? "").trim();
    const zip = (row.PZIP ?? row.pzip ?? "").trim();
    const geo = geoFromLatLng(
        row.LATITUDE ?? row.latitude ?? "",
        row.LONGITUDE ?? row.longitude ?? ""
    );

    const pgrouplo = (row.PGROUPLO ?? row.pgrouplo ?? "").trim();
    const pgrouphi = (row.PGROUPHI ?? row.pgrouphi ?? "").trim();
    const ptotale = (row.PTOTALE ?? row.ptotale ?? "").trim();
    const enrollment = ptotale && ptotale !== "." ? parseInt(ptotale, 10) : null;

    // P140 — religious affiliation code
    const p140 = (row.P140 ?? row.p140 ?? "").trim();
    const denomination = p140 && p140 !== "1" ? (PSS_RELIGIOUS_AFFILIATION_MAP[p140] ?? null) : null;

    const now = admin.firestore.Timestamp.now();

    const stub: OrgStub = {
        id: uuidv4(),
        type: "school",
        source: "nces_pss",
        sourceId,
        name,
        normalizedName: normalizeOrgName(name),
        address,
        city,
        state,
        zip,
        geo,
        metadata: {
            gradeRange: pgrouplo && pgrouphi ? `${pgrouplo}-${pgrouphi}` : null,
            gradeLow: pgrouplo || null,
            gradeHigh: pgrouphi || null,
            enrollment: isNaN(enrollment as number) ? null : enrollment,
            religiousAffiliationCode: p140 || null,
            denomination,
            isReligious: p140 !== "" && p140 !== "1",
        },
        modules: defaultModulesForType("school"),
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
        throw new HttpsError(
            "invalid-argument",
            `Invalid gcsPath: expected gs://bucket/path/file.csv, got ${gcsPath}`
        );
    }
    return { bucketName: match[1], filePath: match[2] };
}

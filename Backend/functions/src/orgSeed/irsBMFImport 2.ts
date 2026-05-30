/**
 * irsBMFImport.ts
 *
 * Cloud Function: `importIRSBMF`
 *
 * Imports religious exempt organizations from the IRS Exempt Organizations
 * Business Master File (BMF) CSV, streamed from Cloud Storage.
 *
 * Data source: https://www.irs.gov/charities-non-profits/exempt-organizations-business-master-file-extract-eo-bmf
 * Key fields:
 *   EIN      — Employer Identification Number (idempotency key)
 *   NAME     — organization name
 *   ICO      — In Care Of (secondary name/contact)
 *   STREET   — street address
 *   CITY, STATE, ZIP — location
 *   ACTIVITY — 3-digit activity codes (pipe/space-separated); codes 001–029 = religious
 *   NTEE_CD  — National Taxonomy of Exempt Entities code
 *
 * Filter logic:
 *   Include row if:
 *     NTEE_CD starts with "X"   (religion-related)
 *     OR any ACTIVITY code is in range "001"–"029"
 *
 * NTEE_CD → OrgType mapping:
 *   X20, X21, X22, X23, X24, X25  → church
 *   X11, X12, X19, X30, X80, X99  → ministry (religious/spiritual support orgs)
 *   X (any other X prefix)         → ministry
 *
 * NOTE: IRS BMF has NO lat/lng. geo is null; metadata.needsGeocoding = true.
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
    defaultModulesForType,
    batchUpsert,
    writeOpsRun,
    rejectGooglePlacesSource,
    isOrgSeedEnabled,
} from "./orgImportUtils";
import type { OrgStub, OrgType } from "./orgSeedModels";

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

// ─── NTEE Mapping ─────────────────────────────────────────────────────────────

/**
 * Maps an NTEE_CD prefix to an OrgType.
 * Full X-series list: https://nccs.urban.org/publication/ntee-codes
 *
 * X20 = Churches, Temples, Mosques, Synagogues → church
 * X21 = Catholic → church
 * X22 = Protestant → church
 * X23 = Jewish → church (synagogue)
 * X24 = Muslim → church (mosque)
 * X25 = Buddhist → church (temple)
 * X30 = Religious Media, Broadcasting → ministry
 * X80 = Religious/Spiritual Orgs → ministry
 * All other X-prefix codes → ministry
 */
function nteeToOrgType(nteeCode: string): OrgType {
    const prefix = nteeCode.substring(0, 3).toUpperCase();

    if (["X20", "X21", "X22", "X23", "X24", "X25"].includes(prefix)) {
        return "church";
    }

    // Any X-prefix org that is not a direct congregation maps to ministry
    return "ministry";
}

/**
 * Describes the denomination/affiliation based on NTEE_CD.
 */
function nteeToLabel(nteeCode: string): string | null {
    const prefix = nteeCode.substring(0, 3).toUpperCase();
    const labels: Record<string, string> = {
        "X20": "Church",
        "X21": "Catholic",
        "X22": "Protestant",
        "X23": "Jewish",
        "X24": "Muslim",
        "X25": "Buddhist",
        "X30": "Religious Media",
        "X80": "Religious/Spiritual Organization",
    };
    return labels[prefix] ?? null;
}

// ─── Activity Code Filter ────────────────────────────────────────────────────

/**
 * IRS BMF ACTIVITY field contains up to 3 space- or comma-separated 3-digit codes.
 * Religious activity codes are 001–029.
 * Returns true if any activity code in the row is in the religious range.
 */
function hasReligiousActivityCode(activityField: string): boolean {
    if (!activityField) return false;
    const codes = activityField.split(/[\s,]+/).filter(Boolean);
    for (const code of codes) {
        const num = parseInt(code, 10);
        if (!isNaN(num) && num >= 1 && num <= 29) {
            return true;
        }
    }
    return false;
}

// ─── Cloud Function ───────────────────────────────────────────────────────────

export const importIRSBMF = onCall(
    { region: REGION, timeoutSeconds: 540, memory: "1GiB" },
    async (request) => {
        if (request.auth?.token?.admin !== true) {
            throw new HttpsError("permission-denied", "Admin privileges required.");
        }

        const flags = await isOrgSeedEnabled();
        if (!flags.orgSeed) {
            logger.warn("[importIRSBMF] orgSeedEnabled flag is off — returning early");
            return { skipped: true, reason: "orgSeedEnabled flag is off" };
        }

        const data = request.data as { gcsPath?: string; dryRun?: boolean };
        if (!data.gcsPath || typeof data.gcsPath !== "string") {
            throw new HttpsError("invalid-argument", "gcsPath is required");
        }

        rejectGooglePlacesSource("irs_bmf");

        const dryRun = data.dryRun === true;
        const { bucketName, filePath } = parseGcsPath(data.gcsPath);

        logger.info(`[importIRSBMF] Starting — gcsPath=${data.gcsPath}, dryRun=${dryRun}`);
        logger.info("[importIRSBMF] NOTE: IRS BMF has no lat/lng. All records will have geo=null and needsGeocoding=true.");

        const runId = await writeOpsRun({
            job: "importIRSBMF",
            source: "irs_bmf",
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

            // IRS BMF is ~1.5M rows — use a slightly smaller chunk size to
            // keep memory pressure low and avoid timeouts between chunks.
            const CHUNK_SIZE = 300;
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
                            const stub = mapBMFRow(row);
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
                            errors.push(`Row error EIN=${row.EIN ?? "?"}: ${String(rowErr)}`);
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
            logger.error("[importIRSBMF] Stream error", { err });
        }

        const durationMs = Date.now() - startedAt;
        logger.info(`[importIRSBMF] Finished — created=${created}, updated=${updated}, skipped=${skipped}, errors=${errors.length}, durationMs=${durationMs}`);

        await writeOpsRun({
            id: runId,
            job: "importIRSBMF",
            source: "irs_bmf",
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

function mapBMFRow(row: Record<string, string>): OrgStub | null {
    // Normalize keys — IRS BMF headers may be uppercase or lowercase
    const ein = (row.EIN ?? row.ein ?? "").trim();
    if (!ein) return null;

    const name = (row.NAME ?? row.name ?? "").trim();
    if (!name) return null;

    const nteeRaw = (row.NTEE_CD ?? row.ntee_cd ?? "").trim();
    const activityRaw = (row.ACTIVITY ?? row.activity ?? "").trim();

    // Apply the filter: must be religion-related
    const isReligiousNtee = nteeRaw.toUpperCase().startsWith("X");
    const isReligiousActivity = hasReligiousActivityCode(activityRaw);

    if (!isReligiousNtee && !isReligiousActivity) {
        return null;
    }

    const orgType = isReligiousNtee ? nteeToOrgType(nteeRaw) : "ministry";
    const nteeLabel = isReligiousNtee ? nteeToLabel(nteeRaw) : null;

    const address = (row.STREET ?? row.street ?? "").trim();
    const city = (row.CITY ?? row.city ?? "").trim();
    const state = (row.STATE ?? row.state ?? "").trim();
    const zip = (row.ZIP ?? row.zip ?? "").trim();

    // ICO = "In Care Of" — secondary contact name, useful for ministry records
    const ico = (row.ICO ?? row.ico ?? "").trim() || null;

    const now = admin.firestore.Timestamp.now();

    const stub: OrgStub = {
        id: uuidv4(),
        type: orgType,
        source: "irs_bmf",
        sourceId: ein,
        name,
        normalizedName: normalizeOrgName(name),
        address,
        city,
        state,
        zip,
        // IRS BMF has no coordinates — geo is null; geocoding deferred
        geo: null,
        metadata: {
            nteeCode: nteeRaw || null,
            nteeLabel,
            activityCodes: activityRaw || null,
            inCareOf: ico,
            needsGeocoding: true,
        },
        modules: defaultModulesForType(orgType),
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

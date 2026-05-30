/**
 * ncesCCDImport.ts
 *
 * Cloud Function: `importNcesCCD`
 *
 * Imports K-12 public schools from the NCES Common Core of Data (CCD)
 * flat-file CSV, streamed from a Cloud Storage bucket.
 *
 * Data source: https://nces.ed.gov/ccd/files.asp
 * Key fields:
 *   NCESSCH  — unique school ID (idempotency key)
 *   SCHNAM   — school name
 *   LSTREET1 — address
 *   LCITY, LSTATE, LZIP — location
 *   LATCOD, LONCOD   — lat/lng
 *   GSLO, GSHI       — grade range (e.g. "KG"–"12")
 *   MEMBER           — total enrollment
 *   ULOCALE          — urban-centric locale code
 *
 * Request payload:
 *   { gcsPath: string, dryRun?: boolean }
 *   gcsPath: e.g. "gs://my-bucket/nces/ccd_2023.csv"
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

// Fields the import pipeline owns and may update on subsequent runs
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

export const importNcesCCD = onCall(
    { region: REGION, timeoutSeconds: 540, memory: "512MiB" },
    async (request) => {
        // ── Auth gate ───────────────────────────────────────────────────────
        if (request.auth?.token?.admin !== true) {
            throw new HttpsError("permission-denied", "Admin privileges required.");
        }

        // ── Feature flag gate ────────────────────────────────────────────────
        const flags = await isOrgSeedEnabled();
        if (!flags.orgSeed) {
            logger.warn("[importNcesCCD] orgSeedEnabled flag is off — returning early");
            return { skipped: true, reason: "orgSeedEnabled flag is off" };
        }

        // ── Input validation ────────────────────────────────────────────────
        const data = request.data as { gcsPath?: string; dryRun?: boolean };
        if (!data.gcsPath || typeof data.gcsPath !== "string") {
            throw new HttpsError("invalid-argument", "gcsPath is required (e.g. 'gs://bucket/path/file.csv')");
        }

        // Guard against Google Places abuse
        rejectGooglePlacesSource("nces_ccd");

        const dryRun = data.dryRun === true;
        const { bucketName, filePath } = parseGcsPath(data.gcsPath);

        logger.info(`[importNcesCCD] Starting — gcsPath=${data.gcsPath}, dryRun=${dryRun}`);

        const runId = await writeOpsRun({
            job: "importNcesCCD",
            source: "nces_ccd",
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
            const file = bucket.file(filePath);
            const stream = file.createReadStream();

            // Buffer rows into chunks for batch upsert
            const CHUNK_SIZE = 400;
            let rowBuffer: OrgStub[] = [];

            await new Promise<void>((resolve, reject) => {
                const parser = parse({
                    columns: true,       // Use first row as column headers
                    skip_empty_lines: true,
                    trim: true,
                    relax_column_count: true,
                });

                parser.on("readable", async () => {
                    let row: Record<string, string>;
                    while ((row = parser.read()) !== null) {
                        try {
                            const stub = mapCCDRow(row);
                            if (stub) {
                                rowBuffer.push(stub);
                            } else {
                                skipped++;
                            }

                            if (rowBuffer.length >= CHUNK_SIZE) {
                                // Pause parser while we flush
                                parser.pause();
                                const chunkToFlush = rowBuffer.splice(0, CHUNK_SIZE);
                                try {
                                    const stats = await batchUpsert(chunkToFlush, dryRun);
                                    created += stats.created;
                                    updated += stats.updated;
                                    skipped += stats.skipped;
                                } catch (batchErr) {
                                    const msg = `Batch upsert error: ${String(batchErr)}`;
                                    errors.push(msg);
                                    logger.error(`[importNcesCCD] ${msg}`);
                                }
                                parser.resume();
                            }
                        } catch (rowErr) {
                            const msg = `Row parse error for NCESSCH=${row.NCESSCH ?? "?"}: ${String(rowErr)}`;
                            errors.push(msg);
                            skipped++;
                        }
                    }
                });

                parser.on("error", (err) => reject(err));
                parser.on("end", async () => {
                    // Flush remaining rows
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
            const msg = `Stream error: ${String(err)}`;
            errors.push(msg);
            logger.error(`[importNcesCCD] ${msg}`);
        }

        const durationMs = Date.now() - startedAt;
        logger.info(`[importNcesCCD] Finished — created=${created}, updated=${updated}, skipped=${skipped}, errors=${errors.length}, durationMs=${durationMs}`);

        await writeOpsRun({
            id: runId,
            job: "importNcesCCD",
            source: "nces_ccd",
            finishedAt: admin.firestore.Timestamp.now(),
            created,
            updated,
            skipped,
            errors: errors.slice(0, 100), // cap stored errors
            dryRun,
        });

        return { runId, created, updated, skipped, errorCount: errors.length, durationMs, dryRun };
    }
);

// ─── Row Mapper ───────────────────────────────────────────────────────────────

function mapCCDRow(row: Record<string, string>): OrgStub | null {
    const sourceId = (row.NCESSCH ?? row.ncessch ?? "").trim();
    if (!sourceId) return null;

    const name = (row.SCHNAM ?? row.schnam ?? "").trim();
    if (!name) return null;

    const address = (row.LSTREET1 ?? row.lstreet1 ?? "").trim();
    const city = (row.LCITY ?? row.lcity ?? "").trim();
    const state = (row.LSTATE ?? row.lstate ?? "").trim();
    const zip = (row.LZIP ?? row.lzip ?? "").trim();
    const geo = geoFromLatLng(
        row.LATCOD ?? row.latcod ?? "",
        row.LONCOD ?? row.loncod ?? ""
    );

    // Grade range metadata
    const gslo = (row.GSLO ?? row.gslo ?? "").trim();
    const gshi = (row.GSHI ?? row.gshi ?? "").trim();
    const memberRaw = (row.MEMBER ?? row.member ?? "").trim();
    const enrollment = memberRaw && memberRaw !== "." ? parseInt(memberRaw, 10) : null;
    const locale = (row.ULOCALE ?? row.ulocale ?? "").trim() || null;

    const now = admin.firestore.Timestamp.now();

    const stub: OrgStub = {
        id: uuidv4(),
        type: "school",
        source: "nces_ccd",
        sourceId,
        name,
        normalizedName: normalizeOrgName(name),
        address,
        city,
        state,
        zip,
        geo,
        metadata: {
            gradeRange: gslo && gshi ? `${gslo}-${gshi}` : null,
            gradeLow: gslo || null,
            gradeHigh: gshi || null,
            enrollment: isNaN(enrollment as number) ? null : enrollment,
            locale: locale,
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

// ─── GCS Path Parser ──────────────────────────────────────────────────────────

function parseGcsPath(gcsPath: string): { bucketName: string; filePath: string } {
    const match = gcsPath.match(/^gs:\/\/([^/]+)\/(.+)$/);
    if (!match) {
        throw new HttpsError(
            "invalid-argument",
            `Invalid gcsPath format. Expected: gs://bucket-name/path/to/file.csv, got: ${gcsPath}`
        );
    }
    return { bucketName: match[1], filePath: match[2] };
}

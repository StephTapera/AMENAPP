/**
 * orgImportUtils.ts
 *
 * Shared utilities for all org seed import Cloud Functions.
 *
 * Key contracts:
 *  - batchUpsert  — idempotent upsert keyed by (source, sourceId), 499-op batches
 *  - Field ownership — claimed orgs: only `sourceOwned` fields may be overwritten
 *  - Google Places guard — any request carrying source "google_places" is rejected
 *  - writeOpsRun — writes a complete OpsRun record to `orgOpsRuns`
 */

import * as admin from "firebase-admin";
import * as FirebaseFirestore from "@google-cloud/firestore";
import { logger } from "firebase-functions/v2";
import type { OrgStub, OpsRun, OrgType } from "./orgSeedModels";

const db = admin.firestore();

// ─── FIELD CONSTANTS ──────────────────────────────────────────────────────────

/**
 * Fields that are always considered "user-owned" after an org is claimed.
 * Imports MUST NEVER overwrite these fields on a claimed/pending/verified org.
 */
const USER_OWNED_FIELDS: ReadonlySet<string> = new Set([
    "name",
    "description",
    "website",
    "phone",
    "bannerConfig",
    "spaceDefaults",
]);

/**
 * Fields that the import pipeline may update regardless of claim status.
 * These are source-data fields that improve the record quality.
 */
const SOURCE_OWNED_BASE: readonly string[] = [
    "address",
    "city",
    "state",
    "zip",
    "geo",
    "metadata",
    "normalizedName",
    "sourceUpdatedAt",
    "updatedAt",
];

/** Maximum Firestore batch size (hard limit is 500; we use 499 for safety). */
const MAX_BATCH_OPS = 499;

/** How many times to retry a failed batch commit before giving up. */
const MAX_BATCH_RETRIES = 3;

// ─── NAME NORMALIZER ──────────────────────────────────────────────────────────

/**
 * Produces a normalized form of an org name suitable for deduplication and
 * fuzzy search: lowercase, stripped of punctuation, collapsed whitespace.
 *
 * Examples:
 *   "St. Paul's Lutheran Church, Inc." → "st pauls lutheran church inc"
 *   "EINSTEIN MIDDLE SCHOOL #42"       → "einstein middle school 42"
 */
export function normalizeOrgName(name: string): string {
    return name
        .toLowerCase()
        // Remove most punctuation but keep alphanumerics and spaces
        .replace(/[^a-z0-9\s]/g, " ")
        .replace(/\s+/g, " ")
        .trim();
}

// ─── GEO POINT PARSER ────────────────────────────────────────────────────────

/**
 * Parses a lat/lng pair from CSV strings (which may be empty, ".", or
 * out-of-range) and returns a Firestore GeoPoint, or null on failure.
 *
 * Valid ranges: lat [-90, 90], lng [-180, 180].
 * Zero-zero coordinates (i.e. Gulf of Guinea) are treated as invalid for
 * US-domestic datasets.
 */
export function geoFromLatLng(lat: string, lng: string): FirebaseFirestore.GeoPoint | null {
    const latNum = parseFloat(lat);
    const lngNum = parseFloat(lng);

    if (!isFinite(latNum) || !isFinite(lngNum)) return null;
    if (latNum < -90 || latNum > 90) return null;
    if (lngNum < -180 || lngNum > 180) return null;
    // Reject (0, 0) — no US org is in the Gulf of Guinea
    if (latNum === 0 && lngNum === 0) return null;

    return new admin.firestore.GeoPoint(latNum, lngNum);
}

// ─── DEFAULT MODULES ─────────────────────────────────────────────────────────

/**
 * Returns the default module list for a given org type.
 * Mirrors the Swift `AmenOrganizationType.defaultModules` computed property
 * in AmenOrganizationIdentityModels.swift.
 */
export function defaultModulesForType(type: OrgType): string[] {
    switch (type) {
        case "church":
            return [
                "heroBanner",
                "identityHeader",
                "spacesPreview",
                "eventsPreview",
                "smartNotesPreview",
                "mediaPreview",
                "claimCTA",
                "safetyTransparency",
            ];
        case "school":
        case "university":
        case "campusGroup":
            return [
                "heroBanner",
                "identityHeader",
                "spacesPreview",
                "eventsPreview",
                "schoolNotesPreview",
                "claimCTA",
                "safetyTransparency",
            ];
        case "business":
            return [
                "heroBanner",
                "identityHeader",
                "spacesPreview",
                "eventsPreview",
                "adminTools",
                "claimCTA",
                "safetyTransparency",
            ];
        case "nonprofit":
        case "ministry":
        case "bibleStudy":
        case "creatorCommunity":
        case "communityGroup":
        default:
            return [
                "heroBanner",
                "identityHeader",
                "spacesPreview",
                "eventsPreview",
                "smartNotesPreview",
                "claimCTA",
                "safetyTransparency",
            ];
    }
}

// ─── GOOGLE PLACES GUARD ──────────────────────────────────────────────────────

/**
 * Throws if the caller is trying to bulk-store Google Places data.
 * Per product policy, Google Places data must never be written to Firestore
 * except for the `place_id` field on an existing org doc.
 */
export function rejectGooglePlacesSource(source: string): void {
    if (source === "google_places") {
        throw new Error(
            "POLICY_VIOLATION: Google Places data must never be bulk-stored in Firestore. " +
            "Only place_id may be stored on an existing org document."
        );
    }
}

// ─── IDEMPOTENT BATCH UPSERT ─────────────────────────────────────────────────

export interface UpsertStats {
    created: number;
    updated: number;
    skipped: number;
}

/**
 * Idempotently upserts a batch of OrgStub records into the `organizations`
 * collection.
 *
 * Idempotency key: (source, sourceId) — a compound query fetches existing docs.
 *
 * Field ownership rules:
 *   - If the existing doc has claimStatus "unclaimed": all fields are overwritten.
 *   - If the existing doc has claimStatus "pending" | "claimed" | "verified":
 *     only `sourceOwned` fields (minus USER_OWNED_FIELDS) are updated.
 *
 * Batching: commits at most MAX_BATCH_OPS (499) operations per batch.
 * Each batch is retried up to MAX_BATCH_RETRIES times on transient errors.
 *
 * @param docs   Array of OrgStub records to upsert.
 * @param dryRun When true, validates and counts but does not write to Firestore.
 */
export async function batchUpsert(
    docs: OrgStub[],
    dryRun: boolean
): Promise<UpsertStats> {
    const stats: UpsertStats = { created: 0, updated: 0, skipped: 0 };
    if (docs.length === 0) return stats;

    const orgsRef = db.collection("organizations");

    // ── Build a (source → sourceId → existing doc) lookup ──────────────────
    // We query in chunks of 30 because Firestore `in` has a max of 30 values.
    const sourceIdChunks = chunk(
        docs.map((d) => d.sourceId),
        30
    );

    const existingBySourceId = new Map<string, FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>>();

    for (const idChunk of sourceIdChunks) {
        const snap = await orgsRef
            .where("source", "==", docs[0].source)
            .where("sourceId", "in", idChunk)
            .get();
        for (const docSnap of snap.docs) {
            existingBySourceId.set(docSnap.data().sourceId as string, docSnap);
        }
    }

    // ── Prepare write operations ────────────────────────────────────────────
    type WriteOp =
        | { kind: "create"; ref: FirebaseFirestore.DocumentReference; data: FirebaseFirestore.DocumentData }
        | { kind: "update"; ref: FirebaseFirestore.DocumentReference; data: Partial<FirebaseFirestore.DocumentData> };

    const ops: WriteOp[] = [];

    for (const stub of docs) {
        const existing = existingBySourceId.get(stub.sourceId);

        if (!existing) {
            // New record — create
            const ref = orgsRef.doc(stub.id);
            ops.push({ kind: "create", ref, data: stub as unknown as FirebaseFirestore.DocumentData });
        } else {
            const existingData = existing.data();
            const claimStatus = existingData.claimStatus as string;

            if (claimStatus === "unclaimed") {
                // Full overwrite of all import-managed fields
                const updateData: Partial<FirebaseFirestore.DocumentData> = {
                    ...buildSourceUpdate(stub),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                };
                ops.push({ kind: "update", ref: existing.ref, data: updateData });
            } else {
                // Claimed / pending / verified: only update sourceOwned fields
                // that are NOT in USER_OWNED_FIELDS
                const allowedUpdates = (existingData.sourceOwned as string[] | undefined) ?? SOURCE_OWNED_BASE;
                const safeFields = allowedUpdates.filter((f) => !USER_OWNED_FIELDS.has(f));

                const updateData: Partial<FirebaseFirestore.DocumentData> = {};
                for (const field of safeFields) {
                    const val = (stub as unknown as Record<string, unknown>)[field];
                    if (val !== undefined) {
                        updateData[field] = val;
                    }
                }
                updateData.updatedAt = admin.firestore.FieldValue.serverTimestamp();

                if (Object.keys(updateData).length <= 1) {
                    // Only updatedAt would be written — skip
                    stats.skipped++;
                    continue;
                }
                ops.push({ kind: "update", ref: existing.ref, data: updateData });
            }
        }
    }

    if (dryRun) {
        // Count what would happen without writing
        for (const op of ops) {
            if (op.kind === "create") stats.created++;
            else stats.updated++;
        }
        return stats;
    }

    // ── Commit in batches of MAX_BATCH_OPS ─────────────────────────────────
    const opChunks = chunk(ops, MAX_BATCH_OPS);

    for (const opChunk of opChunks) {
        await commitBatchWithRetry(opChunk, stats);
    }

    return stats;
}

/** Commits a batch of write operations with exponential backoff retry. */
async function commitBatchWithRetry(
    ops: Array<
        | { kind: "create"; ref: FirebaseFirestore.DocumentReference; data: FirebaseFirestore.DocumentData }
        | { kind: "update"; ref: FirebaseFirestore.DocumentReference; data: Partial<FirebaseFirestore.DocumentData> }
    >,
    stats: UpsertStats
): Promise<void> {
    let attempt = 0;

    while (attempt < MAX_BATCH_RETRIES) {
        attempt++;
        try {
            const batch = db.batch();
            for (const op of ops) {
                if (op.kind === "create") {
                    batch.set(op.ref, op.data);
                } else {
                    batch.update(op.ref, op.data);
                }
            }
            await batch.commit();

            // Count after successful commit
            for (const op of ops) {
                if (op.kind === "create") stats.created++;
                else stats.updated++;
            }
            return;
        } catch (err) {
            const isLastAttempt = attempt >= MAX_BATCH_RETRIES;
            if (isLastAttempt) {
                logger.error("[orgImportUtils] Batch commit failed after retries", { err, opsCount: ops.length });
                throw err;
            }
            const backoffMs = 200 * Math.pow(2, attempt - 1);
            logger.warn(`[orgImportUtils] Batch commit attempt ${attempt} failed — retrying in ${backoffMs}ms`, { err });
            await sleep(backoffMs);
        }
    }
}

/** Extracts the fields that an import run should write on an update. */
function buildSourceUpdate(stub: OrgStub): Record<string, unknown> {
    return {
        address: stub.address,
        city: stub.city,
        state: stub.state,
        zip: stub.zip,
        geo: stub.geo,
        metadata: stub.metadata,
        normalizedName: stub.normalizedName,
        type: stub.type,
        modules: stub.modules,
        sourceOwned: stub.sourceOwned,
    };
}

// ─── OPS RUN WRITER ──────────────────────────────────────────────────────────

/**
 * Writes (or updates) an OpsRun document to the `orgOpsRuns` collection.
 * Returns the document ID so the caller can update it when the run finishes.
 *
 * @param run  Partial OpsRun. If `id` is omitted, a new document is created.
 * @returns    The document ID.
 */
export async function writeOpsRun(run: Partial<OpsRun>): Promise<string> {
    const runsRef = db.collection("orgOpsRuns");

    if (run.id) {
        const ref = runsRef.doc(run.id);
        await ref.set(
            {
                ...run,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
        );
        return run.id;
    }

    const ref = runsRef.doc();
    await ref.set({
        id: ref.id,
        job: run.job ?? "unknown",
        source: run.source ?? "unknown",
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
        created: run.created ?? 0,
        updated: run.updated ?? 0,
        skipped: run.skipped ?? 0,
        errors: run.errors ?? [],
        dryRun: run.dryRun ?? false,
        ...run,
    });
    return ref.id;
}

// ─── FEATURE FLAG GATE ────────────────────────────────────────────────────────

/**
 * Reads `config/featureFlags` from Firestore and returns whether
 * `orgSeedEnabled` is true. Defaults to false (flag-off = safe default for
 * seed pipeline which has no safety consequences if skipped).
 *
 * Also checks `orgPlatformEnabled` which gates the broader org platform.
 */
export async function isOrgSeedEnabled(): Promise<{ orgSeed: boolean; orgPlatform: boolean }> {
    try {
        const snap = await db.collection("config").doc("featureFlags").get();
        if (!snap.exists) {
            logger.warn("[orgImportUtils] config/featureFlags not found — defaulting flags to false");
            return { orgSeed: false, orgPlatform: false };
        }
        const data = snap.data() ?? {};
        return {
            orgSeed: (data.orgSeedEnabled as boolean | undefined) ?? false,
            orgPlatform: (data.orgPlatformEnabled as boolean | undefined) ?? false,
        };
    } catch (err) {
        logger.error("[orgImportUtils] Failed to read config/featureFlags", { err });
        return { orgSeed: false, orgPlatform: false };
    }
}

// ─── INTERNAL HELPERS ────────────────────────────────────────────────────────

function chunk<T>(arr: T[], size: number): T[][] {
    const chunks: T[][] = [];
    for (let i = 0; i < arr.length; i += size) {
        chunks.push(arr.slice(i, i + size));
    }
    return chunks;
}

function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

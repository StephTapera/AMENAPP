/**
 * orgSeedModels.ts
 *
 * TypeScript interfaces that mirror the Swift AmenOrganization* models in
 * AMENAPP/AmenOrganizationIdentityModels.swift.
 *
 * These are the canonical shapes written to Firestore by the seed import
 * Cloud Functions. Any changes here MUST stay in sync with the Swift models.
 *
 * IMPORTANT: `billing` and `claimedBy` are deliberately typed as null here.
 * Seed imports always produce unclaimed stubs; those fields are only
 * populated via the claim flow, not by any import function.
 */

import * as FirebaseFirestore from "@google-cloud/firestore";

// ─── Enumerations ─────────────────────────────────────────────────────────────

/**
 * Maps to Swift `AmenOrganizationType`.
 * NOTE: 'business', 'bibleStudy', 'creatorCommunity', 'communityGroup' are
 * valid Swift cases but are not produced by bulk-import sources. They are
 * listed here for completeness and for the deduplication merge path.
 */
export type OrgType =
    | "church"
    | "school"
    | "university"
    | "campusGroup"
    | "business"
    | "nonprofit"
    | "ministry"
    | "bibleStudy"
    | "creatorCommunity"
    | "communityGroup";

/** Maps to Swift `AmenOrganizationSource`. */
export type OrgSource =
    | "nces_ccd"
    | "nces_pss"
    | "ipeds"
    | "irs_bmf"
    | "census_geocoder"
    | "osm_static_extract"
    | "user_created"
    | "partner_import";

/** Maps to Swift `AmenOrganizationClaimStatus`. */
export type ClaimStatus = "unclaimed" | "pending" | "claimed" | "verified" | "rejected";

// ─── Org Stub ─────────────────────────────────────────────────────────────────

/**
 * The canonical org stub document written to the `organizations` collection
 * by bulk seed import functions. All seed stubs start with:
 *   - claimStatus: "unclaimed"
 *   - claimedBy: null
 *   - billing: null
 *   - schemaVersion: 1
 *
 * `sourceOwned` lists the field names that the source importer is allowed to
 * overwrite on subsequent runs. User-owned fields are NEVER in this list.
 */
export interface OrgStub {
    /** Auto-generated Firestore document ID. */
    id: string;
    type: OrgType;
    source: OrgSource;
    /**
     * The primary key from the source dataset (NCESSCH, PPIN, UNITID, EIN).
     * Used as the idempotency key together with `source`.
     */
    sourceId: string;
    name: string;
    /** Lowercase, no punctuation, collapsed whitespace — for dedup / search. */
    normalizedName: string;
    address: string;
    city: string;
    state: string;
    zip: string;
    /** GeoPoint. May be null for IRS BMF records that have no lat/lng. */
    geo: FirebaseFirestore.GeoPoint | null;
    website?: string;
    phone?: string;
    /**
     * Source-specific extras (grade range, enrollment, NTEE code, sector, etc.).
     * Typed loosely so each importer can add its own fields without schema drift.
     */
    metadata: Record<string, unknown>;
    /** Module IDs from AmenOrganizationProfileModuleID — default set for this type. */
    modules: string[];
    claimStatus: ClaimStatus;
    /** Always null for seed stubs. Populated by the claim flow. */
    claimedBy: null;
    /** Always null for seed stubs. Populated by the billing flow. */
    billing: null;
    /** Must be 1 for all records produced by this pipeline version. */
    schemaVersion: 1;
    /** Set to true once the record has been indexed in Algolia. */
    searchIndexed: boolean;
    /**
     * List of top-level field names that the import pipeline may overwrite on
     * subsequent runs. Fields NOT in this list are never touched by imports once
     * the org has been claimed.
     */
    sourceOwned: string[];
    /** Firestore server timestamp. */
    createdAt: FirebaseFirestore.Timestamp;
    /** Firestore server timestamp. */
    updatedAt: FirebaseFirestore.Timestamp;
    /** Standard AMEN visibility gate. Seed stubs are "public". */
    visibility: "public";
    /** Safety gate. Seed stubs are "sourceImported". */
    safetyStatus: "sourceImported";
}

// ─── Ops Run ──────────────────────────────────────────────────────────────────

/**
 * Written to the `orgOpsRuns` collection at the end of every import or
 * deduplication run. Provides a full audit trail of every pipeline execution.
 */
export interface OpsRun {
    /** Auto-generated Firestore document ID. */
    id: string;
    /** Human-readable job name, e.g. "importNcesCCD". */
    job: string;
    /** Source identifier, e.g. "nces_ccd". */
    source: string;
    startedAt: FirebaseFirestore.Timestamp;
    finishedAt?: FirebaseFirestore.Timestamp;
    /** Number of new documents created. */
    created: number;
    /** Number of existing documents updated. */
    updated: number;
    /** Number of rows skipped (validation failures, Google Places rejection, etc.). */
    skipped: number;
    /** Array of error messages encountered during the run. */
    errors: string[];
    /** When true, the run was a dry-run: no writes were performed. */
    dryRun: boolean;
}

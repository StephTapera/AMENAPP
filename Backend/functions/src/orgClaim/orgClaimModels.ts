/**
 * orgClaimModels.ts
 *
 * Shared types for the AMEN Organization Claim system.
 *
 * Security invariants (enforced by CFs, not these types):
 *  - claimStatus, source, sourceId are server-only fields.
 *  - Approved owners may write ONLY: name, description, website, phone,
 *    bannerConfig, spaceDefaults, updatedAt (enforced by Firestore rules).
 *  - ClaimRequest docs are append-only via Admin SDK. Direct client writes
 *    are blocked (allow write: if false in Firestore rules).
 */

import * as admin from "firebase-admin";

// ─── Org claim status — mirrors AmenOrganizationClaimStatus in Swift ──────────

export type ClaimStatus = "unclaimed" | "pending" | "claimed" | "verified" | "rejected";

// ─── Verification method ─────────────────────────────────────────────────────

export type VerificationMethod = "domain_match" | "manual_review";

// ─── Claim request document (organizations/{orgId}/claims/{claimId}) ─────────

export interface ClaimRequest {
    id: string;
    orgId: string;
    requestedBy: string;               // Firebase UID — derived from request.auth, never client data
    verificationEmail: string;         // empty string if manualReview
    verificationMethod: VerificationMethod;
    status: "pending" | "approved" | "rejected";
    guardianScore?: number;            // raw GUARDIAN safety score (0–100)
    guardianVerdict?: "pass" | "flag"; // GUARDIAN decision
    reviewedBy?: string;               // admin UID on approve/reject
    reviewedAt?: admin.firestore.Timestamp;
    createdAt: admin.firestore.Timestamp;
    updatedAt: admin.firestore.Timestamp;
}

// ─── Firestore org document (organizations/{orgId}) fields touched by claim CFs

export interface OrgClaimFields {
    claimStatus: ClaimStatus;
    claimedBy: string | null;
    ownerUid: string | null;
    updatedAt: admin.firestore.FieldValue;
}

// ─── User subcollection record (users/{uid}/organizationClaims/{orgId}) ───────

export interface UserOrgClaimRecord {
    orgId: string;
    claimId: string;
    orgName: string;
    status: "pending" | "approved" | "rejected";
    verificationMethod: VerificationMethod;
    createdAt: admin.firestore.Timestamp;
}

// ─── CF return payloads ───────────────────────────────────────────────────────

export interface RequestOrgClaimResult {
    success: true;
    autoVerified: boolean;
    claimId: string;
}

export interface ApproveClaimResult {
    success: true;
    orgId: string;
    claimId: string;
}

export interface RejectClaimResult {
    success: true;
    claimId: string;
}

export interface CreateOrgStubResult {
    success: true;
    orgId: string;
    claimId: string;
}

// ─── Org type union — mirrors AmenOrganizationType in Swift ──────────────────

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

export const VALID_ORG_TYPES = new Set<OrgType>([
    "church", "school", "university", "campusGroup", "business",
    "nonprofit", "ministry", "bibleStudy", "creatorCommunity", "communityGroup",
]);

// ─── Rate limit config for org claim operations ──────────────────────────────

export const ORG_CLAIM_RATE_LIMIT = {
    name: "org_claim_1hr",
    windowMs: 3_600_000,    // 1 hour
    maxCalls: 5,
} as const;

export const ORG_STUB_RATE_LIMIT = {
    name: "org_stub_1hr",
    windowMs: 3_600_000,
    maxCalls: 5,
} as const;

// ─── Maximum pending claims per user ─────────────────────────────────────────

export const MAX_PENDING_CLAIMS_PER_USER = 3;

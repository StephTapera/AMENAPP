// connect/guardianLink.ts
// AMEN Connect V1 — Verified Guardian Link primitive (spec §5.1). THE safety foundation.
// Region: us-east1. Contracts: ../contracts/connect.
//
// LAW (spec §5.1–§5.2):
//   • A guardian→child relationship is VERIFIED, never self-asserted. requestGuardianLink only
//     ever creates a `pending` link; promotion to `verified` is a separate server/staff path.
//   • No child PII flows to any account without an ACTIVE verified link to THAT child.
//   • getChildCheckInStatus returns 403 (permission-denied) unless such a link exists.
//   • Allergy/medical data is guardian-only and is NEVER written to logs/analytics.

import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

import {
  RequestGuardianLinkRequest,
  RequestGuardianLinkResponse,
  GetChildCheckInStatusRequest,
  ChildStatus,
  GuardianLink,
} from "../contracts/connect";

// Composite doc id mirrors follows_index / blockedUsers convention (firestore.rules:129).
function linkId(guardianUid: string, childId: string): string {
  return `${guardianUid}_${childId}`;
}

/**
 * Returns the guardian's ACTIVE verified link to `childId`, or throws permission-denied.
 * This is the single gate every child read must pass through.
 */
async function assertVerifiedGuardian(
  db: admin.firestore.Firestore,
  guardianUid: string,
  childId: string
): Promise<GuardianLink> {
  const snap = await db.collection("guardianLinks").doc(linkId(guardianUid, childId)).get();
  const data = snap.data() as GuardianLink | undefined;
  if (!snap.exists || !data || data.status !== "verified") {
    // Fail-closed: missing, pending, or revoked → no child data.
    throw new functions.HttpsError("permission-denied", "No verified guardian link to this child.");
  }
  return data;
}

// ── requestGuardianLink ─────────────────────────────────────────────
// Always creates/returns a PENDING link. Verification is intentionally NOT done here.

export const requestGuardianLink = functions.onCall({ enforceAppCheck: true, region: "us-east1", timeoutSeconds: 15, memory: "256MiB" }, async (request): Promise<RequestGuardianLinkResponse> => {
    if (!request.auth?.uid) {
      throw new functions.HttpsError("unauthenticated", "Must be signed in.");
    }
    const guardianUid = request.auth.uid;
    const data = request.data as RequestGuardianLinkRequest;

    if (!data?.churchId || !data?.childId || !data?.evidence?.kind) {
      throw new functions.HttpsError("invalid-argument", "churchId, childId, and evidence are required.");
    }
    const allowedEvidence = ["staff_attested", "pickup_code", "invite_acceptance"];
    if (!allowedEvidence.includes(data.evidence.kind)) {
      throw new functions.HttpsError("invalid-argument", "Unrecognized evidence kind.");
    }

    const db = admin.firestore();
    const id = linkId(guardianUid, data.childId);
    const ref = db.collection("guardianLinks").doc(id);

    // Idempotent: never downgrade an already-verified link; never let the client set status.
    const existing = await ref.get();
    if (existing.exists && (existing.data() as GuardianLink).status === "verified") {
      return { linkId: id, status: "pending" }; // contract: always returns pending shape
    }

    const now = new Date().toISOString();
    const link: GuardianLink = {
      id,
      churchId: data.churchId,
      guardianUid,
      childId: data.childId,
      status: "pending",            // SERVER-controlled; verification is a separate path
      verifiedAt: null,
      createdAt: now,
    };
    // Store evidence kind only (not raw secrets) for the staff/verification review trail.
    await ref.set(
      { ...link, evidenceKind: data.evidence.kind, updatedAt: now },
      { merge: true }
    );

    return { linkId: id, status: "pending" };
  }
);

// ── getChildCheckInStatus ───────────────────────────────────────────
// 403 unless an ACTIVE verified guardian link exists. Guardian-only fields, never logged.

export const getChildCheckInStatus = functions.onCall({ enforceAppCheck: true, region: "us-east1", timeoutSeconds: 15, memory: "256MiB" }, async (request): Promise<ChildStatus> => {
    if (!request.auth?.uid) {
      throw new functions.HttpsError("unauthenticated", "Must be signed in.");
    }
    const guardianUid = request.auth.uid;
    const data = request.data as GetChildCheckInStatusRequest;
    if (!data?.childId) {
      throw new functions.HttpsError("invalid-argument", "childId is required.");
    }

    const db = admin.firestore();
    // GATE — throws permission-denied if not a verified guardian of this child.
    const link = await assertVerifiedGuardian(db, guardianUid, data.childId);

    // Child record is keyed {churchId}_{childId}; churchId comes from the verified link.
    const childRef = db.collection("children").doc(`${link.churchId}_${data.childId}`);
    const childSnap = await childRef.get();
    if (!childSnap.exists) {
      // Verified guardian, but no child record yet — return a safe, empty status.
      return { childId: data.childId, checkedIn: false };
    }
    const child = childSnap.data() as Record<string, unknown>;

    // Check-in state is read from denormalized fields on the child record (written by the
    // QR + pickup-code check-in CF in a later wave). Fail-closed: absent → not checked in.
    const checkIn = (child.currentCheckIn ?? {}) as Record<string, unknown>;

    // NOTE: allergies are SENSITIVE PII — returned to the verified guardian only, never logged.
    return {
      childId: data.childId,
      checkedIn: checkIn.checkedIn === true,
      ageGroup: typeof child.ageGroup === "string" ? child.ageGroup : undefined,
      building: typeof checkIn.building === "string" ? checkIn.building : undefined,
      pickupCode: typeof checkIn.pickupCode === "string" ? checkIn.pickupCode : undefined,
      allergies: Array.isArray(child.allergies) ? (child.allergies as string[]) : undefined,
    };
  }
);

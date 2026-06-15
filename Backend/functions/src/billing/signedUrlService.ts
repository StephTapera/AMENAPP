/**
 * signedUrlService.ts
 *
 * Generates Firebase Storage signed URLs for paid Catalog content.
 * Entitlement is verified server-side before any URL is issued.
 *
 * Security invariants:
 *   - Caller must be authenticated (Firebase Auth).
 *   - Entitlement is re-checked on every call (no client-side cache trusted).
 *   - Signed URLs expire: default 60 minutes, max 24 hours (1440 minutes).
 *   - Every access is logged to /catalogAccessLog/{uid}/{accessId} for audit.
 *   - Watermarking: PDF and video watermarking is not yet implemented in the
 *     signing layer. TODO(watermark): before producing the URL, invoke a
 *     Cloud Run job that injects the user's uid/email as a visible or
 *     steganographic watermark in the asset copy before signing.
 *
 * Deploy: us-east1 only.
 * Add to docs/FUNCTION_INVENTORY.md Interim Region Table before deploy.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import * as logger from "firebase-functions/logger";

// ─── Constants ────────────────────────────────────────────────────────────────

const db = getFirestore();
const REGION = "us-east1";

const DEFAULT_DURATION_MINUTES = 60;
const MAX_DURATION_MINUTES = 1440; // 24 hours absolute ceiling

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Returns the storage path for a work's primary content asset.
 * Convention: catalog/{creatorId}/{workId}/content/{filename}
 * The primary asset filename is stored on the work document as `storagePath`.
 */
async function getWorkStoragePath(workId: string): Promise<string | null> {
  try {
    const doc = await db.collection("works").doc(workId).get();
    if (!doc.exists) return null;
    const data = doc.data()!;
    const storagePath = data["storagePath"] as string | undefined;
    return storagePath ?? null;
  } catch {
    return null;
  }
}

/**
 * Returns the visibility and creatorId for a published work.
 * Returns null if the work does not exist, is soft-deleted, or not published.
 */
async function getWorkMeta(
  workId: string
): Promise<{ visibility: string; creatorId: string } | null> {
  try {
    const doc = await db.collection("works").doc(workId).get();
    if (!doc.exists) return null;
    const data = doc.data()!;
    if (data["deletedAt"] != null) return null;
    if (data["reviewState"] !== "published") return null;
    return {
      visibility: data["visibility"] as string,
      creatorId: data["creatorId"] as string,
    };
  } catch {
    return null;
  }
}

/**
 * Checks whether the uid has an active paid catalog entitlement.
 * Reads users/{uid}/entitlements/catalog — fails closed.
 */
async function hasPaidEntitlement(uid: string): Promise<boolean> {
  try {
    const doc = await db
      .collection("users")
      .doc(uid)
      .collection("entitlements")
      .doc("catalog")
      .get();
    if (!doc.exists) return false;
    const data = doc.data()!;
    const active = data["active"] === true;
    if (!active) return false;
    const expiresAt = data["expiresAt"];
    if (expiresAt && expiresAt.toDate() < new Date()) return false;
    return true;
  } catch {
    return false;
  }
}

/**
 * Checks whether a uid follows a given creator.
 */
async function followsCreator(uid: string, creatorId: string): Promise<boolean> {
  try {
    const followId = `${uid}_${creatorId}`;
    const doc = await db.collection("follows").doc(followId).get();
    return doc.exists;
  } catch {
    return false;
  }
}

/**
 * Checks whether the uid shares the same orgId as the work.
 * Reads from the user's profile (orgId field), not custom claims.
 */
async function sameOrg(uid: string, workCreatorId: string): Promise<boolean> {
  try {
    const [userDoc, creatorDoc] = await Promise.all([
      db.collection("users").doc(uid).get(),
      db.collection("users").doc(workCreatorId).get(),
    ]);
    const userOrg = userDoc.data()?.["orgId"] as string | undefined;
    const creatorOrg = creatorDoc.data()?.["orgId"] as string | undefined;
    return !!(userOrg && creatorOrg && userOrg === creatorOrg);
  } catch {
    return false;
  }
}

// ─── getSignedUrl ─────────────────────────────────────────────────────────────

interface GetSignedUrlInput {
  workId: string;
  durationMinutes?: number;
}

interface GetSignedUrlOutput {
  url: string;
  expiresAt: string; // ISO 8601
  workId: string;
}

/**
 * Issues a time-limited Firebase Storage signed URL for a paid Catalog asset.
 *
 * Access rules (server-enforced):
 *   - public works: any authenticated user
 *   - followers works: authenticated + follows the creator
 *   - paid_members works: authenticated + active catalog entitlement
 *   - organization works: authenticated + same org as creator
 *   - private works: creator only
 *
 * Duration: default 60 min, max 24 hours.
 * Every issuance is logged to /catalogAccessLog for audit.
 *
 * TODO(watermark): Before signing, invoke a Cloud Run watermarking job to
 *   embed uid/email into PDF or video assets so leaked URLs can be traced.
 *   Until implemented, access is still logged and urls are time-limited.
 */
export const getSignedUrl = onCall(
  { region: REGION, secrets: [] },
  async (req): Promise<GetSignedUrlOutput> => {
    if (!req.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const uid = req.auth.uid;
    const data = req.data as GetSignedUrlInput;

    if (!data?.workId) {
      throw new HttpsError("invalid-argument", "workId is required.");
    }

    const requestedMinutes = data.durationMinutes ?? DEFAULT_DURATION_MINUTES;
    const durationMinutes = Math.min(
      Math.max(1, Math.round(requestedMinutes)),
      MAX_DURATION_MINUTES
    );

    // 1. Load work metadata (published + not deleted)
    const meta = await getWorkMeta(data.workId);
    if (!meta) {
      throw new HttpsError("not-found", "Work not found or not published.");
    }

    // 2. Enforce visibility gate (server-side, not client-trusted)
    const { visibility, creatorId } = meta;
    let accessGranted = false;

    if (uid === creatorId) {
      // Creator always has access to their own works
      accessGranted = true;
    } else if (visibility === "public") {
      accessGranted = true;
    } else if (visibility === "followers") {
      accessGranted = await followsCreator(uid, creatorId);
    } else if (visibility === "paid_members") {
      accessGranted = await hasPaidEntitlement(uid);
    } else if (visibility === "organization") {
      accessGranted = await sameOrg(uid, creatorId);
    }
    // private: only creator — handled above; everyone else denied

    if (!accessGranted) {
      logger.info("getSignedUrl: access denied", { uid, workId: data.workId, visibility });
      throw new HttpsError("permission-denied", "You do not have access to this content.");
    }

    // 3. Resolve storage path
    const storagePath = await getWorkStoragePath(data.workId);
    if (!storagePath) {
      logger.error("getSignedUrl: work has no storagePath", { workId: data.workId });
      throw new HttpsError("not-found", "Content asset not found for this work.");
    }

    // 4. Generate signed URL
    const bucket = getStorage().bucket();
    const file = bucket.file(storagePath);
    const expiresMs = durationMinutes * 60 * 1000;
    const expiresAt = new Date(Date.now() + expiresMs);

    let signedUrlArray: [string];
    try {
      [signedUrlArray] = await file.getSignedUrl({
        action: "read",
        expires: expiresAt,
      }) as unknown as [[string]];
    } catch (err) {
      logger.error("getSignedUrl: failed to generate signed URL", { workId: data.workId, err });
      throw new HttpsError("internal", "Could not generate content URL. Please try again.");
    }

    const signedUrl = Array.isArray(signedUrlArray) ? signedUrlArray[0] : signedUrlArray as unknown as string;

    // 5. Audit log — async, do not await (non-blocking)
    db.collection("catalogAccessLog")
      .doc(uid)
      .collection("accesses")
      .add({
        workId: data.workId,
        creatorId,
        visibility,
        durationMinutes,
        expiresAt: expiresAt.toISOString(),
        accessedAt: FieldValue.serverTimestamp(),
        // TODO(watermark): add watermarkJobId here once implemented
      })
      .catch((err) => {
        logger.warn("getSignedUrl: failed to write audit log", { uid, workId: data.workId, err });
      });

    logger.info("getSignedUrl: signed URL issued", {
      uid,
      workId: data.workId,
      visibility,
      durationMinutes,
    });

    return {
      url: signedUrl,
      expiresAt: expiresAt.toISOString(),
      workId: data.workId,
    };
  }
);

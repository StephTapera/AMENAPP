/**
 * EvidencePreservationService.ts
 *
 * Secure evidence preservation for Amen Safety OS.
 * For severe/critical cases (CSAM, trafficking, sextortion, blackmail, etc.),
 * evidence must be preserved BEFORE any content is deleted, so it can be
 * provided to law enforcement or NCMEC.
 *
 * Evidence preservation is:
 *   - Immutable once written (Firestore rules prevent updates/deletes)
 *   - Access-controlled (only admin/trustSafetyReviewer can read)
 *   - Timestamped with server timestamps (not client-provided)
 *   - Deduplicated by contentHash
 *
 * Data model:
 *   evidenceRecords/{evidenceId}
 *     contentId: string
 *     contentType: string
 *     authorUid: string
 *     harmCategoryId: string
 *     contentSnapshot: string  (text) | null
 *     storageUriSnapshot?: string  (media)
 *     preservedStoragePath?: string  (quarantine copy in gs://amen-evidence/)
 *     contentHash: string
 *     reportIds: string[]
 *     externalCaseReference?: string  (NCMEC CyberTip number, etc.)
 *     preservedAt: Timestamp
 *     preservedBy: string  ("server" | "admin:{uid}")
 *     chainOfCustody: ChainOfCustodyEntry[]
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { requiresEvidencePreservation, AMEN_SAFETY_POLICY_VERSION } from "./AmenSafetyPolicy";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const storage = admin.storage();

const EVIDENCE_BUCKET = process.env.EVIDENCE_STORAGE_BUCKET ?? "amen-evidence";

// ─── Types ────────────────────────────────────────────────────────────────────

export interface ChainOfCustodyEntry {
  action: "preserved" | "accessed" | "provided_to_law_enforcement" | "provided_to_ncmec" | "sealed";
  actorUid: string;
  note?: string;
  timestamp: admin.firestore.Timestamp;
}

export interface EvidenceRecord {
  evidenceId: string;
  contentId: string;
  contentType: string;
  authorUid: string;
  harmCategoryId: string;
  contentSnapshot?: string;
  storageUriSnapshot?: string;
  preservedStoragePath?: string;
  contentHash: string;
  reportIds: string[];
  externalCaseReference?: string;
  preservedAt: admin.firestore.Timestamp;
  preservedBy: string;
  chainOfCustody: ChainOfCustodyEntry[];
  policyVersion: string;
}

// ─── Core Preservation ────────────────────────────────────────────────────────

export interface PreserveEvidenceRequest {
  contentId: string;
  contentType: string;
  authorUid: string;
  harmCategoryId: string;
  contentSnapshot?: string;     // Text content
  storageUri?: string;          // gs:// URI for media evidence
  reportIds?: string[];
  preservedBy?: string;
}

export async function preserveEvidence(req: PreserveEvidenceRequest): Promise<string> {
  if (!requiresEvidencePreservation(req.harmCategoryId)) {
    logger.info(`[EvidencePreservationService] harmCategory=${req.harmCategoryId} does not require preservation.`);
    return "";
  }

  // Compute content hash for deduplication
  const hashInput = [req.contentId, req.authorUid, req.contentSnapshot ?? req.storageUri ?? ""].join("|");
  const contentHash = crypto.createHash("sha256").update(hashInput).digest("hex");

  // Deduplication: don't create duplicate evidence records
  const existing = await db.collection("evidenceRecords")
    .where("contentHash", "==", contentHash)
    .limit(1)
    .get();

  if (!existing.empty) {
    logger.info(`[EvidencePreservationService] Evidence already preserved evidenceId=${existing.docs[0].id}`);
    return existing.docs[0].id;
  }

  let preservedStoragePath: string | undefined;

  // Copy media to isolated evidence bucket if storageUri is provided
  if (req.storageUri?.startsWith("gs://")) {
    preservedStoragePath = await copyToEvidenceBucket(req.storageUri, req.contentId, req.authorUid);
  }

  const now = admin.firestore.Timestamp.now();
  const evidenceRef = db.collection("evidenceRecords").doc();

  const record: Omit<EvidenceRecord, "evidenceId"> = {
    contentId: req.contentId,
    contentType: req.contentType,
    authorUid: req.authorUid,
    harmCategoryId: req.harmCategoryId,
    contentSnapshot: req.contentSnapshot ?? undefined,
    storageUriSnapshot: req.storageUri ?? undefined,
    preservedStoragePath,
    contentHash,
    reportIds: req.reportIds ?? [],
    preservedAt: now,
    preservedBy: req.preservedBy ?? "server",
    policyVersion: AMEN_SAFETY_POLICY_VERSION,
    chainOfCustody: [
      {
        action: "preserved",
        actorUid: req.preservedBy ?? "server",
        note: `Auto-preserved for harmCategory=${req.harmCategoryId}`,
        timestamp: now,
      },
    ],
  };

  await evidenceRef.set(record);
  logger.info(`[EvidencePreservationService] Evidence preserved evidenceId=${evidenceRef.id} harm=${req.harmCategoryId}`);

  return evidenceRef.id;
}

async function copyToEvidenceBucket(sourceUri: string, contentId: string, authorUid: string): Promise<string> {
  try {
    const sourceBucket = sourceUri.replace("gs://", "").split("/")[0];
    const sourcePath = sourceUri.replace(`gs://${sourceBucket}/`, "");
    const destPath = `evidence/${authorUid}/${contentId}/${Date.now()}_${sourcePath.split("/").pop()}`;

    await storage.bucket(sourceBucket).file(sourcePath).copy(
      storage.bucket(EVIDENCE_BUCKET).file(destPath)
    );

    return `gs://${EVIDENCE_BUCKET}/${destPath}`;
  } catch (err) {
    logger.error("[EvidencePreservationService] Failed to copy media to evidence bucket.", err);
    return "";
  }
}

// ─── Chain of Custody Updates ─────────────────────────────────────────────────

async function appendChainOfCustody(
  evidenceId: string,
  entry: Omit<ChainOfCustodyEntry, "timestamp">
): Promise<void> {
  const ref = db.collection("evidenceRecords").doc(evidenceId);
  await ref.update({
    chainOfCustody: admin.firestore.FieldValue.arrayUnion({
      ...entry,
      timestamp: admin.firestore.Timestamp.now(),
    }),
  });
}

// ─── Callables (Admin/T&S Only) ───────────────────────────────────────────────

function requireTrustSafety(token: Record<string, unknown>): void {
  if (!token.admin && !token.trustSafetyReviewer) {
    throw new HttpsError("permission-denied", "Trust & Safety access required.");
  }
}

/**
 * preserveEvidenceCallable
 * Called by backend triggers and admin tools to preserve evidence.
 * Not callable by regular users.
 */
export const preserveEvidenceCallable = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<PreserveEvidenceRequest>): Promise<{ evidenceId: string }> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
    requireTrustSafety(request.auth.token as Record<string, unknown>);

    const evidenceId = await preserveEvidence({
      ...request.data,
      preservedBy: `admin:${request.auth.uid}`,
    });
    return { evidenceId };
  }
);

/**
 * getEvidenceRecord
 * Returns a single evidence record for T&S review.
 */
export const getEvidenceRecord = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{ evidenceId: string }>): Promise<EvidenceRecord | null> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
    requireTrustSafety(request.auth.token as Record<string, unknown>);

    const { evidenceId } = request.data;
    if (!evidenceId) throw new HttpsError("invalid-argument", "evidenceId required.");

    const doc = await db.collection("evidenceRecords").doc(evidenceId).get();
    if (!doc.exists) return null;

    // Log access in chain of custody
    await appendChainOfCustody(evidenceId, {
      action: "accessed",
      actorUid: request.auth.uid,
    });

    return { evidenceId: doc.id, ...doc.data() } as EvidenceRecord;
  }
);

/**
 * markEvidenceProvided
 * Records in chain of custody when evidence is provided to law enforcement or NCMEC.
 */
export const markEvidenceProvided = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{
    evidenceId: string;
    providedTo: "law_enforcement" | "ncmec";
    externalCaseReference?: string;
    note?: string;
  }>): Promise<{ success: boolean }> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
    requireTrustSafety(request.auth.token as Record<string, unknown>);

    const { evidenceId, providedTo, externalCaseReference, note } = request.data;
    if (!evidenceId || !providedTo) throw new HttpsError("invalid-argument", "evidenceId and providedTo required.");

    const action: ChainOfCustodyEntry["action"] =
      providedTo === "ncmec" ? "provided_to_ncmec" : "provided_to_law_enforcement";

    await appendChainOfCustody(evidenceId, {
      action,
      actorUid: request.auth.uid,
      note,
    });

    if (externalCaseReference) {
      await db.collection("evidenceRecords").doc(evidenceId).update({ externalCaseReference });
    }

    return { success: true };
  }
);

/**
 * searchEvidenceByUser
 * Returns all evidence records for a given author UID (admin/T&S only).
 */
export const searchEvidenceByUser = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{ authorUid: string; limit?: number }>): Promise<{ records: unknown[] }> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
    requireTrustSafety(request.auth.token as Record<string, unknown>);

    const { authorUid, limit: limitCount = 20 } = request.data;
    if (!authorUid) throw new HttpsError("invalid-argument", "authorUid required.");

    const snap = await db.collection("evidenceRecords")
      .where("authorUid", "==", authorUid)
      .orderBy("preservedAt", "desc")
      .limit(Math.min(limitCount, 50))
      .get();

    return {
      records: snap.docs.map((d) => ({ evidenceId: d.id, ...d.data() })),
    };
  }
);

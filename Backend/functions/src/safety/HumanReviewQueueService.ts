/**
 * HumanReviewQueueService.ts
 *
 * Human review queue management for Amen Safety OS.
 *
 * All content flagged as "needs_human_review" or "escalated" is routed here.
 * Moderators claim items, review them, and record a decision. SLA deadlines
 * are tracked and alerts are fired when items breach their initial-response
 * target from safetyOpsPolicy.ts.
 *
 * Queue items lifecycle:
 *   open → claimed → resolved (approved | removed | escalated_further)
 *
 * Data model:
 *   humanReviewQueue/{itemId}
 *     status: "open" | "claimed" | "resolved"
 *     claimedByUid?: string
 *     claimedAt?: Timestamp
 *     resolvedAt?: Timestamp
 *     resolution?: "approve" | "remove" | "escalate_further" | "false_positive"
 *     resolutionNote?: string
 *     priority: 1 | 2 | 3 | 4
 *     queue: SafetyOpsQueue
 *     dueAt: Timestamp
 *     contentType: string
 *     contentId?: string
 *     authorUid?: string
 *     harmCategoryId?: string
 *     evidence?: Record<string, unknown>
 *     policyVersion: string
 *     createdAt: Timestamp
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {
  safetyOpsPlanFor,
  safetyOpsDueAt,
  SafetyOpsQueue,
} from "../safetyOpsPolicy";
import { AMEN_SAFETY_POLICY_VERSION } from "./AmenSafetyPolicy";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Types ────────────────────────────────────────────────────────────────────

export type QueueItemStatus = "open" | "claimed" | "resolved";
export type QueueResolution = "approve" | "remove" | "escalate_further" | "false_positive";

export interface QueueItem {
  itemId: string;
  status: QueueItemStatus;
  claimedByUid?: string;
  claimedAt?: admin.firestore.Timestamp;
  resolvedAt?: admin.firestore.Timestamp;
  resolution?: QueueResolution;
  resolutionNote?: string;
  priority: 1 | 2 | 3 | 4;
  queue: SafetyOpsQueue;
  dueAt: admin.firestore.Timestamp;
  contentType: string;
  contentId?: string;
  authorUid?: string;
  harmCategoryId?: string;
  policyVersion: string;
  createdAt: admin.firestore.Timestamp;
}

// ─── Enqueue ──────────────────────────────────────────────────────────────────

export interface EnqueueRequest {
  contentType: string;
  contentId?: string;
  authorUid?: string;
  harmCategoryId?: string;
  harmSeverity?: string;
  evidence?: Record<string, unknown>;
  sourceDecisionId?: string;
}

export async function enqueueForHumanReview(req: EnqueueRequest): Promise<string> {
  const plan = safetyOpsPlanFor(req.harmCategoryId ?? "general", req.harmSeverity ?? "medium");
  const dueAt = safetyOpsDueAt(Date.now(), plan.initialResponseMinutes);

  const ref = db.collection("humanReviewQueue").doc();
  await ref.set({
    status: "open",
    priority: plan.priority,
    queue: plan.queue,
    dueAt: admin.firestore.Timestamp.fromDate(dueAt),
    contentType: req.contentType,
    contentId: req.contentId ?? null,
    authorUid: req.authorUid ?? null,
    harmCategoryId: req.harmCategoryId ?? null,
    evidence: req.evidence ?? null,
    sourceDecisionId: req.sourceDecisionId ?? null,
    preserveEvidence: plan.preserveEvidence,
    dualApprovalRequired: plan.dualApprovalRequired,
    externalPartner: plan.externalPartner,
    policyVersion: AMEN_SAFETY_POLICY_VERSION,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  logger.info(`[HumanReviewQueueService] Enqueued itemId=${ref.id} queue=${plan.queue} priority=${plan.priority}`);
  return ref.id;
}

// ─── Callable: Claim Item ─────────────────────────────────────────────────────

export const claimReviewItem = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{ itemId: string }>): Promise<{ success: boolean }> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
    const token = request.auth.token as Record<string, unknown>;
    if (!token.admin && !token.moderator && !token.trustSafetyReviewer) {
      throw new HttpsError("permission-denied", "Trust & Safety reviewer access required.");
    }

    const { itemId } = request.data;
    if (!itemId) throw new HttpsError("invalid-argument", "itemId required.");

    const ref = db.collection("humanReviewQueue").doc(itemId);

    await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      if (!doc.exists) throw new HttpsError("not-found", "Queue item not found.");
      const data = doc.data() as QueueItem;
      if (data.status !== "open") throw new HttpsError("failed-precondition", "Item is not open.");

      tx.update(ref, {
        status: "claimed",
        claimedByUid: request.auth!.uid,
        claimedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return { success: true };
  }
);

// ─── Callable: Resolve Item ───────────────────────────────────────────────────

export const resolveReviewItem = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{
    itemId: string;
    resolution: QueueResolution;
    resolutionNote?: string;
  }>): Promise<{ success: boolean }> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
    const token = request.auth.token as Record<string, unknown>;
    if (!token.admin && !token.moderator && !token.trustSafetyReviewer) {
      throw new HttpsError("permission-denied", "Trust & Safety reviewer access required.");
    }

    const { itemId, resolution, resolutionNote } = request.data;
    if (!itemId || !resolution) throw new HttpsError("invalid-argument", "itemId and resolution required.");

    const VALID_RESOLUTIONS: QueueResolution[] = ["approve", "remove", "escalate_further", "false_positive"];
    if (!VALID_RESOLUTIONS.includes(resolution)) {
      throw new HttpsError("invalid-argument", `Invalid resolution. Must be one of: ${VALID_RESOLUTIONS.join(", ")}`);
    }

    const ref = db.collection("humanReviewQueue").doc(itemId);

    await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      if (!doc.exists) throw new HttpsError("not-found", "Queue item not found.");

      const data = doc.data() as QueueItem;
      if (data.status === "resolved") throw new HttpsError("failed-precondition", "Item is already resolved.");

      // For dualApprovalRequired items, need two different reviewers
      if (data.dualApprovalRequired && resolution === "approve") {
        const firstReviewer = data.claimedByUid;
        if (firstReviewer && firstReviewer === request.auth!.uid) {
          throw new HttpsError(
            "failed-precondition",
            "Dual approval required: a second reviewer must approve this item."
          );
        }
      }

      tx.update(ref, {
        status: "resolved",
        resolution,
        resolutionNote: resolutionNote ?? null,
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
        resolvedByUid: request.auth!.uid,
      });
    });

    // Post-resolution side effects
    const doc = (await ref.get()).data() as QueueItem;
    await handleResolution(doc, resolution);

    return { success: true };
  }
);

async function handleResolution(item: QueueItem, resolution: QueueResolution): Promise<void> {
  if (!item.contentId || !item.contentType) return;

  if (resolution === "remove") {
    // Update content moderationStatus to "removed_after_publish"
    const collectionMap: Record<string, string> = {
      post: "posts",
      comment: "comments",
      dm: "messages",
    };
    const collection = collectionMap[item.contentType];
    if (collection && item.contentId) {
      try {
        await db.collection(collection).doc(item.contentId).set(
          { moderationStatus: "removed_after_publish" },
          { merge: true }
        );
      } catch (err) {
        logger.warn("[HumanReviewQueueService] Failed to update content moderationStatus.", err);
      }
    }

    // Issue a strike
    if (item.authorUid && item.harmCategoryId) {
      const { issueStrike } = await import("./TrustAndStrikeService");
      await issueStrike(item.authorUid, item.harmCategoryId, item.contentId, `moderator_review:${item.itemId}`);
    }
  }

  if (resolution === "approve" && item.contentId) {
    const collectionMap: Record<string, string> = {
      post: "posts",
      comment: "comments",
    };
    const collection = collectionMap[item.contentType];
    if (collection) {
      try {
        await db.collection(collection).doc(item.contentId).set(
          { moderationStatus: "approved" },
          { merge: true }
        );
      } catch { /* ignore */ }
    }
  }
}

// ─── Callable: Get Queue (Moderator) ─────────────────────────────────────────

export const getReviewQueue = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{
    queue?: SafetyOpsQueue;
    status?: QueueItemStatus;
    limit?: number;
  }>): Promise<{ items: unknown[]; total: number }> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
    const token = request.auth.token as Record<string, unknown>;
    if (!token.admin && !token.moderator && !token.trustSafetyReviewer) {
      throw new HttpsError("permission-denied", "Trust & Safety reviewer access required.");
    }

    const { queue, status = "open", limit: limitCount = 50 } = request.data;

    let query = db.collection("humanReviewQueue")
      .where("status", "==", status)
      .orderBy("priority", "asc")
      .orderBy("dueAt", "asc")
      .limit(Math.min(limitCount, 100));

    if (queue) {
      query = db.collection("humanReviewQueue")
        .where("status", "==", status)
        .where("queue", "==", queue)
        .orderBy("priority", "asc")
        .orderBy("dueAt", "asc")
        .limit(Math.min(limitCount, 100));
    }

    const snap = await query.get();
    return {
      items: snap.docs.map((d) => ({ itemId: d.id, ...d.data() })),
      total: snap.size,
    };
  }
);

// ─── Scheduled: SLA Breach Alert ─────────────────────────────────────────────

/**
 * Every 15 minutes, check for queue items that have breached their SLA.
 * Alert moderators by writing to a moderatorAlerts collection.
 */
export const checkQueueSLABreaches = onSchedule(
  { schedule: "every 15 minutes", timeoutSeconds: 60 },
  async () => {
    const now = admin.firestore.Timestamp.now();

    const breached = await db.collection("humanReviewQueue")
      .where("status", "in", ["open", "claimed"])
      .where("dueAt", "<", now)
      .where("slaAlertSent", "!=", true)
      .limit(50)
      .get();

    if (breached.empty) return;

    const batch = db.batch();
    for (const doc of breached.docs) {
      const data = doc.data() as QueueItem;

      // Write alert to moderatorAlerts
      const alertRef = db.collection("moderatorAlerts").doc();
      batch.set(alertRef, {
        type: "sla_breach",
        itemId: doc.id,
        queue: data.queue,
        priority: data.priority,
        harmCategoryId: data.harmCategoryId ?? null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Mark alert sent to prevent repeat alerts
      batch.update(doc.ref, { slaAlertSent: true });
    }

    await batch.commit();
    logger.warn(`[HumanReviewQueueService] SLA breach: ${breached.size} items overdue.`);
  }
);

/**
 * ingestion/reviewWorkflow.ts
 *
 * State machine for the Catalog Work review lifecycle.
 *
 * State machine: imported → draft → review → approved → published
 *
 * CRITICAL INVARIANTS:
 *  - publishWork() requires confirmed === true (HUMAN GATE). If false, throws.
 *  - approveWork() is admin-only (adminId must have admin custom claim)
 *  - No work ever moves to 'published' visibility without confirmed === true
 *  - Visibility stays 'private' until creator explicitly publishes with confirmation
 */

import * as admin from "firebase-admin";
import type { Work, WorkReviewState } from "./providers/types";

const db = () => admin.firestore();

// ─── State machine ──────────────────────────────────────────────────────────

const VALID_TRANSITIONS: Record<WorkReviewState, WorkReviewState[]> = {
  imported: ["draft"],
  draft: ["review"],
  review: ["approved", "draft"], // Can be sent back to draft
  approved: ["published", "review"], // Can be sent back to review
  published: [], // Terminal state — use deleteWork to remove
};

function assertValidTransition(
  currentState: WorkReviewState,
  targetState: WorkReviewState
): void {
  const allowed = VALID_TRANSITIONS[currentState] ?? [];
  if (!allowed.includes(targetState)) {
    throw new Error(
      `invalid_state_transition: ${currentState} → ${targetState}. Allowed: ${allowed.join(", ") || "none"}`
    );
  }
}

// ─── importWork ─────────────────────────────────────────────────────────────

/**
 * Save a raw provider item as a new Work in Firestore.
 * Always: reviewState='imported', visibility='private'.
 * Deduplicates by (creatorId, sourceProviderId, externalId).
 */
export async function importWork(
  creatorId: string,
  work: Omit<Work, "id">
): Promise<string> {
  if (work.reviewState !== "imported") {
    throw new Error("importWork: reviewState must be 'imported'");
  }
  if (work.visibility !== "private") {
    throw new Error("importWork: visibility must be 'private'");
  }

  const firestore = db();

  // Dedup check
  if (work.sourceProviderId && work.externalId) {
    const existing = await firestore
      .collection("works")
      .where("creatorId", "==", creatorId)
      .where("sourceProviderId", "==", work.sourceProviderId)
      .where("externalId", "==", work.externalId)
      .limit(1)
      .get();

    if (!existing.empty) {
      // Already imported — return existing ID
      return existing.docs[0].id;
    }
  }

  const ref = firestore.collection("works").doc();
  await ref.set({
    ...work,
    id: ref.id,
    creatorId,
    reviewState: "imported",
    visibility: "private",
    createdAt: admin.firestore.Timestamp.now(),
    updatedAt: admin.firestore.Timestamp.now(),
    deletedAt: null,
  });

  return ref.id;
}

// ─── submitForReview ────────────────────────────────────────────────────────

/**
 * Creator submits a work for review. Moves: imported → draft or draft → review.
 * Does NOT change visibility.
 */
export async function submitForReview(
  workId: string,
  creatorId: string
): Promise<void> {
  const firestore = db();
  const ref = firestore.collection("works").doc(workId);

  await firestore.runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    if (!snap.exists) throw new Error("work_not_found");

    const data = snap.data() as Work;
    if (data.creatorId !== creatorId) throw new Error("access_denied");
    if (data.deletedAt) throw new Error("work_is_deleted");

    const current = data.reviewState;
    // Allow imported → draft, or draft → review
    let target: WorkReviewState;
    if (current === "imported") {
      target = "draft";
    } else if (current === "draft") {
      target = "review";
    } else {
      throw new Error(`submitForReview: cannot submit from state '${current}'`);
    }

    assertValidTransition(current, target);

    txn.update(ref, {
      reviewState: target,
      updatedAt: admin.firestore.Timestamp.now(),
    });
  });
}

// ─── approveWork ────────────────────────────────────────────────────────────

/**
 * Admin approves a work. Moves: review → approved. ADMIN GATE.
 * Visibility stays 'private' until creator publishes.
 */
export async function approveWork(
  workId: string,
  adminId: string
): Promise<void> {
  // Verify admin custom claim
  const adminRecord = await admin.auth().getUser(adminId);
  const isAdmin = adminRecord.customClaims?.["admin"] === true;
  if (!isAdmin) {
    throw new Error("access_denied: admin claim required for approveWork");
  }

  const firestore = db();
  const ref = firestore.collection("works").doc(workId);

  await firestore.runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    if (!snap.exists) throw new Error("work_not_found");

    const data = snap.data() as Work;
    if (data.deletedAt) throw new Error("work_is_deleted");

    assertValidTransition(data.reviewState, "approved");

    txn.update(ref, {
      reviewState: "approved",
      approvedBy: adminId,
      approvedAt: admin.firestore.Timestamp.now(),
      updatedAt: admin.firestore.Timestamp.now(),
    });
  });
}

// ─── publishWork ────────────────────────────────────────────────────────────

/**
 * Creator publishes an approved work. HUMAN GATE — confirmed MUST be true.
 * If confirmed === false, this function throws unconditionally.
 * Only works in 'approved' state may be published.
 * Visibility is set by the creator at publish time (defaults to 'public').
 */
export async function publishWork(
  workId: string,
  creatorId: string,
  confirmed: boolean,
  visibility: "public" | "followers" | "paid_members" | "organization" = "public"
): Promise<void> {
  // HUMAN GATE — must be explicitly confirmed
  if (confirmed !== true) {
    throw new Error(
      "publishWork: confirmed must be true. This is a human gate — the creator must explicitly confirm publishing."
    );
  }

  const firestore = db();
  const ref = firestore.collection("works").doc(workId);

  await firestore.runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    if (!snap.exists) throw new Error("work_not_found");

    const data = snap.data() as Work;
    if (data.creatorId !== creatorId) throw new Error("access_denied");
    if (data.deletedAt) throw new Error("work_is_deleted");

    assertValidTransition(data.reviewState, "published");

    txn.update(ref, {
      reviewState: "published",
      visibility,
      publishedAt: admin.firestore.Timestamp.now(),
      updatedAt: admin.firestore.Timestamp.now(),
    });
  });
}

// ─── advanceWorkReviewState ─────────────────────────────────────────────────

/**
 * Convenience callable: advances work from current state to next valid state.
 * For creator use: imported → draft, draft → review.
 * Publish requires explicit publishWork() call with confirmed=true.
 */
export async function advanceWorkReviewState(
  workId: string,
  creatorId: string
): Promise<{ newState: WorkReviewState }> {
  const firestore = db();
  const ref = firestore.collection("works").doc(workId);
  const snap = await ref.get();
  if (!snap.exists) throw new Error("work_not_found");

  const data = snap.data() as Work;
  if (data.creatorId !== creatorId) throw new Error("access_denied");
  if (data.deletedAt) throw new Error("work_is_deleted");

  const current = data.reviewState;

  // advanceWorkReviewState does NOT publish — that requires explicit confirmation
  if (current === "approved") {
    throw new Error(
      "approved_works_require_explicit_publish_confirmation: call publishWork() with confirmed=true"
    );
  }

  if (current === "published") {
    throw new Error("work_already_published");
  }

  await submitForReview(workId, creatorId);

  const updated = await ref.get();
  return { newState: (updated.data() as Work).reviewState };
}

// ─── rejectWork ─────────────────────────────────────────────────────────────

/**
 * Admin sends a work back to draft from review. Admin-only.
 */
export async function rejectWork(
  workId: string,
  adminId: string,
  reason: string
): Promise<void> {
  const adminRecord = await admin.auth().getUser(adminId);
  const isAdmin = adminRecord.customClaims?.["admin"] === true;
  if (!isAdmin) {
    throw new Error("access_denied: admin claim required for rejectWork");
  }

  const firestore = db();
  const ref = firestore.collection("works").doc(workId);

  await firestore.runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    if (!snap.exists) throw new Error("work_not_found");
    const data = snap.data() as Work;
    if (data.reviewState !== "review" && data.reviewState !== "approved") {
      throw new Error("work_not_in_reviewable_state");
    }

    txn.update(ref, {
      reviewState: "draft",
      rejectedBy: adminId,
      rejectionReason: reason,
      rejectedAt: admin.firestore.Timestamp.now(),
      updatedAt: admin.firestore.Timestamp.now(),
    });
  });
}

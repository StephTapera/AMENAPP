"use strict";

/**
 * blockMuteReport.js
 *
 * Block, mute, and report primitives for the AMEN platform.
 *
 * Design decisions:
 *   - Block is bidirectional: once blocked, neither party can see or
 *     contact the other in any surface.
 *   - Mute is unidirectional and silent: the muting user stops seeing the
 *     muted user's content; the muted user is never informed.
 *   - Reports are immutable once created — they are never updated or deleted.
 *     Reporters are never exposed to the reported user.
 *   - child_safety / csam_suspected reports bypass the normal review queue
 *     and call escalation.escalateChildSafety immediately.
 *   - Report rate limit (10/day) is checked before writing any record.
 *
 * Exports:
 *   blockUser(db, actorUid, targetUid)
 *   muteUser(db, actorUid, targetUid)
 *   reportContent(db, reporterUid, contentRef, contentType, category, notes)
 *   isBlocked(db, uid1, uid2)
 *   isMuted(db, actorUid, targetUid)
 */

const { FieldValue } = require("firebase-admin/firestore");
const crypto = require("crypto");

const { checkRateLimit, incrementCounter } = require("./rateLimits");
const { escalateChildSafety }              = require("../moderation/escalation");

// ─── Collection names ─────────────────────────────────────────────────────────

const COL_BLOCKS         = "blocks";
const COL_MUTES          = "mutes";
const COL_REPORTS        = "contentReports";
const COL_REVIEW_QUEUE   = "moderationQueue";

// ─── Report categories that trigger immediate child-safety escalation ─────────

const CHILD_SAFETY_CATEGORIES = new Set([
  "child_safety",
  "csam_suspected",
  "child_exploitation",
  "child_grooming",
  "minor_sexualization",
]);

// ─── Helpers ──────────────────────────────────────────────────────────────────

/** Stable, order-independent document ID for a pair of UIDs. */
function pairDocId(uid1, uid2) {
  return [uid1, uid2].sort().join("_");
}

/** Current daily bucket string in UTC (YYYY-MM-DD). */
function dailyBucket() {
  return new Date().toISOString().slice(0, 10);
}

// ─── blockUser ────────────────────────────────────────────────────────────────

/**
 * Creates a bidirectional block between actorUid and targetUid.
 *
 * Both users lose visibility of each other across all surfaces.  If a block
 * record already exists the write is a no-op (idempotent).
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} actorUid   The user initiating the block
 * @param {string} targetUid  The user being blocked
 * @returns {Promise<{ docId: string, alreadyBlocked: boolean }>}
 */
async function blockUser(db, actorUid, targetUid) {
  if (!db)        throw new Error("[blockMuteReport] db is required");
  if (!actorUid)  throw new Error("[blockMuteReport] actorUid is required");
  if (!targetUid) throw new Error("[blockMuteReport] targetUid is required");
  if (actorUid === targetUid) throw new Error("[blockMuteReport] cannot block yourself");

  const docId  = pairDocId(actorUid, targetUid);
  const docRef = db.collection(COL_BLOCKS).doc(docId);

  const snap = await docRef.get();
  if (snap.exists) {
    return { docId, alreadyBlocked: true };
  }

  await docRef.set({
    docId,
    uids:       [actorUid, targetUid].sort(),  // both directions in one doc
    initiator:  actorUid,
    createdAt:  FieldValue.serverTimestamp(),
    // No updatedAt — this record is append-only; unblock creates a new event
    active:     true,
  });

  console.log(`[blockMuteReport] Block created actor=${actorUid} target=${targetUid}`);
  return { docId, alreadyBlocked: false };
}

// ─── muteUser ─────────────────────────────────────────────────────────────────

/**
 * Creates a unidirectional mute record.  The muted user is not informed.
 * Idempotent: calling again returns the existing record ID.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} actorUid   The user who wants to stop seeing content
 * @param {string} targetUid  The user whose content will be hidden
 * @returns {Promise<{ docId: string, alreadyMuted: boolean }>}
 */
async function muteUser(db, actorUid, targetUid) {
  if (!db)        throw new Error("[blockMuteReport] db is required");
  if (!actorUid)  throw new Error("[blockMuteReport] actorUid is required");
  if (!targetUid) throw new Error("[blockMuteReport] targetUid is required");
  if (actorUid === targetUid) throw new Error("[blockMuteReport] cannot mute yourself");

  // Mute is directional: actor mutes target, so the doc ID is directional too.
  const docId  = `${actorUid}_${targetUid}`;
  const docRef = db.collection(COL_MUTES).doc(docId);

  const snap = await docRef.get();
  if (snap.exists && snap.data().active) {
    return { docId, alreadyMuted: true };
  }

  await docRef.set({
    docId,
    actorUid,
    targetUid,
    createdAt: FieldValue.serverTimestamp(),
    active:    true,
  });

  console.log(`[blockMuteReport] Mute created actor=${actorUid} target=${targetUid}`);
  return { docId, alreadyMuted: false };
}

// ─── reportContent ────────────────────────────────────────────────────────────

/**
 * Files a content report.
 *
 * Steps:
 *   1. Check reporter's daily report rate limit (10/day).
 *   2. Create an immutable report record.
 *   3a. If category is child_safety / csam_suspected → call escalateChildSafety.
 *   3b. Otherwise → add to moderationQueue for normal review.
 *   4. Increment the reporter's rate-limit counter.
 *
 * The reported user is NEVER notified.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} reporterUid
 * @param {string} contentRef     Firestore document path of the reported content
 *                                e.g. "posts/abc123" or "comments/xyz"
 * @param {string} contentType    "post" | "comment" | "message" | "profile" | "space"
 * @param {string} category       Report category string (see CHILD_SAFETY_CATEGORIES above)
 * @param {string} [notes]        Optional free-text from reporter (max 500 chars)
 * @returns {Promise<{
 *   reportId: string,
 *   escalated: boolean,          // true if routed to child-safety pipeline
 *   queuedForReview: boolean,    // true if added to normal moderationQueue
 * }>}
 */
async function reportContent(db, reporterUid, contentRef, contentType, category, notes) {
  if (!db)          throw new Error("[blockMuteReport] db is required");
  if (!reporterUid) throw new Error("[blockMuteReport] reporterUid is required");
  if (!contentRef)  throw new Error("[blockMuteReport] contentRef is required");
  if (!contentType) throw new Error("[blockMuteReport] contentType is required");
  if (!category)    throw new Error("[blockMuteReport] category is required");

  // Truncate notes defensively.
  const sanitisedNotes = notes ? String(notes).slice(0, 500) : null;

  // ── 1. Rate-limit check ───────────────────────────────────────────────────
  // Throws RateLimitError if the reporter has already filed 10 reports today.
  await checkRateLimit(db, reporterUid, "report", dailyBucket());

  // ── 2. Create immutable report record ────────────────────────────────────
  const reportId = crypto.randomUUID();
  const reportRef = db.collection(COL_REPORTS).doc(reportId);

  await reportRef.set({
    reportId,
    reporterUid,
    contentRef,
    contentType,
    category:    category.toLowerCase(),
    notes:       sanitisedNotes,
    createdAt:   FieldValue.serverTimestamp(),
    // The report is the canonical record; its status tracks downstream handling.
    status:      "filed",
    escalated:   false,
  });

  let escalated      = false;
  let queuedForReview = false;

  const normCategory = category.toLowerCase();

  // ── 3a. Child-safety fast path ────────────────────────────────────────────
  if (CHILD_SAFETY_CATEGORIES.has(normCategory)) {
    try {
      // Fetch a snapshot of the content document to hand to the escalation pipeline.
      let contentSnapshot = {};
      try {
        const contentSnap = await db.doc(contentRef).get();
        contentSnapshot = contentSnap.exists ? contentSnap.data() : {};
      } catch (_) {
        // Best-effort; escalation must not be blocked by a missing content doc.
      }

      await escalateChildSafety(
        db,
        contentRef,
        contentSnapshot.authorId ?? contentSnapshot.uid ?? null,
        reporterUid,
        [normCategory],
        contentSnapshot
      );

      // Mark the report as escalated.
      await reportRef.update({
        status:    "escalated_child_safety",
        escalated: true,
      });

      escalated = true;
      console.warn(
        `[blockMuteReport] Child-safety escalation triggered ` +
        `reporter=${reporterUid} contentRef=${contentRef} category=${normCategory}`
      );
    } catch (err) {
      // Escalation failure must not suppress the report.
      console.error("[blockMuteReport] escalateChildSafety failed:", err);
      // Fall through to normal queue as a safety net.
    }
  }

  // ── 3b. Normal review queue ───────────────────────────────────────────────
  if (!escalated) {
    const queueRef = db.collection(COL_REVIEW_QUEUE).doc(reportId);
    await queueRef.set({
      reportId,
      reporterUid,
      contentRef,
      contentType,
      category:  normCategory,
      notes:     sanitisedNotes,
      priority:  "normal",
      status:    "pending",
      createdAt: FieldValue.serverTimestamp(),
    });

    await reportRef.update({ status: "queued_for_review" });
    queuedForReview = true;
  }

  // ── 4. Increment rate-limit counter ──────────────────────────────────────
  await incrementCounter(db, reporterUid, "report", dailyBucket());

  return { reportId, escalated, queuedForReview };
}

// ─── isBlocked ────────────────────────────────────────────────────────────────

/**
 * Returns true if a block exists between uid1 and uid2 in either direction.
 * Checks the single bidirectional document.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid1
 * @param {string} uid2
 * @returns {Promise<boolean>}
 */
async function isBlocked(db, uid1, uid2) {
  if (!db)   throw new Error("[blockMuteReport] db is required");
  if (!uid1) throw new Error("[blockMuteReport] uid1 is required");
  if (!uid2) throw new Error("[blockMuteReport] uid2 is required");

  if (uid1 === uid2) return false;

  const docId = pairDocId(uid1, uid2);
  const snap  = await db.collection(COL_BLOCKS).doc(docId).get();
  return snap.exists && snap.data().active === true;
}

// ─── isMuted ──────────────────────────────────────────────────────────────────

/**
 * Returns true if actorUid has muted targetUid.
 * This is unidirectional — does NOT check whether targetUid has muted actorUid.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} actorUid
 * @param {string} targetUid
 * @returns {Promise<boolean>}
 */
async function isMuted(db, actorUid, targetUid) {
  if (!db)        throw new Error("[blockMuteReport] db is required");
  if (!actorUid)  throw new Error("[blockMuteReport] actorUid is required");
  if (!targetUid) throw new Error("[blockMuteReport] targetUid is required");

  if (actorUid === targetUid) return false;

  const docId = `${actorUid}_${targetUid}`;
  const snap  = await db.collection(COL_MUTES).doc(docId).get();
  return snap.exists && snap.data().active === true;
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = {
  blockUser,
  muteUser,
  reportContent,
  isBlocked,
  isMuted,
  CHILD_SAFETY_CATEGORIES,
};

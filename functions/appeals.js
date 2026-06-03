// appeals.js
// User-facing appeals for removed/held content.
// appeals/{appealId}: { contentId, contentType, contentRef, authorId, reason, evidence,
//                        status: "pending"|"approved"|"rejected",
//                        createdAt, reviewedAt?, reviewedBy?, adminNotes? }

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { enforceRateLimit } = require("./rateLimiter");

exports.submitAppeal = onCall({ region: "us-central1" }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  const uid = request.auth.uid;
  const { contentId, contentType, reason, evidence } = request.data || {};

  if (!contentId) {
    throw new HttpsError("invalid-argument", "contentId is required.");
  }
  if (!reason) {
    throw new HttpsError("invalid-argument", "reason is required.");
  }
  if (reason.length > 500) {
    throw new HttpsError("invalid-argument", "reason must be 500 characters or fewer.");
  }
  if (evidence && evidence.length > 1000) {
    throw new HttpsError("invalid-argument", "evidence must be 1000 characters or fewer.");
  }

  await enforceRateLimit(uid, "appeal_submit", 3, 86400);

  const db = getFirestore();

  let contentData = null;
  let contentRef = null;

  if (contentType === "prayer") {
    const prayerSnap = await db.collection("prayers").doc(contentId).get();
    if (!prayerSnap.exists) {
      throw new HttpsError("not-found", `Prayer ${contentId} not found.`);
    }
    contentData = prayerSnap.data();
    contentRef = `prayers/${contentId}`;
  } else {
    // Default: posts. For sanctuary_message we would need the sanctuary ID —
    // scoped to posts and prayers for now.
    const postSnap = await db.collection("posts").doc(contentId).get();
    if (!postSnap.exists) {
      throw new HttpsError("not-found", `Post ${contentId} not found.`);
    }
    contentData = postSnap.data();
    contentRef = `posts/${contentId}`;
  }

  const isAuthor =
    contentData.authorId === uid || contentData.userId === uid;
  if (!isAuthor) {
    throw new HttpsError("permission-denied", "You can only appeal your own content.");
  }

  if (contentData.visible === true) {
    throw new HttpsError("failed-precondition", "Content is not currently removed.");
  }

  const appealDoc = await db.collection("appeals").add({
    contentId,
    contentType: contentType || "post",
    contentRef,
    authorId: uid,
    reason,
    evidence: evidence || null,
    status: "pending",
    createdAt: FieldValue.serverTimestamp(),
  });

  await db.collection("moderationQueue").add({
    postRef: contentRef,
    authorId: uid,
    preview: reason.slice(0, 280),
    status: "appeal",
    appealsRef: appealDoc.id,
    createdAt: FieldValue.serverTimestamp(),
  });

  return { appealId: appealDoc.id, status: "pending" };
});

exports.reviewAppeal = onCall({ region: "us-central1" }, async (request) => {
  if (!request.auth?.token?.admin) {
    throw new HttpsError("permission-denied", "Admin only.");
  }

  const uid = request.auth.uid;
  const { appealId, decision, adminNotes } = request.data || {};

  if (!appealId) {
    throw new HttpsError("invalid-argument", "appealId is required.");
  }
  if (!["approved", "rejected"].includes(decision)) {
    throw new HttpsError("invalid-argument", "decision must be 'approved' or 'rejected'.");
  }

  const db = getFirestore();
  const appealRef = db.collection("appeals").doc(appealId);
  const appealSnap = await appealRef.get();

  if (!appealSnap.exists) {
    throw new HttpsError("not-found", `Appeal ${appealId} not found.`);
  }

  const appealData = appealSnap.data();

  if (decision === "approved") {
    const contentDocRef = db.doc(appealData.contentRef);
    await contentDocRef.update({
      visible: true,
      flaggedForReview: false,
      removed: false,
      moderation: {
        status: "appeal_approved",
        reviewedBy: uid,
        reviewedAt: FieldValue.serverTimestamp(),
      },
    });

    await appealRef.update({
      status: "approved",
      reviewedAt: FieldValue.serverTimestamp(),
      reviewedBy: uid,
      adminNotes: adminNotes || null,
    });
  } else {
    await appealRef.update({
      status: "rejected",
      reviewedAt: FieldValue.serverTimestamp(),
      reviewedBy: uid,
      adminNotes: adminNotes || null,
    });
  }

  await db.collection("moderationAuditLog").add({
    adminId: uid,
    action: "review_appeal",
    appealId,
    decision,
    reviewedAt: FieldValue.serverTimestamp(),
  });

  return { success: true, decision };
});

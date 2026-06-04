// reviewAppealV1.js — migrated to v2 (quota freed; was gen1 workaround)
// Admin-only callable to approve or reject a pending content appeal.
// submitAppeal is in appeals.js (also v2).

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

exports.reviewAppeal = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth?.token?.admin) {
    throw new HttpsError("permission-denied", "Admin only.");
  }

  const uid = request.auth.uid;
  const { appealId, decision, adminNotes } = request.data ?? {};

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

// TODO: MIGRATE_TO_V2 — still using Gen1 runWith() pattern
// reviewAppealV1.js — v1 Cloud Function (avoids Cloud Run quota)
// Admin-only callable to approve or reject a pending content appeal.
// submitAppeal is in appeals.js (already deployed as v2).

const functions = require("firebase-functions/v1");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

exports.reviewAppeal = functions.region("us-central1").https.onCall(async (data, context) => {
  if (!context.auth?.token?.admin) {
    throw new functions.https.HttpsError("permission-denied", "Admin only.");
  }

  const uid = context.auth.uid;
  const { appealId, decision, adminNotes } = data || {};

  if (!appealId) {
    throw new functions.https.HttpsError("invalid-argument", "appealId is required.");
  }
  if (!["approved", "rejected"].includes(decision)) {
    throw new functions.https.HttpsError("invalid-argument", "decision must be 'approved' or 'rejected'.");
  }

  const db = getFirestore();
  const appealRef = db.collection("appeals").doc(appealId);
  const appealSnap = await appealRef.get();

  if (!appealSnap.exists) {
    throw new functions.https.HttpsError("not-found", `Appeal ${appealId} not found.`);
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

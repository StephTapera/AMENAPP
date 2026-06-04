const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const db = admin.firestore();
const VALID_OUTCOME_TYPES = ["groupFormed","eventCreated","studyLaunched","questionAnswered","prayerAnswered"];

exports.recordDiscussionOutcome = onCall(async (request) => {
  const { threadId, type, title, description } = request.data;
  const uid = request.auth?.uid;
  if (!uid || !threadId || !type || !title) throw new Error("Missing params");
  if (!VALID_OUTCOME_TYPES.includes(type)) throw new Error("Invalid outcome type");
  await db.collection("threads").doc(threadId).collection("outcomes").add({
    type, title, description: description || null,
    createdBy: uid, createdAt: admin.firestore.FieldValue.serverTimestamp()
  });
  return { ok: true };
});

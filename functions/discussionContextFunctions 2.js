const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const db = admin.firestore();

exports.updateReadProgress = onCall(async (request) => {
  const { postId, readFraction } = request.data;
  const uid = request.auth?.uid;
  if (!uid || !postId) throw new Error("Missing params");
  const docId = `${uid}_${postId}`;
  await db.collection("watchProgress").doc(docId).set(
    { uid, postId, readFraction: Math.min(1, readFraction || 0), updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );
  return { ok: true };
});

exports.updateAudioProgress = onCall(async (request) => {
  const { postId, audioFraction } = request.data;
  const uid = request.auth?.uid;
  if (!uid || !postId) throw new Error("Missing params");
  const docId = `${uid}_${postId}`;
  await db.collection("watchProgress").doc(docId).set(
    { uid, postId, audioFraction: Math.min(1, audioFraction || 0), updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );
  return { ok: true };
});

exports.updateCarouselProgress = onCall(async (request) => {
  const { postId, viewedSlides, totalSlides } = request.data;
  const uid = request.auth?.uid;
  if (!uid || !postId) throw new Error("Missing params");
  const fraction = totalSlides > 0 ? Math.min(1, viewedSlides / totalSlides) : 0;
  const docId = `${uid}_${postId}`;
  await db.collection("watchProgress").doc(docId).set(
    { uid, postId, carouselFraction: fraction, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );
  return { ok: true };
});

exports.getContextScore = onCall(async (request) => {
  const { postId } = request.data;
  const uid = request.auth?.uid;
  if (!uid || !postId) return { score: 100 };
  const docId = `${uid}_${postId}`;
  const snap = await db.collection("watchProgress").doc(docId).get();
  if (!snap.exists) return { score: 0 };
  const data = snap.data();
  const read     = (data.readFraction     || 0) * 30;
  const audio    = (data.audioFraction    || 0) * 20;
  const carousel = (data.carouselFraction || 0) * 10;
  const video    = (data.videoFraction    || 0) * 40;
  const score = Math.round(read + audio + carousel + video);
  return { score: Math.min(100, score) };
});

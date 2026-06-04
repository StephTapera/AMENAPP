const { onCall } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { defineSecret } = require("firebase-functions/params");

const BEREAN_LLM_KEY = defineSecret("BEREAN_LLM_KEY");
const db = admin.firestore();

exports.analyzeDiscussionHealth = onCall({ secrets: [BEREAN_LLM_KEY] }, async (request) => {
  const { threadId } = request.data;
  if (!threadId) throw new Error("Missing threadId");

  const snap = await db.collection("threads").doc(threadId)
    .collection("comments")
    .where("isDeleted", "==", false)
    .orderBy("createdAt", "desc")
    .limit(50)
    .get();

  const comments = snap.docs.map(d => d.data().body || "").filter(Boolean);
  if (comments.length === 0) {
    await db.collection("threads").doc(threadId).collection("health").doc("current").set({
      status: "healthy", escalationSignals: [], lastAnalyzedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    return { status: "healthy" };
  }

  let status = "healthy", escalationSignals = [];
  try {
    const genAI = new GoogleGenerativeAI(BEREAN_LLM_KEY.value());
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
    const prompt = `Analyze this discussion's health. Comments:\n${comments.slice(0, 20).join("\n---\n")}\n\nRespond JSON: {"status":"healthy|active|heated|escalating|needsReview","escalationSignals":["..."]}`;
    const result = await model.generateContent(prompt);
    const text = result.response.text();
    const match = text.match(/\{[\s\S]*\}/);
    if (match) {
      const parsed = JSON.parse(match[0]);
      status = parsed.status || "healthy";
      escalationSignals = parsed.escalationSignals || [];
    }
  } catch (_) { /* fail open */ }

  await db.collection("threads").doc(threadId).collection("health").doc("current").set({
    status, escalationSignals, lastAnalyzedAt: admin.firestore.FieldValue.serverTimestamp()
  });
  return { status };
});

exports.autoAnalyzeHealth = onDocumentWritten("threads/{threadId}", async (event) => {
  const after = event.data?.after?.data();
  if (!after) return;
  const count = after.commentCount || 0;
  if (count > 0 && count % 10 === 0) {
    const db2 = admin.firestore();
    const snap = await db2.collection("threads").doc(event.params.threadId)
      .collection("comments").where("isDeleted","==",false).limit(50).get();
    const comments = snap.docs.map(d => d.data().body || "").filter(Boolean);
    if (comments.length === 0) return;
    await db2.collection("threads").doc(event.params.threadId).collection("health").doc("current").set({
      status: "active", escalationSignals: [], lastAnalyzedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
  }
});

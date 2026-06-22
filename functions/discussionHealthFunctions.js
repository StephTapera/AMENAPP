const { onCall } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");

const BEREAN_LLM_KEY = defineSecret("BEREAN_LLM_KEY");
const db = admin.firestore();

async function callGemini(prompt, apiKey) {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }] }),
    }
  );
  if (!res.ok) return null;
  const json = await res.json();
  const raw = json?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  const cleaned = raw.replace(/^```(?:json)?\s*/i, "").replace(/\s*```\s*$/, "").trim();
  try { return JSON.parse(cleaned); } catch { return null; }
}

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
  let status = "healthy", escalationSignals = [];

  if (comments.length > 0) {
    const key = BEREAN_LLM_KEY.value() || "";
    if (key) {
      const prompt = `Analyze this discussion's health. Comments:\n${comments.slice(0, 20).join("\n---\n")}\n\nRespond JSON: {"status":"healthy|active|heated|escalating|needsReview","escalationSignals":["..."]}`;
      const parsed = await callGemini(prompt, key).catch(() => null);
      if (parsed) {
        status = parsed.status || "healthy";
        escalationSignals = parsed.escalationSignals || [];
      }
    }
  }

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
    await admin.firestore()
      .collection("threads").doc(event.params.threadId)
      .collection("health").doc("current")
      .set({
        status: "active", escalationSignals: [],
        lastAnalyzedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
  }
});

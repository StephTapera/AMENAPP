const { onCall } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");

const BEREAN_LLM_KEY = defineSecret("BEREAN_LLM_KEY");
const db = admin.firestore();

const MOCK_MEDIATION = {
  areasOfAgreement: ["Both sides share a desire to understand the truth"],
  differentPerspectives: ["Some emphasize personal experience, others emphasize scripture"],
  questionsWorthExploring: ["What does this passage mean in its original context?"],
  potentialMisunderstandings: ["Some may be using the same words with different meanings"],
  suggestedClarifications: ["Clarifying what 'faith' means to each person might help"]
};

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

exports.mediateDiscussion = onCall({ secrets: [BEREAN_LLM_KEY] }, async (request) => {
  const { threadId } = request.data;
  if (!threadId) throw new Error("Missing threadId");

  const snap = await db.collection("threads").doc(threadId)
    .collection("comments")
    .where("isDeleted", "==", false)
    .orderBy("createdAt", "desc")
    .limit(30)
    .get();

  const comments = snap.docs.map(d => d.data().body || "").filter(Boolean);
  if (comments.length === 0) return MOCK_MEDIATION;

  const key = BEREAN_LLM_KEY.value() || "";
  if (!key) return MOCK_MEDIATION;

  const prompt = `You are a neutral, wise facilitator. Analyze this discussion and find common ground.\n\nComments:\n${comments.join("\n---\n")}\n\nRespond JSON: {"areasOfAgreement":[],"differentPerspectives":[],"questionsWorthExploring":[],"potentialMisunderstandings":[],"suggestedClarifications":[]}`;
  const parsed = await callGemini(prompt, key).catch(() => null);
  return parsed || MOCK_MEDIATION;
});

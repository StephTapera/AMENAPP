const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { defineSecret } = require("firebase-functions/params");

const BEREAN_LLM_KEY = defineSecret("BEREAN_LLM_KEY");
const db = admin.firestore();

exports.analyzeDraft = onCall({ secrets: [BEREAN_LLM_KEY] }, async (request) => {
  const { threadId, draftBody } = request.data;
  const uid = request.auth?.uid;
  if (!uid || !draftBody || draftBody.length < 10) return { hasConcern: false };

  // Rate limit: 20/hour
  const usageRef = db.collection("users").doc(uid).collection("draftAnalysisUsage").doc("hourly");
  const now = Date.now();
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(usageRef);
    const d = snap.exists ? snap.data() : { count: 0, windowStart: now };
    const inWindow = now - d.windowStart < 3600000;
    if (inWindow && d.count >= 20) throw new Error("Rate limit");
    tx.set(usageRef, inWindow ? { count: d.count + 1, windowStart: d.windowStart } : { count: 1, windowStart: now });
  });

  try {
    const genAI = new GoogleGenerativeAI(BEREAN_LLM_KEY.value());
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
    const prompt = `You are a kind conversation guide. Review this draft comment and only flag if it could genuinely harm the conversation (not just opinion differences). Be conservative — only flag "medium" severity concerns.\n\nDraft: "${draftBody}"\n\nRespond JSON: {"hasConcern":bool,"observation":"one sentence or empty","severity":"low|medium"}`;
    const result = await model.generateContent(prompt);
    const text = result.response.text();
    const match = text.match(/\{[\s\S]*\}/);
    if (match) {
      const parsed = JSON.parse(match[0]);
      if (parsed.severity === "medium" && parsed.hasConcern) {
        return { hasConcern: true, observation: parsed.observation || "", severity: "medium" };
      }
    }
  } catch (_) { /* fail open */ }

  return { hasConcern: false };
});

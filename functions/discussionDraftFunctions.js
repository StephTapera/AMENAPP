const { onCall } = require("firebase-functions/v2/https");
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

exports.analyzeDraft = onCall({ secrets: [BEREAN_LLM_KEY] }, async (request) => {
  const { draftBody } = request.data;
  const uid = request.auth?.uid;
  if (!uid || !draftBody || draftBody.length < 10) return { hasConcern: false };

  // Rate limit: 20/hour per user
  const usageRef = db.collection("users").doc(uid).collection("draftAnalysisUsage").doc("hourly");
  const now = Date.now();
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(usageRef);
      const d = snap.exists ? snap.data() : { count: 0, windowStart: now };
      const inWindow = now - d.windowStart < 3600000;
      if (inWindow && d.count >= 20) throw new Error("Rate limit");
      tx.set(usageRef, inWindow
        ? { count: d.count + 1, windowStart: d.windowStart }
        : { count: 1, windowStart: now });
    });
  } catch (e) {
    if (e.message === "Rate limit") return { hasConcern: false };
    throw e;
  }

  const key = process.env.BEREAN_LLM_KEY || "";
  if (!key) return { hasConcern: false };

  const prompt = `You are a kind conversation guide. Review this draft comment and only flag if it could genuinely harm the conversation (not just opinion differences). Be conservative — only flag "medium" severity concerns.\n\nDraft: "${draftBody}"\n\nRespond JSON: {"hasConcern":bool,"observation":"one sentence or empty","severity":"low|medium"}`;
  const parsed = await callGemini(prompt, key).catch(() => null);
  if (parsed && parsed.severity === "medium" && parsed.hasConcern) {
    return { hasConcern: true, observation: parsed.observation || "", severity: "medium" };
  }
  return { hasConcern: false };
});

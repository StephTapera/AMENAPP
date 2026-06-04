const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { defineSecret } = require("firebase-functions/params");

const BEREAN_LLM_KEY = defineSecret("BEREAN_LLM_KEY");
const db = admin.firestore();

exports.getDiscussionDashboard = onCall({ secrets: [BEREAN_LLM_KEY] }, async (request) => {
  const { threadId } = request.data;
  const uid = request.auth?.uid;
  if (!uid || !threadId) throw new Error("Missing params");

  // Rate limit 10/hour
  const usageRef = db.collection("users").doc(uid).collection("dashboardUsage").doc("hourly");
  const now = Date.now();
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(usageRef);
      const d = snap.exists ? snap.data() : { count: 0, windowStart: now };
      const inWindow = now - d.windowStart < 3600000;
      if (inWindow && d.count >= 10) throw new Error("Rate limit");
      tx.set(usageRef, inWindow ? { count: d.count+1, windowStart: d.windowStart } : { count: 1, windowStart: now });
    });
  } catch (e) { if (e.message === "Rate limit") throw e; }

  const snap = await db.collection("threads").doc(threadId).collection("comments")
    .where("isDeleted","==",false).orderBy("createdAt","desc").limit(100).get();

  let questionCount = 0, prayerCount = 0, mentorCount = 0;
  const bodies = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const rt = d.responseType || "";
    if (rt === "question") questionCount++;
    if (rt === "prayer") prayerCount++;
    if (rt === "mentorship") mentorCount++;
    if (d.body) bodies.push(d.body);
  }

  const healthSnap = await db.collection("threads").doc(threadId).collection("health").doc("current").get();
  const healthStatus = healthSnap.exists ? (healthSnap.data().status || "healthy") : "healthy";

  let topKeywords = [], suggestedResponses = [];
  try {
    const genAI = new GoogleGenerativeAI(BEREAN_LLM_KEY.value());
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
    const prompt = `From this discussion, extract:\n${bodies.slice(0,30).join("\n---\n")}\n\nJSON: {"topKeywords":["up to 8 short phrases"],"suggestedResponses":["2-3 host response suggestions"]}`;
    const result = await model.generateContent(prompt);
    const text = result.response.text();
    const match = text.match(/\{[\s\S]*\}/);
    if (match) {
      const parsed = JSON.parse(match[0]);
      topKeywords = parsed.topKeywords || [];
      suggestedResponses = parsed.suggestedResponses || [];
    }
  } catch (_) { /* fail open */ }

  return { questionCount, prayerCount, mentorCount, topKeywords, suggestedResponses, healthStatus };
});

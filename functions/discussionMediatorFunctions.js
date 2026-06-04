const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { defineSecret } = require("firebase-functions/params");

const BEREAN_LLM_KEY = defineSecret("BEREAN_LLM_KEY");
const db = admin.firestore();

exports.mediateDiscussion = onCall({ secrets: [BEREAN_LLM_KEY] }, async (request) => {
  const { threadId } = request.data;
  if (!threadId) throw new Error("Missing threadId");

  const snap = await db.collection("threads").doc(threadId).collection("comments")
    .where("isDeleted","==",false).orderBy("createdAt","desc").limit(30).get();
  const comments = snap.docs.map(d => d.data().body || "").filter(Boolean);

  const mock = {
    areasOfAgreement: ["Both sides share a desire to understand the truth"],
    differentPerspectives: ["Some emphasize personal experience, others emphasize scripture"],
    questionsWorthExploring: ["What does this passage mean in its original context?"],
    potentialMisunderstandings: ["Some may be using the same words with different meanings"],
    suggestedClarifications: ["Clarifying what 'faith' means to each person might help"]
  };

  if (comments.length === 0) return mock;

  try {
    const genAI = new GoogleGenerativeAI(BEREAN_LLM_KEY.value());
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
    const prompt = `You are a neutral, wise facilitator. Analyze this discussion and find common ground.\n\nComments:\n${comments.join("\n---\n")}\n\nRespond JSON: {"areasOfAgreement":[],"differentPerspectives":[],"questionsWorthExploring":[],"potentialMisunderstandings":[],"suggestedClarifications":[]}`;
    const result = await model.generateContent(prompt);
    const text = result.response.text();
    const match = text.match(/\{[\s\S]*\}/);
    if (match) return JSON.parse(match[0]);
  } catch (_) { /* fall through */ }

  return mock;
});

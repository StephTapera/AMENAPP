/**
 * Berean OS — Wisdom Engine Cloud Functions
 * bereanWisdomAnalysis
 *
 * Deploy: firebase deploy --only functions:bereanWisdomAnalysis --project amen-5e359
 * Requires: CLAUDE_API_KEY secret
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

const REGION = "us-central1";
const CLAUDE_API_KEY = defineSecret("CLAUDE_API_KEY");

exports.bereanWisdomAnalysis = onCall(
  {
    region: REGION,
    secrets: [CLAUDE_API_KEY],
    enforceAppCheck: false,
    timeoutSeconds: 90,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    const { decision, projectId, context } = request.data;

    if (!decision || typeof decision !== "string" || decision.trim().length < 5) {
      throw new HttpsError("invalid-argument", "decision must be at least 5 characters.");
    }
    if (decision.length > 2000) {
      throw new HttpsError("invalid-argument", "decision must be ≤ 2000 characters.");
    }

    const systemPrompt = `You are a biblical wisdom counselor for the AMEN faith community.
Analyze this decision across multiple wisdom dimensions.
Return a JSON object with:
- decision: string
- overallWisdomScore: number 0-10
- dimensions: array of objects {
    name: string (e.g., "Biblical Alignment", "Long-term Impact", "Relationships", "Stewardship", "Character Growth", "Community Impact"),
    score: number 0-10,
    rationale: string,
    scriptures: array of strings
  }
- topStrengths: array of strings
- topConcerns: array of strings
- alternativeApproaches: array of strings
- keyScriptures: array of objects { reference: string, text: string, relevance: string }
- wisdomSummary: string (2-3 sentences of balanced counsel)

Include 5-7 dimensions. Be pastoral, balanced, and grounded in scripture.
Return ONLY valid JSON, no markdown.`;

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": CLAUDE_API_KEY.value(),
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-6",
        max_tokens: 2000,
        messages: [
          {
            role: "user",
            content: `${systemPrompt}\n\nDecision to analyze: "${decision}"${context ? `\n\nAdditional context: ${context}` : ""}`,
          },
        ],
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      console.error("[bereanWisdomAnalysis] Claude error:", err);
      throw new HttpsError("internal", "Wisdom analysis failed.");
    }

    const result = await response.json();
    let analysis = {};
    try {
      const raw = result.content[0].text;
      const jsonMatch = raw.match(/\{[\s\S]*\}/);
      analysis = JSON.parse(jsonMatch ? jsonMatch[0] : raw);
    } catch (_) {
      throw new HttpsError("internal", "Failed to parse wisdom analysis response.");
    }

    const analysisId = admin.firestore().collection("_").doc().id;
    analysis.id = analysisId;
    analysis.decision = decision;
    analysis.createdAt = new Date().toISOString();

    // Optionally save to project
    if (projectId) {
      await admin.firestore()
        .collection("users").doc(uid)
        .collection("bereanProjects").doc(projectId)
        .collection("wisdomAnalyses").doc(analysisId)
        .set({ ...analysis, createdAt: admin.firestore.FieldValue.serverTimestamp() });
    }

    return analysis;
  }
);

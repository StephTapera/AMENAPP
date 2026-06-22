// SECURITY: enforceAppCheck: true added — enable Console enforce-mode per DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md
/**
 * Berean OS — Research Engine Cloud Functions
 * bereanStartResearch
 *
 * Deploy: firebase deploy --only functions:bereanStartResearch --project amen-5e359
 * Requires: CLAUDE_API_KEY, OPENAI_API_KEY secrets
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

const REGION = "us-central1";
const CLAUDE_API_KEY = defineSecret("CLAUDE_API_KEY");

exports.bereanStartResearch = onCall(
  {
    region: REGION,
    secrets: [CLAUDE_API_KEY],
    enforceAppCheck: true,
    timeoutSeconds: 120,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    const { query, mode, projectId } = request.data;

    if (!query || typeof query !== "string" || query.trim().length < 3) {
      throw new HttpsError("invalid-argument", "query must be at least 3 characters.");
    }
    if (query.length > 2000) {
      throw new HttpsError("invalid-argument", "query must be ≤ 2000 characters.");
    }

    const researchMode = mode || "balanced";
    const systemPrompt = `You are a rigorous research assistant for the AMEN faith community.
Conduct thorough, balanced research on the given topic. Mode: ${researchMode}.
Return a JSON object with these fields:
- title: string (concise research title)
- executiveSummary: string (2-3 sentences overview)
- confidenceScore: number 0-1
- confidenceLevel: one of "verifiedFact", "stronglySupported", "likelyTrue", "uncertain", "speculative", "opinionBased", "aiGenerated"
- keyFindings: array of objects { claim: string, evidence: string, confidence: number }
- evidence: array of objects { description: string, source: string, reliability: number }
- counterArguments: array of strings
- openQuestions: array of strings
- recommendations: array of strings
- sources: array of strings (cited sources)
- researchMode: string

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
          { role: "user", content: `${systemPrompt}\n\nResearch query: ${query}` },
        ],
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      console.error("[bereanStartResearch] Claude error:", err);
      throw new HttpsError("internal", "Research failed. Please try again.");
    }

    const result = await response.json();
    let report = {};
    try {
      const raw = result.content[0].text;
      const jsonMatch = raw.match(/\{[\s\S]*\}/);
      report = JSON.parse(jsonMatch ? jsonMatch[0] : raw);
    } catch (_) {
      throw new HttpsError("internal", "Failed to parse research response.");
    }

    report.id = admin.firestore().collection("_").doc().id;
    report.query = query;
    report.researchMode = researchMode;
    report.createdAt = new Date().toISOString();

    // Optionally save to project
    if (projectId) {
      await admin.firestore()
        .collection("users").doc(uid)
        .collection("bereanProjects").doc(projectId)
        .collection("researchReports").doc(report.id)
        .set({ ...report, createdAt: admin.firestore.FieldValue.serverTimestamp() });
    }

    return report;
  }
);

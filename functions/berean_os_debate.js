/**
 * Berean OS — Debate Engine Cloud Functions
 * bereanGenerateDebate
 *
 * Deploy: firebase deploy --only functions:bereanGenerateDebate --project amen-5e359
 * Requires: CLAUDE_API_KEY secret
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

const REGION = "us-central1";
const CLAUDE_API_KEY = defineSecret("CLAUDE_API_KEY");

exports.bereanGenerateDebate = onCall(
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
    const { question, projectId } = request.data;

    if (!question || typeof question !== "string" || question.trim().length < 5) {
      throw new HttpsError("invalid-argument", "question must be at least 5 characters.");
    }
    if (question.length > 500) {
      throw new HttpsError("invalid-argument", "question must be ≤ 500 characters.");
    }

    const systemPrompt = `You are a structured debate facilitator for the AMEN faith community.
Generate a balanced, rigorous two-sided debate on the given question.
Return a JSON object with:
- question: string
- sideA: { position: string, arguments: array of { claim: string, evidence: string, confidence: number } }
- sideB: { position: string, arguments: array of { claim: string, evidence: string, confidence: number } }
- commonGround: array of strings (areas both sides agree)
- stillUnknown: array of strings (open questions neither side can answer definitively)
- keyTakeaway: string (balanced synthesis)

Each side should have 3-5 arguments. Be fair, rigorous, and scripturally grounded where relevant.
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
          { role: "user", content: `${systemPrompt}\n\nDebate question: ${question}` },
        ],
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      console.error("[bereanGenerateDebate] Claude error:", err);
      throw new HttpsError("internal", "Debate generation failed.");
    }

    const result = await response.json();
    let debate = {};
    try {
      const raw = result.content[0].text;
      const jsonMatch = raw.match(/\{[\s\S]*\}/);
      debate = JSON.parse(jsonMatch ? jsonMatch[0] : raw);
    } catch (_) {
      throw new HttpsError("internal", "Failed to parse debate response.");
    }

    const debateId = admin.firestore().collection("_").doc().id;
    debate.id = debateId;
    debate.question = question;
    debate.createdAt = new Date().toISOString();

    // Optionally save to project
    if (projectId) {
      await admin.firestore()
        .collection("users").doc(uid)
        .collection("bereanProjects").doc(projectId)
        .collection("debates").doc(debateId)
        .set({ ...debate, createdAt: admin.firestore.FieldValue.serverTimestamp() });
    }

    return debate;
  }
);

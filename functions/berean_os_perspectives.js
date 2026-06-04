"use strict";
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");

const CLAUDE_API_KEY = defineSecret("CLAUDE_API_KEY");
const REGION = "us-central1";

exports.bereanMultiPerspective = onCall(
  {region: REGION, secrets: [CLAUDE_API_KEY], timeoutSeconds: 90},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const {question, perspectives} = request.data;
    if (!question || !Array.isArray(perspectives) || perspectives.length < 2) {
      throw new HttpsError("invalid-argument", "question and at least 2 perspectives required.");
    }
    if (perspectives.length > 6) throw new HttpsError("invalid-argument", "Max 6 perspectives.");

    const fetch = (await import("node-fetch")).default;
    const prompt = `Generate multiple perspectives on this question. Steelman each perspective — give the strongest version of each view.

Question: ${question}
Perspectives: ${perspectives.join(", ")}

Return JSON:
{
  "perspectives": [
    {
      "perspectiveType": "role name",
      "summary": "2-3 sentence summary of this perspective",
      "agreements": ["point they'd agree with others on"],
      "disagreements": ["point they'd disagree with others on"],
      "tradeoffs": ["key tradeoff from this perspective"],
      "unknowns": ["what they can't answer from their position"]
    }
  ],
  "consensusZone": ["things all perspectives agree on"],
  "openQuestions": ["questions none of the perspectives can answer"]
}`;

    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": CLAUDE_API_KEY.value(),
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-6",
        max_tokens: 3000,
        messages: [{role: "user", content: prompt}],
      }),
    });
    const data = await resp.json();
    const text = data.content?.[0]?.text || "";
    let result = {perspectives: [], consensusZone: [], openQuestions: []};
    try {
      result = JSON.parse(text.match(/\{[\s\S]*\}/)?.[0] || "{}");
    } catch (_) {
      // Return empty result if parse fails — client handles gracefully
    }

    return {
      perspectives: (result.perspectives || []).map((p, i) => ({id: `p${i}`, ...p})),
      consensusZone: result.consensusZone || [],
      openQuestions: result.openQuestions || [],
    };
  }
);

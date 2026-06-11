// SECURITY: enforceAppCheck: true added — enable Console enforce-mode per DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md
/**
 * Berean OS — Advisory Boards Cloud Functions
 * bereanConsultAdvisoryBoard
 *
 * Deploy: firebase deploy --only functions:bereanConsultAdvisoryBoard --project amen-5e359
 * Requires: CLAUDE_API_KEY secret
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

const REGION = "us-central1";
const CLAUDE_API_KEY = defineSecret("CLAUDE_API_KEY");

const BOARD_ARCHETYPES = {
  biblical: { name: "Biblical Scholar", focus: "scripture, theology, and doctrinal alignment" },
  practical: { name: "Practical Strategist", focus: "execution, resources, and measurable outcomes" },
  relational: { name: "Relational Counselor", focus: "people, community, and emotional wisdom" },
  prophetic: { name: "Prophetic Voice", focus: "vision, calling, and spiritual discernment" },
  stewardship: { name: "Stewardship Expert", focus: "finances, time, and resource management" },
  cultural: { name: "Cultural Translator", focus: "context, relevance, and engaging the culture" },
};

exports.bereanConsultAdvisoryBoard = onCall(
  {
    region: REGION,
    secrets: [CLAUDE_API_KEY],
    enforceAppCheck: true,
    timeoutSeconds: 90,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    const { question, boardType, advisorRoles, projectId } = request.data;

    if (!question || typeof question !== "string" || question.trim().length < 5) {
      throw new HttpsError("invalid-argument", "question must be at least 5 characters.");
    }
    if (question.length > 2000) {
      throw new HttpsError("invalid-argument", "question must be ≤ 2000 characters.");
    }

    // Use provided roles or default board archetypes
    const roles = advisorRoles && advisorRoles.length > 0
      ? advisorRoles
      : Object.keys(BOARD_ARCHETYPES).slice(0, 5);

    const advisorDescriptions = roles.map(role => {
      const archetype = BOARD_ARCHETYPES[role];
      return archetype
        ? `- ${archetype.name}: Focuses on ${archetype.focus}`
        : `- ${role}: Provides perspective from their domain`;
    }).join("\n");

    const systemPrompt = `You are facilitating an AI advisory board session for the AMEN faith community.
Generate authentic, distinct perspectives from each board member on the given question.
Board composition:
${advisorDescriptions}

Return a JSON object with:
- question: string
- boardType: string
- advisorResponses: array of objects {
    role: string,
    advisorName: string,
    perspective: string (2-3 sentences of focused advice),
    keyRecommendation: string (one clear action to take),
    scripture: string|null (relevant verse if applicable)
  }
- synthesis: string (2-3 sentences integrating all perspectives into a unified recommendation)
- unanimousPoints: array of strings (things all advisors agree on)
- divergentViews: array of strings (key areas of disagreement or tension)

Each advisor should be genuinely distinct in their focus and tone. Be specific, not generic.
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
        max_tokens: 2500,
        messages: [
          {
            role: "user",
            content: `${systemPrompt}\n\nQuestion for the advisory board: "${question}"`,
          },
        ],
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      console.error("[bereanConsultAdvisoryBoard] Claude error:", err);
      throw new HttpsError("internal", "Advisory board consultation failed.");
    }

    const result = await response.json();
    let consultation = {};
    try {
      const raw = result.content[0].text;
      const jsonMatch = raw.match(/\{[\s\S]*\}/);
      consultation = JSON.parse(jsonMatch ? jsonMatch[0] : raw);
    } catch (_) {
      throw new HttpsError("internal", "Failed to parse advisory board response.");
    }

    const consultationId = admin.firestore().collection("_").doc().id;
    consultation.id = consultationId;
    consultation.question = question;
    consultation.boardType = boardType || "balanced";
    consultation.createdAt = new Date().toISOString();

    // Optionally save to project
    if (projectId) {
      await admin.firestore()
        .collection("users").doc(uid)
        .collection("bereanProjects").doc(projectId)
        .collection("advisoryConsultations").doc(consultationId)
        .set({ ...consultation, createdAt: admin.firestore.FieldValue.serverTimestamp() });
    }

    return consultation;
  }
);

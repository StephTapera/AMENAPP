// SECURITY: enforceAppCheck: true added — enable Console enforce-mode per DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md
/**
 * Berean OS — Mentor OS Cloud Functions
 * bereanAIMentorReview
 *
 * Deploy: firebase deploy --only functions:bereanAIMentorReview --project amen-5e359
 * Requires: CLAUDE_API_KEY secret
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

const REGION = "us-central1";
const CLAUDE_API_KEY = defineSecret("CLAUDE_API_KEY");

const PERSONA_PROMPTS = {
  coach: "You are an encouraging life coach. Focus on goal-setting, accountability, and forward momentum.",
  pastor: "You are a wise pastor with deep biblical knowledge. Focus on spiritual formation, scripture, and soul care.",
  teacher: "You are a knowledgeable teacher. Focus on learning, skill development, and intellectual growth.",
  businessAdvisor: "You are a seasoned business advisor. Focus on strategy, execution, and practical outcomes.",
  lifeMentor: "You are a life mentor with broad wisdom. Focus on holistic growth, relationships, and values alignment.",
};

exports.bereanAIMentorReview = onCall(
  {
    region: REGION,
    secrets: [CLAUDE_API_KEY],
    enforceAppCheck: true,
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    const { projectId, persona, focusArea } = request.data;

    if (!projectId || typeof projectId !== "string") {
      throw new HttpsError("invalid-argument", "projectId is required.");
    }

    const personaKey = (persona || "lifeMentor").replace(/\s+/g, "");
    const personaPrompt = PERSONA_PROMPTS[personaKey] || PERSONA_PROMPTS.lifeMentor;

    // Fetch project + up to 20 memory entries for context
    const projectDoc = await admin.firestore()
      .collection("users").doc(uid)
      .collection("bereanProjects").doc(projectId)
      .get();

    if (!projectDoc.exists) {
      throw new HttpsError("not-found", "Project not found.");
    }

    const project = projectDoc.data();
    const memorySnap = await admin.firestore()
      .collection("users").doc(uid)
      .collection("bereanProjects").doc(projectId)
      .collection("memoryEntries")
      .orderBy("createdAt", "desc")
      .limit(20)
      .get();

    const memories = memorySnap.docs.map(d => `- [${d.data().entryType}] ${d.data().content}`).join("\n");

    const systemPrompt = `${personaPrompt}
You are reviewing a project for a member of the AMEN faith community.
Provide 3-5 specific, actionable mentor notes.
Return a JSON object with:
- notes: array of objects { content: string, noteType: "encouragement"|"challenge"|"question"|"resource"|"warning", isPinned: boolean }

Focus area: ${focusArea || "overall project progress"}
Be specific, pastoral, and practically helpful. Reference the project details directly.
Return ONLY valid JSON, no markdown.`;

    const userContent = `Project: "${project.title}"
Description: ${project.description || "No description"}
Type: ${project.projectType}

Memory entries:
${memories || "No memory entries yet."}`;

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": CLAUDE_API_KEY.value(),
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-6",
        max_tokens: 1200,
        messages: [
          { role: "user", content: `${systemPrompt}\n\n${userContent}` },
        ],
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      console.error("[bereanAIMentorReview] Claude error:", err);
      throw new HttpsError("internal", "AI mentor review failed.");
    }

    const result = await response.json();
    let parsed = {};
    try {
      const raw = result.content[0].text;
      const jsonMatch = raw.match(/\{[\s\S]*\}/);
      parsed = JSON.parse(jsonMatch ? jsonMatch[0] : raw);
    } catch (_) {
      throw new HttpsError("internal", "Failed to parse mentor review response.");
    }

    const notes = (parsed.notes || []).map(n => ({
      ...n,
      authorUid: "berean-ai-mentor",
      isActedUpon: false,
      isPinned: n.isPinned || false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }));

    return { notes, persona: personaKey, focusArea: focusArea || null };
  }
);

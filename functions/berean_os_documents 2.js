/**
 * Berean OS — Living Documents + Action Planner Cloud Functions
 * bereanRefineDocument, bereanGenerateActionPlan
 *
 * Deploy: firebase deploy --only functions:bereanRefineDocument,bereanGenerateActionPlan
 *         --project amen-5e359
 * Requires: CLAUDE_API_KEY secret
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

const REGION = "us-central1";
const CLAUDE_API_KEY = defineSecret("CLAUDE_API_KEY");

exports.bereanRefineDocument = onCall(
  {
    region: REGION,
    secrets: [CLAUDE_API_KEY],
    enforceAppCheck: false,
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const { documentBody, instruction, documentType } = request.data;

    if (!documentBody || typeof documentBody !== "string") {
      throw new HttpsError("invalid-argument", "documentBody is required.");
    }
    if (documentBody.length > 20000) {
      throw new HttpsError("invalid-argument", "documentBody must be ≤ 20000 characters.");
    }
    if (!instruction || typeof instruction !== "string") {
      throw new HttpsError("invalid-argument", "instruction is required.");
    }

    const systemPrompt = `You are a document refinement assistant for the AMEN faith community.
Refine the provided ${documentType || "document"} based on the user's instruction.
Return a JSON object with:
- refinedBody: string (the improved document)
- changeSummary: string (brief description of what was changed and why)

Preserve the original structure and voice while making the requested improvements.
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
        max_tokens: 4000,
        messages: [
          {
            role: "user",
            content: `${systemPrompt}\n\nInstruction: ${instruction}\n\nDocument:\n${documentBody}`,
          },
        ],
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      console.error("[bereanRefineDocument] Claude error:", err);
      throw new HttpsError("internal", "Document refinement failed.");
    }

    const result = await response.json();
    let parsed = {};
    try {
      const raw = result.content[0].text;
      const jsonMatch = raw.match(/\{[\s\S]*\}/);
      parsed = JSON.parse(jsonMatch ? jsonMatch[0] : raw);
    } catch (_) {
      throw new HttpsError("internal", "Failed to parse refinement response.");
    }

    return { refinedBody: parsed.refinedBody || "", changeSummary: parsed.changeSummary || "" };
  }
);

exports.bereanGenerateActionPlan = onCall(
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
    const { goal, planType, projectId, durationWeeks } = request.data;

    if (!goal || typeof goal !== "string" || goal.trim().length < 5) {
      throw new HttpsError("invalid-argument", "goal must be at least 5 characters.");
    }
    if (goal.length > 1000) {
      throw new HttpsError("invalid-argument", "goal must be ≤ 1000 characters.");
    }

    const weeks = Math.min(Math.max(parseInt(durationWeeks) || 4, 1), 52);

    const systemPrompt = `You are an action planning expert for the AMEN faith community.
Create a detailed, actionable ${planType || "personal"} action plan to achieve the goal.
Return a JSON object with:
- title: string
- goal: string
- planType: string
- durationWeeks: number
- milestones: array of objects {
    title: string,
    description: string,
    weekNumber: number,
    tasks: array of objects { title: string, description: string, isCompleted: boolean },
    successCriteria: string,
    dependencies: array of strings (other milestone titles)
  }
- risks: array of objects { description: string, mitigation: string }
- successMetrics: array of strings
- scriptureFoundation: array of objects { reference: string, relevance: string }

Create 3-6 milestones spread over ${weeks} weeks. Each milestone should have 2-5 tasks.
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
        max_tokens: 3000,
        messages: [
          { role: "user", content: `${systemPrompt}\n\nGoal: "${goal}"` },
        ],
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      console.error("[bereanGenerateActionPlan] Claude error:", err);
      throw new HttpsError("internal", "Action plan generation failed.");
    }

    const result = await response.json();
    let plan = {};
    try {
      const raw = result.content[0].text;
      const jsonMatch = raw.match(/\{[\s\S]*\}/);
      plan = JSON.parse(jsonMatch ? jsonMatch[0] : raw);
    } catch (_) {
      throw new HttpsError("internal", "Failed to parse action plan response.");
    }

    const planId = admin.firestore().collection("_").doc().id;
    plan.id = planId;
    plan.goal = goal;
    plan.planType = planType || "personal";
    plan.createdAt = new Date().toISOString();

    // Optionally save to project
    if (projectId) {
      await admin.firestore()
        .collection("users").doc(uid)
        .collection("bereanProjects").doc(projectId)
        .collection("actionPlans").doc(planId)
        .set({ ...plan, createdAt: admin.firestore.FieldValue.serverTimestamp() });
    }

    return { plan };
  }
);

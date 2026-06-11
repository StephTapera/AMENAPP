// SECURITY: enforceAppCheck: true added — enable Console enforce-mode per DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md
/**
 * Berean OS — Knowledge Graph Cloud Functions
 * bereanDiscoverKnowledgeLinks
 *
 * Deploy: firebase deploy --only functions:bereanDiscoverKnowledgeLinks --project amen-5e359
 * Requires: OPENAI_API_KEY secret
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

const REGION = "us-central1";
const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
const MIN_CONFIDENCE = 0.7;

exports.bereanDiscoverKnowledgeLinks = onCall(
  {
    region: REGION,
    secrets: [OPENAI_API_KEY],
    enforceAppCheck: true,
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    const { nodes, projectId } = request.data;

    if (!Array.isArray(nodes) || nodes.length < 2) {
      throw new HttpsError("invalid-argument", "At least 2 nodes are required.");
    }
    if (nodes.length > 50) {
      throw new HttpsError("invalid-argument", "Maximum 50 nodes at once.");
    }

    const nodeDescriptions = nodes.map((n, i) => `${i + 1}. "${n.title}" (${n.nodeType}): ${n.content || ""}`.trim()).join("\n");

    const systemPrompt = `You are a knowledge graph expert. Analyze these knowledge nodes and discover meaningful connections.
Return a JSON object with:
- links: array of objects { fromNodeId: string, toNodeId: string, relationshipType: string, strength: number 0-1, description: string }
- insights: array of strings (surprising patterns or gaps you notice)

Only include links with strength ≥ ${MIN_CONFIDENCE}.
Return ONLY valid JSON, no markdown.`;

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${OPENAI_API_KEY.value()}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: `Nodes:\n${nodeDescriptions}\n\nDiscover meaningful links between these nodes.` },
        ],
        temperature: 0.4,
        max_tokens: 1500,
        response_format: { type: "json_object" },
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      console.error("[bereanDiscoverKnowledgeLinks] OpenAI error:", err);
      throw new HttpsError("internal", "Knowledge discovery failed.");
    }

    const result = await response.json();
    let parsed = {};
    try {
      parsed = JSON.parse(result.choices[0].message.content);
    } catch (_) {
      throw new HttpsError("internal", "Failed to parse knowledge links response.");
    }

    const links = (parsed.links || []).filter(l => l.strength >= MIN_CONFIDENCE);
    const insights = parsed.insights || [];

    // Save discovered links to Firestore
    if (projectId && links.length > 0) {
      const batch = admin.firestore().batch();
      const linksRef = admin.firestore()
        .collection("users").doc(uid)
        .collection("bereanProjects").doc(projectId)
        .collection("knowledgeLinks");
      for (const link of links) {
        const ref = linksRef.doc();
        batch.set(ref, { ...link, discoveredAt: admin.firestore.FieldValue.serverTimestamp() });
      }
      await batch.commit();
    }

    return { links, insights, discoveredCount: links.length };
  }
);

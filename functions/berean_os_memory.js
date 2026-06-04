/**
 * Berean OS — Project Memory Brain Cloud Functions
 * bereanExtractProjectMemory
 *
 * Deploy: firebase deploy --only functions:bereanExtractProjectMemory --project amen-5e359
 * Requires: OPENAI_API_KEY secret
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

const REGION = "us-central1";
const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
const MAX_INPUT_CHARS = 10000;

exports.bereanExtractProjectMemory = onCall(
  {
    region: REGION,
    secrets: [OPENAI_API_KEY],
    enforceAppCheck: false,
    timeoutSeconds: 90,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    const { text, projectId } = request.data;

    if (!text || typeof text !== "string") {
      throw new HttpsError("invalid-argument", "text is required.");
    }
    if (text.length > MAX_INPUT_CHARS) {
      throw new HttpsError("invalid-argument", `text must be ≤ ${MAX_INPUT_CHARS} characters.`);
    }
    if (!projectId || typeof projectId !== "string") {
      throw new HttpsError("invalid-argument", "projectId is required.");
    }

    const systemPrompt = `You are a knowledge extraction assistant. Extract 3-10 discrete memory items from the provided text.
Return a JSON array of objects with these fields:
- entryType: one of "knownFact", "decision", "openQuestion", "assumption", "risk", "resource", "contact", "deadline", "insight", "note"
- content: the extracted item (1-3 sentences, clear and actionable)
- confidence: number 0-1 indicating how certain this item is

Return ONLY valid JSON array, no markdown.`;

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
          { role: "user", content: text },
        ],
        temperature: 0.3,
        max_tokens: 1000,
        response_format: { type: "json_object" },
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      console.error("[bereanExtractProjectMemory] OpenAI error:", err);
      throw new HttpsError("internal", "Memory extraction failed.");
    }

    const result = await response.json();
    let items = [];
    try {
      const parsed = JSON.parse(result.choices[0].message.content);
      items = Array.isArray(parsed) ? parsed : (parsed.items || []);
    } catch (_) {
      throw new HttpsError("internal", "Failed to parse memory extraction response.");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = admin.firestore().batch();
    const entriesRef = admin.firestore()
      .collection("users").doc(uid)
      .collection("bereanProjects").doc(projectId)
      .collection("memoryEntries");

    const saved = [];
    for (const item of items.slice(0, 10)) {
      const ref = entriesRef.doc();
      const entry = {
        id: ref.id,
        entryType: item.entryType || "note",
        content: item.content || "",
        confidence: typeof item.confidence === "number" ? item.confidence : 0.7,
        sourceText: text.slice(0, 200),
        isResolved: false,
        createdAt: now,
        projectId,
      };
      batch.set(ref, entry);
      saved.push(entry);
    }

    await batch.commit();
    return { entries: saved, count: saved.length };
  }
);

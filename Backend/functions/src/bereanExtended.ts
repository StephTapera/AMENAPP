/**
 * bereanExtended.ts
 *
 * Extended Berean AI intelligence callables:
 *   saveBereanInsight, updateBereanMemory, deleteBereanMemory,
 *   createBereanStudyThread, summarizeBereanThread,
 *   compareBibleTranslations, generateBereanFollowUps,
 *   linkBereanContext, unlinkBereanContext,
 *   classifyBereanSafety, updateBereanPreferences
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const db = getFirestore();
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// Haiku model ID — matches rest of codebase
const HAIKU_MODEL = "claude-haiku-4-5-20251001";

// ---------------------------------------------------------------------------
// Auth helper
// ---------------------------------------------------------------------------

function requireAuth(request: CallableRequest): string {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Login required.");
  return request.auth.uid;
}

// ---------------------------------------------------------------------------
// Anthropic fetch helper (matches generateStructuredResponse.ts pattern)
// ---------------------------------------------------------------------------

async function callAnthropic(
  apiKey: string,
  userPrompt: string,
  maxTokens = 400
): Promise<string> {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: HAIKU_MODEL,
      max_tokens: maxTokens,
      messages: [{ role: "user", content: userPrompt }],
    }),
  });

  if (!response.ok) {
    const err = await response.text().catch(() => "Unknown error");
    throw new HttpsError("internal", `Anthropic error: ${response.status} — ${err}`);
  }

  const data = await response.json() as { content?: Array<{ type?: string; text?: string }> };
  return data.content?.find((b) => b.type === "text")?.text ?? "";
}

// ---------------------------------------------------------------------------
// saveBereanInsight
// ---------------------------------------------------------------------------

export const saveBereanInsight = onCall(
  { region: "us-central1", secrets: [anthropicApiKey] , enforceAppCheck: true }, 
  async (request: CallableRequest) => {
    const userId = requireAuth(request);
    const { sessionId, text, linkedVerses = [], tags = [], category = "insight" } =
      request.data as {
        sessionId: string;
        text: string;
        linkedVerses?: string[];
        tags?: string[];
        category?: string;
      };

    if (!text?.trim()) throw new HttpsError("invalid-argument", "text is required.");

    const ref = db.collection("users").doc(userId).collection("bereanMemory").doc();
    await ref.set({
      id: ref.id,
      sessionId,
      text: text.trim(),
      linkedVerses,
      tags,
      category,
      createdAt: FieldValue.serverTimestamp(),
      lastReferencedAt: FieldValue.serverTimestamp(),
      timesReferenced: 0,
      isUserVisible: true,
    });

    await db.collection("users").doc(userId).collection("bereanInsights").doc(ref.id).set({
      id: ref.id,
      userId,
      sourceConversationId: sessionId,
      title: text.trim().slice(0, 80) || "Berean insight",
      summary: text.trim(),
      scriptureReferences: linkedVerses,
      tags,
      createdAt: FieldValue.serverTimestamp(),
      savedToLibrary: true,
      savedToWalkWithChrist: false,
      serverValidated: true,
    });

    await db.collection("bereanAuditEvents").add({
      userId,
      action: "save_insight",
      entryId: ref.id,
      sessionId,
      createdAt: FieldValue.serverTimestamp(),
    });

    logger.info("saveBereanInsight", { userId, entryId: ref.id });
    return { entryId: ref.id };
  }
);

// ---------------------------------------------------------------------------
// updateBereanMemory
// ---------------------------------------------------------------------------

export const updateBereanMemory = onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request: CallableRequest) => {
    const userId = requireAuth(request);
    const { entryId, updates } = request.data as {
      entryId: string;
      updates: Record<string, unknown>;
    };

    const ALLOWED = new Set(["text", "linkedVerses", "tags", "category", "isUserVisible"]);
    const safeUpdates: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp() };
    for (const [k, v] of Object.entries(updates ?? {})) {
      if (ALLOWED.has(k)) safeUpdates[k] = v;
    }

    const ref = db.collection("users").doc(userId).collection("bereanMemory").doc(entryId);
    if (!(await ref.get()).exists) throw new HttpsError("not-found", "Entry not found.");

    await ref.update(safeUpdates);
    return { updated: true };
  }
);

// ---------------------------------------------------------------------------
// deleteBereanMemory
// ---------------------------------------------------------------------------

export const deleteBereanMemory = onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request: CallableRequest) => {
    const userId = requireAuth(request);
    const { entryId } = request.data as { entryId: string };

    const ref = db.collection("users").doc(userId).collection("bereanMemory").doc(entryId);
    if (!(await ref.get()).exists) throw new HttpsError("not-found", "Entry not found.");

    await ref.delete();
    await db.collection("bereanAuditEvents").add({
      userId,
      action: "delete_memory",
      entryId,
      deletedAt: FieldValue.serverTimestamp(),
    });

    return { deleted: true };
  }
);

// ---------------------------------------------------------------------------
// createBereanStudyThread
// ---------------------------------------------------------------------------

export const createBereanStudyThread = onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request: CallableRequest) => {
    const userId = requireAuth(request);
    const { title, passage, topic, initialMessageIds = [] } = request.data as {
      title: string;
      passage?: string;
      topic?: string;
      initialMessageIds?: string[];
    };

    if (!title?.trim()) throw new HttpsError("invalid-argument", "title is required.");

    const ref = db.collection("bereanThreads").doc();
    await ref.set({
      id: ref.id,
      ownerId: userId,
      title: title.trim(),
      passage: passage ?? null,
      topic: topic ?? null,
      messageIds: initialMessageIds,
      messageCount: initialMessageIds.length,
      summaryText: null,
      summaryGeneratedAt: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    logger.info("createBereanStudyThread", { userId, threadId: ref.id });
    return { threadId: ref.id };
  }
);

// ---------------------------------------------------------------------------
// summarizeBereanThread
// ---------------------------------------------------------------------------

export const summarizeBereanThread = onCall(
  { region: "us-central1", secrets: [anthropicApiKey] , enforceAppCheck: true }, 
  async (request: CallableRequest) => {
    const userId = requireAuth(request);
    const { threadId } = request.data as { threadId: string };

    const threadDoc = await db.collection("bereanThreads").doc(threadId).get();
    if (!threadDoc.exists) throw new HttpsError("not-found", "Thread not found.");
    if (threadDoc.data()?.ownerId !== userId) {
      throw new HttpsError("permission-denied", "Not your thread.");
    }

    const messagesSnap = await db
      .collection("bereanThreads")
      .doc(threadId)
      .collection("messages")
      .orderBy("createdAt", "asc")
      .limit(40)
      .get();

    const transcript = messagesSnap.docs
      .map((d) => `${d.data().role === "assistant" ? "Berean" : "You"}: ${d.data().text ?? ""}`)
      .join("\n");

    if (!transcript.trim()) return { summary: "No messages to summarize yet." };

    const summary = await callAnthropic(
      anthropicApiKey.value(),
      `Summarize this biblical study conversation in 2–3 concise sentences, emphasising key scripture insights and spiritual growth points:\n\n${transcript}`,
      300
    );

    await db.collection("bereanThreads").doc(threadId).update({
      summaryText: summary,
      summaryGeneratedAt: FieldValue.serverTimestamp(),
    });

    return { summary };
  }
);

// ---------------------------------------------------------------------------
// compareBibleTranslations
// ---------------------------------------------------------------------------

export const compareBibleTranslations = onCall(
  { region: "us-central1", secrets: [anthropicApiKey] , enforceAppCheck: true }, 
  async (request: CallableRequest) => {
    requireAuth(request);
    const { reference, translations } = request.data as {
      reference: string;
      translations?: string[];
    };

    if (!reference) throw new HttpsError("invalid-argument", "reference is required.");
    const tList = (translations?.length ? translations : ["ESV", "NIV", "KJV", "NLT"]).slice(0, 5);

    const rawText = await callAnthropic(
      anthropicApiKey.value(),
      `For the Bible verse "${reference}", provide the text in these translations: ${tList.join(", ")}.
Then give a 2–3 sentence scholarly commentary on how the translations differ and what the original Greek/Hebrew nuance is.
Return JSON: { "translations": { ${tList.map((t) => `"${t}": "..."`).join(", ")} }, "commentary": "..." }`,
      800
    );

    let parsed: { translations: Record<string, string>; commentary: string } = {
      translations: {},
      commentary: rawText,
    };
    try {
      const match = rawText.match(/\{[\s\S]*\}/);
      if (match) parsed = JSON.parse(match[0]);
    } catch { /* use fallback */ }

    return parsed;
  }
);

// ---------------------------------------------------------------------------
// generateBereanFollowUps
// ---------------------------------------------------------------------------

export const generateBereanFollowUps = onCall(
  { region: "us-central1", secrets: [anthropicApiKey] , enforceAppCheck: true }, 
  async (request: CallableRequest) => {
    requireAuth(request);
    const { sessionId, lastResponseText, passage } = request.data as {
      sessionId: string;
      lastResponseText: string;
      passage?: string;
    };

    if (!lastResponseText) throw new HttpsError("invalid-argument", "lastResponseText required.");

    const rawText = await callAnthropic(
      anthropicApiKey.value(),
      `Based on this Berean AI biblical study response${passage ? ` about ${passage}` : ""}, generate 3 short follow-up questions a student might ask next. Make them specific, spiritually insightful, and grounded in scripture.
Response: "${lastResponseText.slice(0, 600)}"
Return JSON array: ["question1", "question2", "question3"]`,
      200
    );

    let followUps: string[] = [];
    try {
      const match = rawText.match(/\[[\s\S]*\]/);
      if (match) followUps = JSON.parse(match[0]);
    } catch { /* empty */ }

    if (sessionId) {
      await db.collection("bereanSessions").doc(sessionId).set(
        { followUpSuggestions: followUps, followUpsGeneratedAt: FieldValue.serverTimestamp() },
        { merge: true }
      );
    }

    return { followUps };
  }
);

// ---------------------------------------------------------------------------
// linkBereanContext
// ---------------------------------------------------------------------------

export const linkBereanContext = onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request: CallableRequest) => {
    const userId = requireAuth(request);
    const { sessionId, linkedEntityType, linkedEntityId, notes } = request.data as {
      sessionId: string;
      linkedEntityType: string;
      linkedEntityId: string;
      notes?: string;
    };

    const ref = await db.collection("bereanContextPermissions").add({
      userId,
      sessionId,
      linkedEntityType,
      linkedEntityId,
      notes: notes ?? null,
      linkedAt: FieldValue.serverTimestamp(),
    });

    return { linked: true, linkId: ref.id };
  }
);

// ---------------------------------------------------------------------------
// unlinkBereanContext
// ---------------------------------------------------------------------------

export const unlinkBereanContext = onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request: CallableRequest) => {
    const userId = requireAuth(request);
    const { linkId } = request.data as { linkId: string };

    const ref = db.collection("bereanContextPermissions").doc(linkId);
    const snap = await ref.get();
    if (!snap.exists || snap.data()?.userId !== userId) {
      throw new HttpsError("not-found", "Link not found.");
    }
    await ref.delete();
    return { unlinked: true };
  }
);

// ---------------------------------------------------------------------------
// classifyBereanSafety
// ---------------------------------------------------------------------------

export const classifyBereanSafety = onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request: CallableRequest) => {
    requireAuth(request);
    const { text } = request.data as { text: string };
    if (!text) throw new HttpsError("invalid-argument", "text required.");

    const CRISIS = [
      /\b(want to die|end my life|kill myself|suicide|self.harm)\b/i,
      /\b(hopeless|worthless|nobody cares)\b/i,
    ];
    const THEOLOGY = [/\b(polytheism|pantheism|salvation by works alone)\b/i];

    let safetyClass: "safe" | "crisis" | "theologicalConcern" = "safe";
    let userMessage: string | null = null;

    if (CRISIS.some((p) => p.test(text))) {
      safetyClass = "crisis";
      userMessage = "If you're struggling, please reach out or call/text 988.";
    } else if (THEOLOGY.some((p) => p.test(text))) {
      safetyClass = "theologicalConcern";
      userMessage = "Berean will gently note where this diverges from mainstream evangelical theology.";
    }

    return { safetyClass, userMessage };
  }
);

// ---------------------------------------------------------------------------
// updateBereanPreferences
// ---------------------------------------------------------------------------

export const updateBereanPreferences = onCall(
  { region: "us-central1" , enforceAppCheck: true }, 
  async (request: CallableRequest) => {
    const userId = requireAuth(request);
    const { preferences } = request.data as { preferences: Record<string, unknown> };

    const ALLOWED = new Set([
      "defaultMode", "responseStyle", "preferredTranslation",
      "theologicalLens", "citationDepth", "followUpsEnabled",
      "memoryEnabled", "contextBridgeEnabled",
    ]);

    const safe: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp() };
    for (const [k, v] of Object.entries(preferences ?? {})) {
      if (ALLOWED.has(k)) safe[k] = v;
    }

    await db.collection("bereanPreferences").doc(userId).set(safe, { merge: true });
    return { updated: true };
  }
);

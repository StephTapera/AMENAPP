/**
 * selahBerean.ts
 *
 * Berean Island — Wave 3 Selah Intelligence callables:
 *   generateDiscussionGuide  — group notebook discussion guide for a Table
 *   retrievePersonalContext  — server-side personal context retrieval (Tier S + C only)
 *
 * Region: us-central1
 *
 * TIER P IMPOSSIBILITY:
 *   retrievePersonalContext validates that tierFilter is never "P".
 *   The allowed set of Firestore paths is hardcoded to Tier S + C collections.
 *   Private/E2EE message paths are not present in this file.
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

const db = getFirestore();
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// ---------------------------------------------------------------------------
// Model config (matches rest of codebase)
// ---------------------------------------------------------------------------

const HAIKU_MODEL = "claude-haiku-4-5-20251001";

// ---------------------------------------------------------------------------
// Auth helper
// ---------------------------------------------------------------------------

function requireAuth(request: CallableRequest): string {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }
  return request.auth.uid;
}

// ---------------------------------------------------------------------------
// Anthropic helper (matches bereanExtended.ts pattern)
// ---------------------------------------------------------------------------

async function callAnthropic(
  apiKey: string,
  userPrompt: string,
  maxTokens = 600
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

  const data = await response.json() as {
    content?: Array<{ type?: string; text?: string }>;
  };
  return data.content?.find((b) => b.type === "text")?.text ?? "";
}

// ---------------------------------------------------------------------------
// Allowed Tier S + C collection paths
// Tier P paths (directMessages, privateNotes, e2eeThreads) are absent by design.
// ---------------------------------------------------------------------------

function allowedPaths(uid: string) {
  return {
    notes:         `notes/${uid}/entries`,
    commitments:   `users/${uid}/prayerCommitments`,
    spaceActivity: `users/${uid}/spaceActivity`,
    sharedStudies: `users/${uid}/sharedStudies`,
  };
}

// ---------------------------------------------------------------------------
// generateDiscussionGuide
// ---------------------------------------------------------------------------

export const generateDiscussionGuide = onCall(
  { region: "us-central1", secrets: [anthropicApiKey], enforceAppCheck: true },
  async (request: CallableRequest) => {
    requireAuth(request);

    const { tableId } = request.data as { tableId: string };
    if (!tableId || typeof tableId !== "string") {
      throw new HttpsError("invalid-argument", "tableId is required.");
    }

    logger.info("[selahBerean] generateDiscussionGuide", { tableId });

    // Read shared highlights for this table
    const entriesSnap = await db
      .collection("tables")
      .doc(tableId)
      .collection("notebookEntries")
      .orderBy("createdAt", "desc")
      .limit(50)
      .get();

    const highlights: string[] = entriesSnap.docs.map(
      (doc) => (doc.data()["highlight"] as string) ?? ""
    ).filter((h) => h.length > 0);

    if (highlights.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "No highlights found for this table. Add highlights before generating a guide."
      );
    }

    const highlightBlock = highlights.map((h, i) => `${i + 1}. "${h}"`).join("\n");

    const prompt = `You are Berean, a scripture-grounded AI companion helping a Bible study group.
Below are highlights shared by group members for an upcoming discussion.

Highlights:
${highlightBlock}

Generate a discussion guide with:
1. QUESTIONS: Exactly 3 to 5 open-ended discussion questions that arise naturally from these highlights.
2. THEMES: 2 to 4 emerging themes you notice across the highlights.

Return ONLY valid JSON with this shape:
{
  "questions": ["...", "...", "..."],
  "themes": ["...", "..."]
}`;

    const apiKey = anthropicApiKey.value();
    const raw = await callAnthropic(apiKey, prompt, 600);

    let parsed: { questions: string[]; themes: string[] };
    try {
      // Extract JSON even if the model wraps it in markdown
      const jsonMatch = raw.match(/\{[\s\S]*\}/);
      parsed = JSON.parse(jsonMatch ? jsonMatch[0] : raw);
    } catch {
      logger.error("[selahBerean] Failed to parse generateDiscussionGuide response", { raw });
      throw new HttpsError("internal", "Failed to parse discussion guide from AI.");
    }

    const questions: string[] = Array.isArray(parsed.questions) ? parsed.questions.slice(0, 5) : [];
    const themes: string[] = Array.isArray(parsed.themes) ? parsed.themes.slice(0, 4) : [];

    // Store guide at tables/{tableId}/discussionGuides/{guideId}
    const guideRef = db
      .collection("tables")
      .doc(tableId)
      .collection("discussionGuides")
      .doc();

    const guide = {
      tableId,
      questions,
      themes,
      generatedAt: FieldValue.serverTimestamp(),
      highlightCount: highlights.length,
    };

    await guideRef.set(guide);

    return {
      tableId,
      questions,
      themes,
      generatedAt: new Date().toISOString(),
    };
  }
);

// ---------------------------------------------------------------------------
// retrievePersonalContext
// ---------------------------------------------------------------------------

// Allowed tier values — "P" is explicitly excluded and rejected
const ALLOWED_TIERS = new Set<string>(["S", "C"]);

export const retrievePersonalContext = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request: CallableRequest) => {
    const uid = requireAuth(request);

    const {
      query,
      tierFilter,
      limit: rawLimit = 20,
    } = request.data as {
      query: string;
      uid?: string;
      tierFilter: string | string[];
      limit?: number;
    };

    // CRITICAL: Reject any request that includes Tier P
    // This is the server-side enforcement of the impossibility guarantee.
    const tierArray = Array.isArray(tierFilter)
      ? tierFilter
      : [tierFilter];

    for (const t of tierArray) {
      if (t === "P") {
        logger.warn("[selahBerean] retrievePersonalContext rejected Tier P request", { uid });
        throw new HttpsError(
          "invalid-argument",
          "Tier P (private/E2EE) content is not accessible through this endpoint."
        );
      }
      if (!ALLOWED_TIERS.has(t)) {
        throw new HttpsError(
          "invalid-argument",
          `Unknown tier filter: "${t}". Allowed values: S, C.`
        );
      }
    }

    const limit = Math.min(Math.max(1, rawLimit), 50);
    const tiers = new Set(tierArray);
    const paths = allowedPaths(uid);

    logger.info("[selahBerean] retrievePersonalContext", { uid, tiers: [...tiers], limit });

    const chunks: Array<{
      content: string;
      source: string;
      tier: string;
      timestamp: string;
      humanLabel: string | null;
    }> = [];

    // --- Tier S: notes ---
    if (tiers.has("S")) {
      const notesSnap = await db
        .collection(paths.notes)
        .orderBy("createdAt", "desc")
        .limit(Math.min(limit, 20))
        .get();

      for (const doc of notesSnap.docs) {
        const data = doc.data();
        const text = data["text"] as string | undefined;
        const ts = (data["createdAt"] as Timestamp | undefined)?.toDate();
        if (!text || !ts) continue;
        chunks.push({
          content: text,
          source: "notes",
          tier: "S",
          timestamp: ts.toISOString(),
          humanLabel: `your note from ${formatDate(ts)}`,
        });
      }

      // --- Tier S: commitments ---
      const commitSnap = await db
        .collection(paths.commitments)
        .orderBy("createdAt", "desc")
        .limit(Math.min(limit, 10))
        .get();

      for (const doc of commitSnap.docs) {
        const data = doc.data();
        const text = data["commitmentText"] as string | undefined;
        const ts = (data["createdAt"] as Timestamp | undefined)?.toDate();
        const subject = data["subject"] as string | undefined;
        if (!text || !ts) continue;
        const humanLabel = subject
          ? `your commitment to pray for ${subject}`
          : `your prayer commitment from ${formatDate(ts)}`;
        chunks.push({
          content: text,
          source: "commitments",
          tier: "S",
          timestamp: ts.toISOString(),
          humanLabel,
        });
      }
    }

    // --- Tier C: space activity + shared studies ---
    if (tiers.has("C")) {
      const spaceSnap = await db
        .collection(paths.spaceActivity)
        .orderBy("joinedAt", "desc")
        .limit(Math.min(limit, 10))
        .get();

      for (const doc of spaceSnap.docs) {
        const data = doc.data();
        const spaceName = data["spaceName"] as string | undefined;
        const ts = (data["joinedAt"] as Timestamp | undefined)?.toDate();
        if (!spaceName || !ts) continue;
        chunks.push({
          content: (data["summary"] as string | undefined) ?? spaceName,
          source: "space_history",
          tier: "C",
          timestamp: ts.toISOString(),
          humanLabel: `your activity in ${spaceName}`,
        });
      }

      const studiesSnap = await db
        .collection(paths.sharedStudies)
        .orderBy("updatedAt", "desc")
        .limit(Math.min(limit, 10))
        .get();

      for (const doc of studiesSnap.docs) {
        const data = doc.data();
        const topic = data["topic"] as string | undefined;
        const ts = (data["updatedAt"] as Timestamp | undefined)?.toDate();
        const ref = data["scriptureRef"] as string | undefined;
        if (!topic || !ts) continue;
        const humanLabel = ref ? `your study on ${ref}` : `your study from ${formatDate(ts)}`;
        chunks.push({
          content: (data["summary"] as string | undefined) ?? topic,
          source: "shared_studies",
          tier: "C",
          timestamp: ts.toISOString(),
          humanLabel,
        });
      }
    }

    // Hard filter — defensive, belt-and-suspenders (Tier P should be structurally impossible)
    const sanitized = chunks.filter((c) => c.tier !== "P").slice(0, limit);

    return { chunks: sanitized };
  }
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatDate(date: Date): string {
  return date.toLocaleDateString("en-US", { month: "long", day: "numeric" });
}

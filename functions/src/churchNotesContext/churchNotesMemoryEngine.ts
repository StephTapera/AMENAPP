// churchNotesMemoryEngine.ts
// Tracks patterns across a user's Church Notes: recurring themes, repeated scripture,
// connected prayers, unresolved reflections. Private by design — never exposed to groups.

import * as admin from "firebase-admin";
import Anthropic from "@anthropic-ai/sdk";
import {
  CNMemorySnapshot,
  CNMemoryEntry,
  CNProvenanceLabel,
  CN_MAX_INPUT_CHARS,
  CN_SYSTEM_PROMPT_HEADER,
} from "./types.js";

const anthropic = new Anthropic();
const db = admin.firestore();

// MARK: - Load Note History (compressed for LLM)

async function loadNoteHistory(userId: string, limit = 20): Promise<{
  texts: string[];
  titles: string[];
  scriptures: string[];
}> {
  const snap = await db
    .collection("churchNotes")
    .where("userId", "==", userId)
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get();

  const texts: string[] = [];
  const titles: string[] = [];
  const scriptures: string[] = [];

  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.title) titles.push(String(data.title));
    if (data.sermonTitle) titles.push(String(data.sermonTitle));
    if (Array.isArray(data.scriptureReferences)) {
      scriptures.push(...(data.scriptureReferences as string[]));
    }
    // Use summary draft if available (already approved/processed) — not raw block content
    if (data.summaryDraft) texts.push(String(data.summaryDraft));
    else if (data.transcriptText) texts.push(String(data.transcriptText).slice(0, 800));
  }

  return { texts, titles, scriptures };
}

// MARK: - Pattern Analysis

async function analyzePatterns(
  userId: string,
  history: { texts: string[]; titles: string[]; scriptures: string[] }
): Promise<Pick<CNMemorySnapshot, "topThemes" | "repeatedScriptures" | "postureTrend" | "recurringPatterns">> {
  const combined = history.texts.join("\n\n").slice(0, CN_MAX_INPUT_CHARS);

  // Count repeated scripture references
  const scriptureCount: Record<string, number> = {};
  for (const ref of history.scriptures) {
    scriptureCount[ref] = (scriptureCount[ref] ?? 0) + 1;
  }
  const repeatedScriptures = Object.entries(scriptureCount)
    .filter(([, count]) => count >= 2)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([ref]) => ref);

  if (combined.length < 100) {
    return {
      topThemes: [],
      repeatedScriptures,
      postureTrend: "not enough notes yet",
      recurringPatterns: [],
    };
  }

  const prompt = `${CN_SYSTEM_PROMPT_HEADER}

Below are summaries from a person's recent church notes. Identify patterns that recur across multiple notes.

Notes:
${combined}

Return JSON:
{
  "topThemes": [string],        // up to 5 recurring themes
  "postureTrend": string,       // one sentence about the overall spiritual posture trend (humble, observational)
  "recurringPatterns": [
    { "type": "recurringTheme"|"repeatedVerse"|"sermonContinuity", "title": string, "summary": string }
  ]
}

Rules:
- topThemes: max 5, based on actual repetition across notes
- postureTrend: 1 sentence, humble. E.g. "Your notes often return to surrender and trust."
- recurringPatterns: max 5, only include patterns seen in 2+ notes
- Never diagnose. Never claim certainty. Never say "God told you."
- Return ONLY valid JSON.`;

  const message = await anthropic.messages.create({
    model: "claude-haiku-4-5-20251001",
    max_tokens: 2000,
    messages: [{ role: "user", content: prompt }],
  });

  const raw = message.content[0].type === "text" ? message.content[0].text : "{}";
  let parsed: Record<string, unknown>;
  try { parsed = JSON.parse(raw); } catch { parsed = {}; }

  const prov: CNProvenanceLabel = {
    source: "prior notes",
    confidence: "possible",
    whySuggested: "Detected from patterns across your recent Church Notes",
  };

  const recurringPatterns: CNMemoryEntry[] = ((parsed.recurringPatterns as unknown[]) ?? []).slice(0, 5).map((p: unknown) => {
    const pattern = p as Record<string, unknown>;
    const validTypes = ["recurringTheme", "answeredPrayer", "repeatedVerse", "sermonContinuity", "reflectionCompleted", "actionFollowedThrough"];
    return {
      id: crypto.randomUUID(),
      userId,
      type: (validTypes.includes(String(pattern.type)) ? String(pattern.type) : "recurringTheme") as CNMemoryEntry["type"],
      title: String(pattern.title ?? ""),
      summary: String(pattern.summary ?? ""),
      relatedNoteIds: [],
      date: admin.firestore.Timestamp.now(),
      isPrivate: true,
      provenance: prov,
    };
  });

  return {
    topThemes: ((parsed.topThemes as string[]) ?? []).slice(0, 5),
    repeatedScriptures,
    postureTrend: String(parsed.postureTrend ?? ""),
    recurringPatterns,
  };
}

// MARK: - Main Export

export async function generateChurchNotesMemorySnapshot(userId: string): Promise<CNMemorySnapshot> {
  const history = await loadNoteHistory(userId);
  const patterns = await analyzePatterns(userId, history);

  const snapshot: CNMemorySnapshot = {
    userId,
    ...patterns,
    lastUpdatedAt: admin.firestore.Timestamp.now(),
  };

  // Save to user's private memory path
  await db
    .collection("users")
    .doc(userId)
    .collection("churchNotesMemory")
    .doc("snapshot")
    .set(snapshot);

  // Save individual recurring pattern entries
  for (const entry of snapshot.recurringPatterns) {
    await db
      .collection("users")
      .doc(userId)
      .collection("churchNotesMemory")
      .doc(entry.id)
      .set(entry);
  }

  return snapshot;
}

export async function loadChurchNotesMemorySnapshot(userId: string): Promise<CNMemorySnapshot | null> {
  const snap = await db
    .collection("users")
    .doc(userId)
    .collection("churchNotesMemory")
    .doc("snapshot")
    .get();
  return snap.exists ? (snap.data() as CNMemorySnapshot) : null;
}

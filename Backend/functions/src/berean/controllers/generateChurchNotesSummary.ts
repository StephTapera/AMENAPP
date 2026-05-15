import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

import { analyticsService } from "../services/AnalyticsService";

type NoteSummaryInput = {
  noteId: string;
  title?: string;
  sermonTitle?: string;
  sermonSpeaker?: string;
  scriptureReferences?: string[];
  text: string;
  isPrivateNote?: boolean;
};

type LLMNotesSummary = {
  reflectionStatement?: string;
  postureTrend?: string | null;
  topThemes?: Array<{ theme: string; noteCount: number; recentNoteIds?: string[] }>;
  repeatedScriptures?: Array<{ reference: string; book?: string; timesAttached: number }>;
};

export const bereanGenerateChurchNotesSummary = onCall(
  { region: "us-central1", timeoutSeconds: 45 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }

    const userId = request.auth.uid;
    const {
      noteIds = [],
      notes = [],
      isPrivateNote = true,
    } = request.data as {
      userId?: string;
      noteIds?: string[];
      notes?: NoteSummaryInput[];
      isPrivateNote?: boolean;
    };

    if (!Array.isArray(noteIds) || !Array.isArray(notes) || notes.length === 0) {
      throw new HttpsError("invalid-argument", "notes and noteIds are required.");
    }

    const sanitizedNotes = notes
      .filter((note) => typeof note?.noteId === "string" && typeof note?.text === "string")
      .slice(0, 20)
      .map((note) => ({
        noteId: note.noteId,
        title: (note.title ?? "").trim(),
        sermonTitle: (note.sermonTitle ?? "").trim(),
        sermonSpeaker: (note.sermonSpeaker ?? "").trim(),
        scriptureReferences: Array.isArray(note.scriptureReferences) ? note.scriptureReferences : [],
        text: note.text.trim().slice(0, 4000),
        isPrivateNote: note.isPrivateNote !== false,
      }))
      .filter((note) => note.text.length > 0);

    if (sanitizedNotes.length === 0) {
      throw new HttpsError("invalid-argument", "At least one note with text is required.");
    }

    const startedAt = await analyticsService.logRequestStart(
      userId,
      `church-notes-summary-${Date.now()}`
    );

    const callable = admin.app().functions().httpsCallable("bereanChatProxy");
    const systemPrompt = [
      "You summarize private church notes for the note owner inside AMEN.",
      "These notes are private. Never claim divine certainty. Speak reflectively and cautiously.",
      "Return strict JSON only.",
      "Schema:",
      JSON.stringify({
        reflectionStatement: "string",
        postureTrend: "comforted | convicted | expectant | burdened | grateful | confused | repentant | encouraged | challenged | null",
        topThemes: [{ theme: "string", noteCount: 1, recentNoteIds: ["string"] }],
        repeatedScriptures: [{ reference: "string", book: "string", timesAttached: 1 }],
      }),
    ].join("\n");

    const userPrompt = JSON.stringify({
      instruction:
        "Summarize recurring themes across these private church notes. Keep the reflectionStatement concise and pastoral without implying revelation. Use only the provided notes.",
      isPrivateNote,
      notes: sanitizedNotes,
    });

    let parsed: LLMNotesSummary | null = null;

    try {
      const result = await callable({
        message: userPrompt,
        systemPromptSuffix: systemPrompt,
        maxTokens: 1200,
        modelId: "claude-sonnet-4-5",
      });
      const data = result.data as Record<string, unknown>;
      const raw = String(data.response ?? data.text ?? "");
      parsed = parseSummaryJSON(raw);
    } catch (error) {
      console.error("[bereanGenerateChurchNotesSummary] proxy call failed:", error);
    }

    const nowSeconds = Math.floor(Date.now() / 1000);
    const fallback = buildFallbackSummary(userId, sanitizedNotes, nowSeconds);
    const summary = mergeWithFallback(userId, sanitizedNotes, parsed, fallback, nowSeconds);

    await analyticsService.logRequestComplete(
      userId,
      `church-notes-summary-${sanitizedNotes.length}`,
      startedAt,
      false,
      "church_notes_summary"
    );

    return { success: true, summary };
  }
);

function parseSummaryJSON(raw: string): LLMNotesSummary | null {
  const cleaned = raw
    .replace(/^```(?:json)?\n?/m, "")
    .replace(/\n?```$/m, "")
    .trim();

  try {
    return JSON.parse(cleaned) as LLMNotesSummary;
  } catch {
    return null;
  }
}

function buildFallbackSummary(userId: string, notes: NoteSummaryInput[], nowSeconds: number) {
  const themeCounts = new Map<string, { count: number; noteIds: string[] }>();
  const scriptureCounts = new Map<string, number>();

  for (const note of notes) {
    for (const ref of note.scriptureReferences ?? []) {
      scriptureCounts.set(ref, (scriptureCounts.get(ref) ?? 0) + 1);
    }

    const tokens = note.text
      .toLowerCase()
      .split(/[^a-z0-9]+/)
      .filter((token) => token.length >= 5)
      .slice(0, 120);

    for (const token of tokens) {
      const existing = themeCounts.get(token) ?? { count: 0, noteIds: [] };
      existing.count += 1;
      if (!existing.noteIds.includes(note.noteId)) {
        existing.noteIds.push(note.noteId);
      }
      themeCounts.set(token, existing);
    }
  }

  const topThemes = [...themeCounts.entries()]
    .sort((lhs, rhs) => rhs[1].count - lhs[1].count)
    .slice(0, 4)
    .map(([theme, value]) => ({
      id: theme,
      theme: theme.charAt(0).toUpperCase() + theme.slice(1),
      noteCount: value.count,
      recentNoteIds: value.noteIds.slice(-3),
      firstSeenAt: nowSeconds,
      lastSeenAt: nowSeconds,
    }));

  const repeatedScriptures = [...scriptureCounts.entries()]
    .filter(([, count]) => count > 1)
    .slice(0, 4)
    .map(([reference, timesAttached]) => ({
      reference,
      book: reference.split(" ")[0] ?? reference,
      timesAttached,
      lastSeenAt: nowSeconds,
    }));

  return {
    id: userId,
    topThemes,
    repeatedScriptures,
    postureTrend: null,
    noteCountLast30Days: notes.length,
    noteCountAllTime: notes.length,
    reflectionStatement:
      topThemes.length > 0
        ? `Your recent notes often return to ${topThemes
            .slice(0, 2)
            .map((item) => item.theme.toLowerCase())
            .join(" and ")}.`
        : "",
    generatedAt: nowSeconds,
    showInsights: true,
    dismissedAt: null,
  };
}

function mergeWithFallback(
  userId: string,
  notes: NoteSummaryInput[],
  parsed: LLMNotesSummary | null,
  fallback: ReturnType<typeof buildFallbackSummary>,
  nowSeconds: number
) {
  const topThemes = parsed?.topThemes?.length
    ? parsed.topThemes.slice(0, 6).map((item) => ({
        id: item.theme.toLowerCase(),
        theme: item.theme,
        noteCount: item.noteCount,
        recentNoteIds: item.recentNoteIds?.slice(0, 3) ?? notes.slice(0, 3).map((note) => note.noteId),
        firstSeenAt: nowSeconds,
        lastSeenAt: nowSeconds,
      }))
    : fallback.topThemes;

  const repeatedScriptures = parsed?.repeatedScriptures?.length
    ? parsed.repeatedScriptures.slice(0, 4).map((item) => ({
        reference: item.reference,
        book: item.book ?? item.reference.split(" ")[0] ?? item.reference,
        timesAttached: item.timesAttached,
        lastSeenAt: nowSeconds,
      }))
    : fallback.repeatedScriptures;

  return {
    id: userId,
    topThemes,
    repeatedScriptures,
    postureTrend: parsed?.postureTrend ?? fallback.postureTrend,
    noteCountLast30Days: notes.length,
    noteCountAllTime: notes.length,
    reflectionStatement: parsed?.reflectionStatement?.trim() || fallback.reflectionStatement,
    generatedAt: nowSeconds,
    showInsights: true,
    dismissedAt: null,
  };
}

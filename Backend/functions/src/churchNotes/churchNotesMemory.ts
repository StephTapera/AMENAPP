import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const MEMORY_RATE_LIMIT_WINDOW_MS = 60_000;
const MEMORY_RATE_LIMIT_MAX_CALLS = 10;

interface ThemeAccumulator {
  count: number;
  noteIds: string[];
}

export const analyzeChurchNoteMemory = onCall(
  { enforceAppCheck: true, maxInstances: 10 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const uid = request.auth.uid;
    const limit = Math.min(
      (request.data as { limit?: number } | null)?.limit ?? 30,
      50
    );
    const excludeId: string | undefined = (
      request.data as { currentNoteId?: string } | null
    )?.currentNoteId;

    const db = admin.firestore();

    // Simple per-user rate limit via Firestore counter
    const rateLimitRef = db
      .collection("rateLimits")
      .doc(`churchNotesMemory_${uid}`);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(rateLimitRef);
      const now = Date.now();
      const windowStart: number = snap.data()?.windowStart ?? 0;
      const callCount: number = snap.data()?.callCount ?? 0;

      if (now - windowStart < MEMORY_RATE_LIMIT_WINDOW_MS) {
        if (callCount >= MEMORY_RATE_LIMIT_MAX_CALLS) {
          throw new HttpsError(
            "resource-exhausted",
            "Too many requests. Please wait before analyzing notes again."
          );
        }
        tx.set(rateLimitRef, { windowStart, callCount: callCount + 1 }, { merge: true });
      } else {
        tx.set(rateLimitRef, { windowStart: now, callCount: 1 });
      }
    });

    // Check kill switch
    const flagsSnap = await db.collection("system").doc("amenAIFlags").get();
    const flags = flagsSnap.data() ?? {};
    if (flags["churchNotesProcessingKillSwitch"] === true) {
      throw new HttpsError(
        "failed-precondition",
        "Church Notes Intelligence is temporarily unavailable."
      );
    }

    // Fetch recent notes owned by this user
    const snap = await db
      .collection("churchNotes")
      .where("userId", "==", uid)
      .orderBy("createdAt", "desc")
      .limit(limit + 1)
      .get();

    const notes = snap.docs
      .filter((d) => d.id !== excludeId)
      .slice(0, limit);

    if (notes.length === 0) {
      return {
        topThemes: [],
        recentScriptures: [],
        prayerPatterns: [],
        growthInsights: [],
        relatedNoteIds: [],
        notesAnalyzed: 0,
      };
    }

    // Accumulate themes (from tags), scripture refs, and prayer topics
    const themeCounts: Record<string, ThemeAccumulator> = {};
    const scriptureCounts: Record<string, number> = {};
    const prayerTopics: string[] = [];

    for (const doc of notes) {
      const data = doc.data();
      const noteId = doc.id;

      // Themes from tags array
      const tags: string[] = Array.isArray(data["tags"]) ? data["tags"] as string[] : [];
      for (const tag of tags) {
        const key = tag.toLowerCase().trim();
        if (!key) continue;
        if (!themeCounts[key]) {
          themeCounts[key] = { count: 0, noteIds: [] };
        }
        themeCounts[key].count++;
        if (!themeCounts[key].noteIds.includes(noteId)) {
          themeCounts[key].noteIds.push(noteId);
        }
      }

      // Scripture references
      const refs: string[] = Array.isArray(data["scriptureReferences"])
        ? data["scriptureReferences"] as string[]
        : [];
      for (const ref of refs) {
        scriptureCounts[ref] = (scriptureCounts[ref] ?? 0) + 1;
      }

      // Prayer topic heuristic: check title/sermonTitle for prayer keywords
      const titleRaw: unknown = data["title"] ?? data["sermonTitle"] ?? "";
      const title = typeof titleRaw === "string" ? titleRaw : "";
      const titleLower = title.toLowerCase();
      if (
        titleLower.includes("prayer") ||
        titleLower.includes("pray") ||
        titleLower.includes("intercede")
      ) {
        if (title && !prayerTopics.includes(title)) {
          prayerTopics.push(title);
        }
      }
    }

    // Build sorted top themes (min count 2 to filter noise)
    const topThemes = Object.entries(themeCounts)
      .filter(([, v]) => v.count >= 2)
      .sort((a, b) => b[1].count - a[1].count)
      .slice(0, 8)
      .map(([label, v]) => ({
        label,
        count: v.count,
        exampleNoteIds: v.noteIds.slice(0, 3),
      }));

    // Top scripture references
    const recentScriptures = Object.entries(scriptureCounts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 6)
      .map(([reference, count]) => ({ reference, count }));

    // Growth insight strings
    const growthInsights: string[] = [];
    for (const theme of topThemes.slice(0, 3)) {
      growthInsights.push(
        `"${capitalize(theme.label)}" has appeared across ${theme.count} of your recent notes`
      );
    }
    if (recentScriptures.length > 0) {
      growthInsights.push(
        `${recentScriptures[0].reference} is your most referenced scripture recently`
      );
    }

    // Related note IDs: notes sharing at least 1 tag with a top theme
    const topThemeLabels = new Set(topThemes.map((t) => t.label));
    const relatedNoteIds = notes
      .filter((d) => {
        const tags: string[] = Array.isArray(d.data()["tags"])
          ? (d.data()["tags"] as string[]).map((t: string) => t.toLowerCase().trim())
          : [];
        return tags.some((t) => topThemeLabels.has(t));
      })
      .map((d) => d.id)
      .slice(0, 10);

    return {
      topThemes,
      recentScriptures,
      prayerPatterns: prayerTopics.slice(0, 5),
      growthInsights,
      relatedNoteIds,
      notesAnalyzed: notes.length,
    };
  }
);

function capitalize(str: string): string {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

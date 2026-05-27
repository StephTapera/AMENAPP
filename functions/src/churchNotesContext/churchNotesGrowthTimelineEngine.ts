// churchNotesGrowthTimelineEngine.ts
// Builds a private Spiritual Growth Timeline from patterns in a user's Church Notes.
// Only the owner can read their timeline. Never exposed to group or public contexts.

import * as admin from "firebase-admin";
import {
  CNGrowthTimelineEntry,
  CNMemorySnapshot,
  CNProvenanceLabel,
} from "./types.js";
import { loadChurchNotesMemorySnapshot, generateChurchNotesMemorySnapshot } from "./churchNotesMemoryEngine.js";

const db = admin.firestore();

// MARK: - Timeline Entry Builder

function buildTimelineEntriesFromSnapshot(
  userId: string,
  snapshot: CNMemorySnapshot
): CNGrowthTimelineEntry[] {
  const entries: CNGrowthTimelineEntry[] = [];

  const prov: CNProvenanceLabel = {
    source: "prior notes",
    confidence: "possible",
    whySuggested: "Detected from patterns across your saved Church Notes",
  };

  // Recurring themes
  for (const theme of snapshot.topThemes.slice(0, 3)) {
    entries.push({
      id: crypto.randomUUID(),
      userId,
      type: "recurringTheme",
      title: theme,
      summary: `"${theme}" appears repeatedly in your notes. This may connect to something ongoing in your spiritual life.`,
      relatedNoteIds: [],
      date: admin.firestore.Timestamp.now(),
      isPrivate: true,
      provenance: prov,
    });
  }

  // Repeated scripture
  for (const ref of snapshot.repeatedScriptures.slice(0, 3)) {
    entries.push({
      id: crypto.randomUUID(),
      userId,
      type: "repeatedVerse",
      title: ref,
      summary: `You've referenced ${ref} multiple times across your notes.`,
      relatedNoteIds: [],
      date: admin.firestore.Timestamp.now(),
      isPrivate: true,
      provenance: {
        source: "prior notes",
        confidence: "confirmed",
        whySuggested: `${ref} appears in multiple saved notes`,
      },
    });
  }

  // Memory snapshot patterns
  for (const pattern of snapshot.recurringPatterns) {
    entries.push({
      id: pattern.id,
      userId,
      type: pattern.type,
      title: pattern.title,
      summary: pattern.summary,
      relatedNoteIds: pattern.relatedNoteIds,
      date: pattern.date,
      isPrivate: true,
      provenance: pattern.provenance,
    });
  }

  return entries;
}

// MARK: - Answered Prayer Detection

async function loadAnsweredPrayers(userId: string): Promise<CNGrowthTimelineEntry[]> {
  const snap = await db
    .collection("users")
    .doc(userId)
    .collection("prayerItems")
    .where("status", "==", "answered")
    .orderBy("answeredAt", "desc")
    .limit(5)
    .get();

  return snap.docs.map((doc) => {
    const data = doc.data();
    return {
      id: crypto.randomUUID(),
      userId,
      type: "answeredPrayer" as const,
      title: String(data.title ?? "Answered prayer"),
      summary: String(data.notes ?? "You marked this prayer as answered."),
      relatedNoteIds: data.relatedNoteIds ?? [],
      date: data.answeredAt ?? admin.firestore.Timestamp.now(),
      isPrivate: true,
      provenance: {
        source: "your prayer list",
        confidence: "confirmed",
        whySuggested: "You marked this as answered",
      },
    };
  });
}

// MARK: - Persist Timeline

async function persistTimelineEntries(userId: string, entries: CNGrowthTimelineEntry[]): Promise<void> {
  const batch = db.batch();
  for (const entry of entries) {
    const ref = db
      .collection("users")
      .doc(userId)
      .collection("churchNotesMemory")
      .doc(entry.id);
    batch.set(ref, entry, { merge: true });
  }
  await batch.commit();
}

// MARK: - Main Export

export async function generateGrowthTimeline(userId: string): Promise<CNGrowthTimelineEntry[]> {
  // Load or generate memory snapshot
  let snapshot = await loadChurchNotesMemorySnapshot(userId);
  if (!snapshot) {
    snapshot = await generateChurchNotesMemorySnapshot(userId);
  }

  const entries: CNGrowthTimelineEntry[] = [
    ...buildTimelineEntriesFromSnapshot(userId, snapshot),
    ...await loadAnsweredPrayers(userId),
  ];

  // Sort by date descending
  entries.sort((a, b) => {
    const aMs = a.date?.toMillis() ?? 0;
    const bMs = b.date?.toMillis() ?? 0;
    return bMs - aMs;
  });

  await persistTimelineEntries(userId, entries);
  return entries;
}

export async function loadGrowthTimeline(userId: string): Promise<CNGrowthTimelineEntry[]> {
  const snap = await db
    .collection("users")
    .doc(userId)
    .collection("churchNotesMemory")
    .where("isPrivate", "==", true)
    .orderBy("date", "desc")
    .limit(50)
    .get();

  return snap.docs.map((doc) => doc.data() as CNGrowthTimelineEntry);
}

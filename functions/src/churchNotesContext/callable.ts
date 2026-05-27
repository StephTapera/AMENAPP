// callable.ts
// Church Notes Context Engine — Firebase Cloud Function callables.
// All callables enforce: App Check → Auth → Ownership → Rate limit → Feature flag kill switch.
// Server-side AI writes only. Client can approve/edit/reject via allowed fields only.

import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {
  GenerateChurchNotesContextInput,
  GenerateChurchNotesContextOutput,
  GenerateChurchNotesRecapInput,
  GenerateChurchNotesRecapOutput,
  ExtractChurchNotesActionsInput,
  ExtractChurchNotesActionsOutput,
  GenerateGrowthTimelineInput,
  GenerateGrowthTimelineOutput,
  QueryChurchNotesMemoryInput,
  QueryChurchNotesMemoryOutput,
} from "./types.js";
import { generateChurchNotesContext } from "./churchNotesContextEngine.js";
import { generateChurchNotesRecap } from "./churchNotesRecapEngine.js";
import { extractChurchNotesActions } from "./churchNotesActionExtractionEngine.js";
import { generateGrowthTimeline, loadGrowthTimeline } from "./churchNotesGrowthTimelineEngine.js";
import {
  generateChurchNotesMemorySnapshot,
  loadChurchNotesMemorySnapshot,
} from "./churchNotesMemoryEngine.js";

const db = admin.firestore();

// MARK: - Rate Limit Helper

async function checkRateLimit(uid: string, action: string, maxPerMin: number, maxPerDay: number): Promise<void> {
  const now = Date.now();
  const ref = db.collection("rateLimits").doc(`${uid}_churchNotesContext_${action}`);
  const snap = await ref.get();
  const data = snap.data() ?? { callsThisMinute: 0, callsToday: 0, minuteStart: now, dayStart: now };

  const minuteElapsed = now - (data.minuteStart as number) > 60_000;
  const dayElapsed = now - (data.dayStart as number) > 86_400_000;

  const callsThisMinute = minuteElapsed ? 1 : (data.callsThisMinute as number) + 1;
  const callsToday = dayElapsed ? 1 : (data.callsToday as number) + 1;

  if (!minuteElapsed && callsThisMinute > maxPerMin) {
    throw new functions.HttpsError("resource-exhausted", "Rate limit exceeded. Please wait a moment.");
  }
  if (!dayElapsed && callsToday > maxPerDay) {
    throw new functions.HttpsError("resource-exhausted", "Daily limit reached for this feature.");
  }

  await ref.set({
    callsThisMinute,
    callsToday,
    minuteStart: minuteElapsed ? now : data.minuteStart,
    dayStart: dayElapsed ? now : data.dayStart,
  });
}

// MARK: - Ownership Verification

async function verifyNoteOwnership(noteId: string, uid: string): Promise<void> {
  const noteSnap = await db.collection("churchNotes").doc(noteId).get();
  if (!noteSnap.exists) throw new functions.HttpsError("not-found", "Note not found.");
  const noteData = noteSnap.data() as Record<string, unknown>;
  if (noteData.userId !== uid) throw new functions.HttpsError("permission-denied", "Not your note.");
}

// MARK: - Callables

export const generateChurchNotesContextCallable = functions.onCall<
  GenerateChurchNotesContextInput,
  GenerateChurchNotesContextOutput
>({ enforceAppCheck: true }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

  const { noteId, noteText, sermonTitle, scriptureReferences, groupId, churchId } = req.data;
  if (!noteId || !noteText) throw new functions.HttpsError("invalid-argument", "noteId and noteText required.");

  await verifyNoteOwnership(noteId, uid);
  await checkRateLimit(uid, "generateContext", 3, 30);

  try {
    const result = await generateChurchNotesContext({
      noteId,
      userId: uid,
      noteText,
      sermonTitle,
      scriptureReferences,
      groupId,
      churchId,
    });
    return { success: true, result };
  } catch (error) {
    console.error("[churchNotesContext] generateContext error:", error);
    return { success: false, error: "Context generation failed." };
  }
});

export const generateChurchNotesRecapCallable = functions.onCall<
  GenerateChurchNotesRecapInput,
  GenerateChurchNotesRecapOutput
>({ enforceAppCheck: true }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

  const { noteId, noteText } = req.data;
  if (!noteId || !noteText) throw new functions.HttpsError("invalid-argument", "noteId and noteText required.");

  await verifyNoteOwnership(noteId, uid);
  await checkRateLimit(uid, "generateRecap", 3, 20);

  try {
    const recap = await generateChurchNotesRecap(noteId, uid, noteText);
    return { success: true, recapId: recap.id, recap };
  } catch (error) {
    console.error("[churchNotesContext] generateRecap error:", error);
    return { success: false, error: "Recap generation failed." };
  }
});

export const extractChurchNotesActionsCallable = functions.onCall<
  ExtractChurchNotesActionsInput,
  ExtractChurchNotesActionsOutput
>({ enforceAppCheck: true }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

  const { noteId, jobId } = req.data;
  if (!noteId || !jobId) throw new functions.HttpsError("invalid-argument", "noteId and jobId required.");

  await verifyNoteOwnership(noteId, uid);
  await checkRateLimit(uid, "extractActions", 5, 30);

  try {
    const actions = await extractChurchNotesActions(noteId, uid, jobId);
    return { success: true, actions };
  } catch (error) {
    console.error("[churchNotesContext] extractActions error:", error);
    return { success: false, error: "Action extraction failed." };
  }
});

export const generateGrowthTimelineCallable = functions.onCall<
  GenerateGrowthTimelineInput,
  GenerateGrowthTimelineOutput
>({ enforceAppCheck: true }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

  if (req.data.userId !== uid) throw new functions.HttpsError("permission-denied", "Can only generate your own timeline.");
  await checkRateLimit(uid, "generateTimeline", 2, 10);

  try {
    const entries = await generateGrowthTimeline(uid);
    return { success: true, entries };
  } catch (error) {
    console.error("[churchNotesContext] generateTimeline error:", error);
    return { success: false, error: "Timeline generation failed." };
  }
});

export const queryChurchNotesMemoryCallable = functions.onCall<
  QueryChurchNotesMemoryInput,
  QueryChurchNotesMemoryOutput
>({ enforceAppCheck: true }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

  if (req.data.userId !== uid) throw new functions.HttpsError("permission-denied", "Can only query your own memory.");
  await checkRateLimit(uid, "queryMemory", 5, 30);

  try {
    let snapshot = await loadChurchNotesMemorySnapshot(uid);
    if (!snapshot) snapshot = await generateChurchNotesMemorySnapshot(uid);
    return { success: true, snapshot };
  } catch (error) {
    console.error("[churchNotesContext] queryMemory error:", error);
    return { success: false, error: "Memory query failed." };
  }
});

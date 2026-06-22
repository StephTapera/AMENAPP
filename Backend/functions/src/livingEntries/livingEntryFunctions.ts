import * as functions from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {
  classifyWithFallback,
  openAIClassification,
  claudeClassification,
  generateEvolutionSuggestion,
  generateReflectionLearning,
  openaiLivingEntriesApiKey,
  anthropicLivingEntriesApiKey,
} from "./livingEntryAI";
import { evaluateContext } from "./livingEntryContext";
import { buildGentleRegretCopy, calculateIntentGravityScore, clamp01 } from "./livingEntryScoring";

const db = admin.firestore();

function requireAuth(context: { auth?: any; app?: any }): string {
  if (!context.auth) {
    throw new HttpsError("unauthenticated", "Auth required");
  }
  return context.auth.uid;
}

function requireAppCheck(context: { auth?: any; app?: any }) {
  if (context.app == undefined) {
    throw new HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
  }
}

async function enforceLivingEntryRateLimit(userId: string, key: string, maxRequests: number = 30) {
  const bucket = Math.floor(Date.now() / 60_000);
  const ref = db.collection("rateLimits").doc(`living_entries:${key}:${userId}:${bucket}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = snap.exists ? Number(snap.data()?.count ?? 0) : 0;
    if (count >= maxRequests) {
      throw new HttpsError("resource-exhausted", "Rate limit exceeded");
    }
    tx.set(ref, {
      userId,
      key,
      count: count + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

const livingEntryAISecrets = [openaiLivingEntriesApiKey, anthropicLivingEntriesApiKey];

export const classifyLivingEntry = onCall({ enforceAppCheck: true, secrets: livingEntryAISecrets }, async (request) => {
  const data = request.data as any;
  const context = { auth: request.auth, app: request.app };
  const uid = requireAuth(context);
  requireAppCheck(context);
  await enforceLivingEntryRateLimit(uid, "classify");
  return classifyWithFallback(data ?? {}, openAIClassification, claudeClassification);
});

export const evaluateLivingEntryContext = onCall({ enforceAppCheck: true }, async (request) => {
  const data = request.data as any;
  const context = { auth: request.auth, app: request.app };
  const uid = requireAuth(context);
  requireAppCheck(context);
  await enforceLivingEntryRateLimit(uid, "context");
  return evaluateContext(data ?? {});
});

export const calculateIntentGravity = onCall({ enforceAppCheck: true }, async (request) => {
  const data = request.data as any;
  const context = { auth: request.auth, app: request.app };
  const uid = requireAuth(context);
  requireAppCheck(context);
  await enforceLivingEntryRateLimit(uid, "gravity");
  return {
    gravityScore: calculateIntentGravityScore(data ?? {}),
  };
});

export const calculateRegretRisk = onCall({ enforceAppCheck: true }, async (request) => {
  const data = request.data as any;
  const context = { auth: request.auth, app: request.app };
  const uid = requireAuth(context);
  requireAppCheck(context);
  await enforceLivingEntryRateLimit(uid, "regret");
  const deferrals = Number(data?.repeatedDeferrals ?? 0);
  const completions = Number(data?.completedCount ?? 0);
  const skipped = Number(data?.skippedCount ?? 0);
  const spiritualWeight = clamp01(Number(data?.spiritualWeight ?? 0));
  const regretRisk = clamp01(deferrals * 0.12 + skipped * 0.06 - completions * 0.03 + spiritualWeight * 0.35);
  return {
    regretRisk,
    gentleCopy: buildGentleRegretCopy(regretRisk),
  };
});

export const completeLivingEntryWithReflection = onCall({ enforceAppCheck: true, secrets: livingEntryAISecrets }, async (request) => {
  const data = request.data as any;
  const context = { auth: request.auth, app: request.app };
  const uid = requireAuth(context);
  requireAppCheck(context);
  await enforceLivingEntryRateLimit(uid, "complete");

  const entryId = String(data?.entryId ?? "");
  if (!entryId) {
    throw new HttpsError("invalid-argument", "entryId is required");
  }

  const reflectionRef = db.collection("users").doc(uid).collection("living_entry_reflections").doc();
  const entryRef = db.collection("users").doc(uid).collection("living_entries").doc(entryId);
  const entrySnap = await entryRef.get();
  const entryData = entrySnap.data() ?? {};
  const answer = String(data?.answer ?? "").trim().slice(0, 500);
  const helpfulness = String(data?.helpfulness ?? "helpful");
  const reflectionLearning = await generateReflectionLearning({
    entryType: String(entryData.type ?? "note"),
    entryTitle: String(entryData.title ?? ""),
    answer,
    helpfulness,
  });

  await db.runTransaction(async (tx) => {
    tx.set(reflectionRef, {
      entryId,
      userId: uid,
      answer,
      helpfulness,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      aiLearningSummary: reflectionLearning.aiLearningSummary,
      nextTriggerSuggestion: reflectionLearning.nextTriggerSuggestion,
      provider: reflectionLearning.provider,
    });
    tx.set(entryRef, {
      state: "completed",
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      reflectionAnswer: answer,
      suggestedNextAction: reflectionLearning.nextTriggerSuggestion,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });

  return { ok: true, reflectionId: reflectionRef.id };
});

export const evolveLivingEntries = onCall({ enforceAppCheck: true, secrets: livingEntryAISecrets }, async (request) => {
    const _data = request.data as any;
    const data = _data;
    const context = { auth: request.auth, app: request.app };
  const uid = requireAuth(context);
  requireAppCheck(context);
  await enforceLivingEntryRateLimit(uid, "evolve", 10);
  return evolveEntriesForUser(uid);
});

export const evolveLivingEntriesScheduled = onSchedule({ schedule: "every 6 hours" }, async () => {
  const users = await db.collection("users").limit(50).get();
  for (const user of users.docs) {
    await evolveEntriesForUser(user.id);
  }
});

async function evolveEntriesForUser(uid: string) {
  const entriesSnap = await db.collection("users").doc(uid).collection("living_entries")
    .where("state", "in", ["active", "deferred", "needsReflection"])
    .limit(50)
    .get();

  if (entriesSnap.empty) {
    return { ok: true, evolved: 0 };
  }

  let evolved = 0;
  const batch = db.batch();
  for (const doc of entriesSnap.docs) {
    const data = doc.data();
    const evolution = await generateEvolutionSuggestion({
      type: String(data.type ?? "note"),
      title: String(data.title ?? ""),
      body: String(data.body ?? ""),
      churchName: String(data.churchName ?? ""),
      state: String(data.state ?? "active"),
    });
    batch.set(doc.ref, {
      aiSummary: evolution.aiSummary,
      suggestedNextAction: evolution.suggestedNextAction,
      aiProvider: evolution.provider,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    evolved += 1;
  }
  await batch.commit();
  return { ok: true, evolved };
}

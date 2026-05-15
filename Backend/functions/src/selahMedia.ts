import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import Anthropic from "@anthropic-ai/sdk";

const db = admin.firestore();

function requireAuth(auth: { uid: string } | undefined): string {
  if (!auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return auth.uid;
}

function requireAppCheck(app: { appId?: string } | undefined) {
  if (!app) {
    throw new HttpsError("failed-precondition", "App Check required.");
  }
}

// MARK: - Rate limiting helper

async function enforceSelahRateLimit(userId: string, key: string, max = 20) {
  const bucket = Math.floor(Date.now() / 60_000);
  const ref = db.collection("rateLimits").doc(`selah:${key}:${userId}:${bucket}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = snap.exists ? Number(snap.data()?.count ?? 0) : 0;
    if (count >= max) {
      throw new HttpsError("resource-exhausted", "Rate limit exceeded");
    }
    tx.set(ref, {
      count: count + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

// MARK: - Feed

/**
 * getSelahFeed — returns a ranked list of selah_media items for the calling user.
 * Applies basic intent signal and meaning tag scoring server-side.
 */
export const getSelahFeed = onCall(async (request) => {
  const uid = requireAuth(request.auth);
  requireAppCheck(request.app);
  await enforceSelahRateLimit(uid, "getSelahFeed");

  const { mode = "media", limit = 30 } = request.data ?? {};

  // Fetch candidate media
  const snap = await db.collection("selah_media")
    .where("trustCircleTier", "in", ["community", "public"])
    .orderBy("createdAt", "desc")
    .limit(Number(limit))
    .get();

  const items = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));

  // Fetch user's recent memories for signal
  const memoriesSnap = await db.collection("users").doc(uid)
    .collection("selah_memories")
    .orderBy("createdAt", "desc")
    .limit(10)
    .get();

  const recentCategories = new Set<string>();
  memoriesSnap.docs.forEach((doc) => {
    const tags: Array<{ category: string }> = doc.data().meaningTags ?? [];
    tags.forEach((t) => recentCategories.add(t.category));
  });

  // Score items
  const scored = items.map((item: Record<string, unknown>) => {
    let score = 0;
    const tags: Array<{ category: string }> = (item.meaningTags as Array<{ category: string }>) ?? [];
    tags.forEach((t) => {
      if (recentCategories.has(t.category)) score += 0.25;
    });
    const age = (Date.now() - Number((item.createdAt as admin.firestore.Timestamp)?.toMillis?.() ?? 0)) / 86_400_000;
    score += Math.max(0, 0.15 * (1 - Math.min(age / 7, 1)));
    return { ...item, _score: score };
  });

  scored.sort((a, b) => b._score - a._score);
  return { items: scored };
});

// MARK: - Session

/**
 * updateSelahSession — records session activity and returns an updated context window.
 */
export const updateSelahSession = onCall(async (request) => {
  const uid = requireAuth(request.auth);
  requireAppCheck(request.app);
  await enforceSelahRateLimit(uid, "updateSelahSession", 60);

  const {
    mode = "pause",
    viewedMediaIds = [] as string[],
    sessionStartedAt,
  } = request.data ?? {};

  const now = admin.firestore.Timestamp.now();
  const ref = db.collection("users").doc(uid)
    .collection("selah_sessions").doc("current");

  await ref.set({
    mode,
    viewedMediaIds: viewedMediaIds.slice(0, 50),
    sessionStartedAt: sessionStartedAt
      ? admin.firestore.Timestamp.fromMillis(sessionStartedAt)
      : now,
    updatedAt: now,
  }, { merge: true });

  // Generate context window summary
  const hour = new Date().getHours();
  const isEvening = hour >= 18 || hour < 5;
  const dominantCategory = await getDominantCategory(uid);

  return {
    ok: true,
    contextWindow: {
      suggestedMode: isEvening ? "pause" : mode,
      restSignalDetected: isEvening,
      dominantCategory,
      sessionSummary: buildSessionSummary(viewedMediaIds.length, dominantCategory),
    },
  };
});

async function getDominantCategory(uid: string): Promise<string | null> {
  const snap = await db.collection("users").doc(uid)
    .collection("selah_memories")
    .orderBy("createdAt", "desc")
    .limit(10)
    .get();

  const counts: Record<string, number> = {};
  snap.docs.forEach((doc) => {
    const tags: Array<{ category: string }> = doc.data().meaningTags ?? [];
    tags.forEach((t) => { counts[t.category] = (counts[t.category] ?? 0) + 1; });
  });

  const entries = Object.entries(counts);
  if (!entries.length) return null;
  return entries.sort(([, a], [, b]) => b - a)[0][0];
}

function buildSessionSummary(viewed: number, category: string | null): string {
  if (viewed === 0) return "Just getting started";
  const cat = category ?? "spiritual";
  if (viewed < 5) return `Exploring ${cat} content`;
  return `Deep ${cat} session with ${viewed} moments`;
}

// MARK: - Memories

/**
 * saveSelahMemory — server-authoritative write for selah_memories.
 * Enforces userId ownership and rate limit.
 */
export const saveSelahMemory = onCall(async (request) => {
  const uid = requireAuth(request.auth);
  requireAppCheck(request.app);
  await enforceSelahRateLimit(uid, "saveSelahMemory", 30);

  const { title, bodyText, linkedMediaIds = [], linkedScriptureRefs = [], meaningTags = [], intentSignal = "reflecting" } = request.data ?? {};

  if (!title || typeof title !== "string" || title.trim().length === 0) {
    throw new HttpsError("invalid-argument", "title is required");
  }

  const ref = await db.collection("users").doc(uid)
    .collection("selah_memories")
    .add({
      userId: uid,
      title: String(title).trim().slice(0, 100),
      bodyText: String(bodyText ?? "").trim().slice(0, 2000),
      linkedMediaIds: (linkedMediaIds as string[]).slice(0, 20),
      linkedScriptureRefs: (linkedScriptureRefs as string[]).slice(0, 10),
      meaningTags: (meaningTags as unknown[]).slice(0, 12),
      intentSignal,
      aiSummary: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  // Kick off async AI enrichment
  enrichMemoryWithAI(uid, ref.id, title, bodyText ?? "").catch(() => {});

  return { ok: true, memoryId: ref.id };
});

async function enrichMemoryWithAI(uid: string, memoryId: string, title: string, body: string) {
  const anthropicKey = process.env.ANTHROPIC_API_KEY;
  if (!anthropicKey) return;

  const client = new Anthropic({ apiKey: anthropicKey });
  const message = await client.messages.create({
    model: "claude-opus-4-7",
    max_tokens: 150,
    messages: [{
      role: "user",
      content: `In 1-2 sentences, summarize this spiritual memory and what it reveals about the person's faith journey:\nTitle: ${title}\n${body}`.slice(0, 800),
    }],
  });

  const summary = (message.content[0] as { type: string; text: string }).type === "text"
    ? (message.content[0] as { type: string; text: string }).text.trim()
    : null;

  if (summary) {
    await db.collection("users").doc(uid)
      .collection("selah_memories")
      .document(memoryId)
      .update({ aiSummary: summary });
  }
}

// MARK: - Ask Berean about Selah Media

/**
 * askBereanAboutSelahMedia — AI-powered question about a specific media item.
 */
export const askBereanAboutSelahMedia = onCall(async (request) => {
  const uid = requireAuth(request.auth);
  requireAppCheck(request.app);
  await enforceSelahRateLimit(uid, "askBerean", 10);

  const { mediaItemId, question } = request.data ?? {};
  if (!question || typeof question !== "string") {
    throw new HttpsError("invalid-argument", "question is required");
  }

  // Fetch the media item
  let caption = "";
  let scriptureRef = "";
  let tags: string[] = [];

  if (mediaItemId) {
    const snap = await db.collection("selah_media").doc(String(mediaItemId)).get();
    if (snap.exists) {
      const data = snap.data() ?? {};
      caption = String(data.caption ?? "").slice(0, 300);
      scriptureRef = String(data.scriptureRef ?? "");
      tags = ((data.meaningTags as Array<{ label: string }>) ?? [])
        .map((t) => t.label)
        .slice(0, 5);
    }
  }

  const context = [
    caption && `Media caption: ${caption}`,
    scriptureRef && `Scripture: ${scriptureRef}`,
    tags.length && `Themes: ${tags.join(", ")}`,
  ].filter(Boolean).join("\n");

  const anthropicKey = process.env.ANTHROPIC_API_KEY;
  if (!anthropicKey) {
    throw new HttpsError("internal", "AI service not configured.");
  }

  const client = new Anthropic({ apiKey: anthropicKey });
  const systemPrompt = `You are Berean, a warm and theologically careful AI companion within the AMEN spiritual community app.
A user is reflecting on a meaningful visual moment and has a question.
${context ? `Context about the moment:\n${context}` : ""}
Answer in 2-4 sentences. Be grounded, pastoral, and encouraging.`;

  const message = await client.messages.create({
    model: "claude-opus-4-7",
    max_tokens: 400,
    system: systemPrompt,
    messages: [{ role: "user", content: String(question).slice(0, 500) }],
  });

  const response = (message.content[0] as { type: string; text: string }).type === "text"
    ? (message.content[0] as { type: string; text: string }).text
    : "";

  return { response };
});

// MARK: - Continuations

/**
 * createSelahContinuation — server-side creation of a next-best-action prompt.
 */
export const createSelahContinuation = onCall(async (request) => {
  const uid = requireAuth(request.auth);
  requireAppCheck(request.app);
  await enforceSelahRateLimit(uid, "createContinuation", 20);

  const {
    promptText,
    contextSummary = "",
    action = "reflect",
    linkedMediaId,
    linkedMemoryId,
    scriptureRef,
    relevanceScore = 0.5,
  } = request.data ?? {};

  if (!promptText) {
    throw new HttpsError("invalid-argument", "promptText is required");
  }

  const validActions = ["reflect", "pray", "share", "study", "create", "journal", "rest"];
  const safeAction = validActions.includes(action) ? action : "reflect";

  const ref = await db.collection("users").doc(uid)
    .collection("selah_continuations")
    .add({
      userId: uid,
      promptText: String(promptText).slice(0, 300),
      contextSummary: String(contextSummary).slice(0, 200),
      action: safeAction,
      linkedMediaId: linkedMediaId ?? null,
      linkedMemoryId: linkedMemoryId ?? null,
      linkedLivingEntryId: null,
      scriptureRef: scriptureRef ?? null,
      relevanceScore: Math.min(Math.max(Number(relevanceScore), 0), 1),
      completed: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      completedAt: null,
    });

  return { ok: true, continuationId: ref.id };
});

// MARK: - Outcomes

/**
 * createSelahOutcome — records a completed spiritual action outcome.
 */
export const createSelahOutcome = onCall(async (request) => {
  const uid = requireAuth(request.auth);
  requireAppCheck(request.app);
  await enforceSelahRateLimit(uid, "createOutcome", 20);

  const { continuationId, noteText, scriptureRef } = request.data ?? {};
  if (!continuationId) {
    throw new HttpsError("invalid-argument", "continuationId is required");
  }

  const contRef = db.collection("users").doc(uid)
    .collection("selah_continuations")
    .doc(String(continuationId));

  const snap = await contRef.get();
  if (!snap.exists || snap.data()?.userId !== uid) {
    throw new HttpsError("not-found", "Continuation not found.");
  }

  const batch = db.batch();
  batch.update(contRef, {
    completed: true,
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const outcomeRef = db.collection("users").doc(uid)
    .collection("selah_outcomes")
    .doc();

  batch.set(outcomeRef, {
    userId: uid,
    continuationId,
    action: snap.data()?.action ?? "reflect",
    noteText: noteText ? String(noteText).slice(0, 500) : null,
    scriptureRef: scriptureRef ?? null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();
  return { ok: true, outcomeId: outcomeRef.id };
});

// MARK: - Meaning Graph — triggered on new media item

/**
 * buildSelahMeaningGraphEdge — triggered when a new selah_media doc is created.
 * Finds meaning graph edges to existing media from the same user.
 */
export const buildSelahMeaningGraphEdge = onDocumentCreated(
  "selah_media/{itemId}",
  async (event) => {
    const newItem = event.data?.data();
    if (!newItem) return;

    const itemId = event.params.itemId;
    const authorId: string = newItem.authorId;
    const newTags: Array<{ category: string; scriptureRef?: string }> = newItem.meaningTags ?? [];
    const newCats = new Set(newTags.map((t) => t.category));

    if (newCats.size === 0) return;

    // Find existing media from the same author to build edges
    const existing = await db.collection("selah_media")
      .where("authorId", "==", authorId)
      .orderBy("createdAt", "desc")
      .limit(20)
      .get();

    const batch = db.batch();
    let edgeCount = 0;

    for (const doc of existing.docs) {
      if (doc.id === itemId || edgeCount >= 5) break;
      const otherTags: Array<{ category: string; scriptureRef?: string }> = doc.data().meaningTags ?? [];
      const otherCats = new Set(otherTags.map((t) => t.category));
      const shared = [...newCats].filter((c) => otherCats.has(c));
      if (shared.length === 0) continue;

      const strength = Math.min(shared.length * 0.3, 1);
      const edgeRef = db.collection("selah_meaning_graph").doc();
      batch.set(edgeRef, {
        sourceItemId: itemId,
        targetItemId: doc.id,
        sharedCategories: shared,
        sharedScriptureRefs: [],
        connectionStrength: strength,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      edgeCount++;
    }

    if (edgeCount > 0) await batch.commit();
  }
);

// MARK: - Stale Continuations Cleanup

/**
 * cleanupStaleSelahContinuations — daily cleanup of completed/expired continuations.
 */
export const cleanupStaleSelahContinuations = onSchedule("every 24 hours", async () => {
  const cutoff = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - 30 * 86_400_000)
  );

  const snap = await db.collectionGroup("selah_continuations")
    .where("completed", "==", true)
    .where("completedAt", "<", cutoff)
    .limit(200)
    .get();

  if (snap.empty) return;

  const batch = db.batch();
  snap.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
});

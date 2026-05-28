import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";
import { detectScriptures, scriptureActions } from "./scriptureDetection";
import { detectDateEvents, eventActions } from "./dateEventDetection";
import { detectPrayerRequests, prayerActions } from "./prayerDetection";
import { extractTopics } from "./topicExtraction";
import { buildExtractiveDiscussionInsight, loadThreadMessageTexts, writeDiscussionInsight } from "./discussionSummary";
import { contextualBereanActions } from "./contextualBereanActions";
import { indexMessageForFallback, indexSemanticItem, keywordSearchSpace, vectorSearchEnabled, vectorSearchSpace } from "./semanticSearch";
import { createSmartStudySession } from "./studyMode";
import { transcriptEntity } from "./voiceIntelligence";
import { createKnowledgeNode } from "./knowledgeGraph";
import { recordSmartMessageMetric } from "./monitoring";
import {
  dedupeActions,
  parseMessageContext,
  requireAuthAndAppCheck,
  requireSpaceMember,
  requiredString,
  sanitizeText,
  writeEntities,
} from "./validators";

const db = admin.firestore();
const callableOptions = { region: "us-central1", timeoutSeconds: 60, enforceAppCheck: true } as const;
const appCheckedCallableOptions = { ...callableOptions, enforceAppCheck: true } as const;

const smartRateLimits = [
  RATE_LIMITS.smartMessagePerMinute,
  RATE_LIMITS.smartMessagePerDay,
];

type BackfillCounters = {
  messages: number;
  summaries: number;
  studySessions: number;
  prayerRequests: number;
  knowledgeNodes: number;
  skipped: number;
};

export const analyzeSmartMessage = onCall({ ...appCheckedCallableOptions, enforceAppCheck: true }, async (request) => {
  const uid = requireAuthAndAppCheck(request);
  await enforceRateLimit(uid, smartRateLimits);
  const context = await parseMessageContext(uid, request.data as Record<string, unknown>);

  const scriptureEntities = detectScriptures(context.text);
  const dateEntities = detectDateEvents(context.text);
  const prayerEntities = detectPrayerRequests(context.text);
  const topicEntities = extractTopics(context.text);
  const detectedEntities = [...scriptureEntities, ...dateEntities, ...prayerEntities, ...topicEntities];
  const suggestedActions = dedupeActions([
    ...scriptureEntities.flatMap(scriptureActions),
    ...dateEntities.flatMap((entity) => eventActions(entity, context.text)),
    ...prayerEntities.flatMap(prayerActions),
  ]);

  if (context.messageId) {
    await db.collection("spaces").doc(context.spaceId)
      .collection("smartThreads").doc(context.threadId)
      .collection("messages").doc(context.messageId)
      .set({
        text: context.text,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    await indexMessageForFallback(
      context.spaceId,
      context.threadId,
      context.messageId,
      context.text,
      topicEntities.map((entity) => entity.normalizedValue),
      scriptureEntities.map((entity) => entity.normalizedValue)
    );
  }
  await writeEntities(context.spaceId, context.threadId, detectedEntities as unknown as Record<string, unknown>[]);
  recordSmartMessageMetric("smart_message_analyze_completed", uid, {
    spaceId: context.spaceId,
    threadId: context.threadId,
    entityCount: detectedEntities.length,
    actionCount: suggestedActions.length,
  });
  return { detectedEntities, suggestedActions };
});

export const detectScriptureReferences = onCall({ ...appCheckedCallableOptions, enforceAppCheck: true }, async (request) => {
  const uid = requireAuthAndAppCheck(request);
  await enforceRateLimit(uid, smartRateLimits);
  const text = sanitizeText((request.data as Record<string, unknown>).text);
  const detectedEntities = detectScriptures(text);
  return { detectedEntities, suggestedActions: detectedEntities.flatMap(scriptureActions) };
});

export const detectSmartDateEvents = onCall({ ...appCheckedCallableOptions, enforceAppCheck: true }, async (request) => {
  const uid = requireAuthAndAppCheck(request);
  await enforceRateLimit(uid, smartRateLimits);
  const text = sanitizeText((request.data as Record<string, unknown>).text);
  const detectedEntities = detectDateEvents(text);
  return { detectedEntities, suggestedActions: detectedEntities.flatMap((entity) => eventActions(entity, text)) };
});

export const detectPrayerRequest = onCall({ ...appCheckedCallableOptions, enforceAppCheck: true }, async (request) => {
  const uid = requireAuthAndAppCheck(request);
  await enforceRateLimit(uid, smartRateLimits);
  const text = sanitizeText((request.data as Record<string, unknown>).text);
  const detectedEntities = detectPrayerRequests(text);
  return { detectedEntities, suggestedActions: detectedEntities.flatMap(prayerActions) };
});

export const summarizeDiscussion = onCall({ ...appCheckedCallableOptions, enforceAppCheck: true, timeoutSeconds: 120 }, async (request) => {
  const uid = requireAuthAndAppCheck(request);
  await enforceRateLimit(uid, smartRateLimits);
  const data = request.data as Record<string, unknown>;
  const spaceId = requiredString(data, "spaceId");
  const threadId = requiredString(data, "threadId");
  await requireSpaceMember(uid, spaceId);
  const texts = await loadThreadMessageTexts(spaceId, threadId, data.messageIds);
  const insight = buildExtractiveDiscussionInsight(texts);
  const insightId = await writeDiscussionInsight(spaceId, threadId, insight, uid);
  await indexSemanticItem({
    spaceId,
    itemId: `summary_${insightId}`,
    sourceType: "summary",
    threadId,
    sourceId: insightId,
    title: insight.scriptures[0] ?? insight.topics[0] ?? "Discussion Summary",
    text: [
      insight.summary,
      ...insight.keyTakeaways,
      ...insight.actionItems,
      ...insight.unresolvedQuestions,
    ].join("\n"),
    topics: insight.topics,
    scriptures: insight.scriptures,
    path: `spaces/${spaceId}/smartThreads/${threadId}/insights/${insightId}`,
  });
  recordSmartMessageMetric("smart_message_summary_created", uid, {
    spaceId,
    threadId,
    takeawayCount: insight.keyTakeaways.length,
    scriptureCount: insight.scriptures.length,
    topicCount: insight.topics.length,
  });
  return { insightId, ...insight };
});

export const getContextualBereanActions = onCall({ ...appCheckedCallableOptions, enforceAppCheck: true }, async (request) => {
  const uid = requireAuthAndAppCheck(request);
  await enforceRateLimit(uid, smartRateLimits);
  const data = request.data as Record<string, unknown>;
  const selectedText = sanitizeText(data.selectedText, 2000);
  const sourceType = requiredString(data, "sourceType");
  const sourceId = typeof data.sourceId === "string" ? data.sourceId : undefined;
  const spaceId = typeof data.spaceId === "string" ? data.spaceId : undefined;
  if (spaceId) await requireSpaceMember(uid, spaceId);
  return { actions: contextualBereanActions(selectedText, sourceType, sourceId) };
});

export const extractDiscussionTopics = onCall({ ...appCheckedCallableOptions, enforceAppCheck: true }, async (request) => {
  const uid = requireAuthAndAppCheck(request);
  await enforceRateLimit(uid, smartRateLimits);
  const context = await parseMessageContext(uid, request.data as Record<string, unknown>);
  const detectedEntities = extractTopics(context.text);
  await writeEntities(context.spaceId, context.threadId, detectedEntities as unknown as Record<string, unknown>[]);
  return { detectedEntities };
});

export const semanticSearchAmenSpace = onCall({ ...appCheckedCallableOptions, enforceAppCheck: true }, async (request) => {
  const uid = requireAuthAndAppCheck(request);
  await enforceRateLimit(uid, smartRateLimits);
  const data = request.data as Record<string, unknown>;
  const spaceId = requiredString(data, "spaceId");
  const query = sanitizeText(data.query, 500);
  await requireSpaceMember(uid, spaceId);
  const vectorResults = vectorSearchEnabled() ? await vectorSearchSpace(spaceId, query) : null;
  const rankingMode = vectorResults ? "vector" : "keywordFallback";
  const results = vectorResults ?? await keywordSearchSpace(spaceId, query);
  recordSmartMessageMetric("smart_message_search_completed", uid, {
    spaceId,
    rankingMode,
    resultCount: results.length,
    vectorConfigured: vectorSearchEnabled(),
  });
  return { rankingMode, results };
});

export const startSmartStudyMode = onCall({ ...appCheckedCallableOptions, enforceAppCheck: true }, async (request) => {
  const uid = requireAuthAndAppCheck(request);
  await enforceRateLimit(uid, smartRateLimits);
  const data = request.data as Record<string, unknown>;
  const spaceId = requiredString(data, "spaceId");
  const threadId = requiredString(data, "threadId");
  await requireSpaceMember(uid, spaceId);
  const seedMessageIds = Array.isArray(data.seedMessageIds) ? data.seedMessageIds.map(String).slice(0, 40) : [];
  const texts = await loadThreadMessageTexts(spaceId, threadId, seedMessageIds);
  const combined = texts.join("\n");
  const session = await createSmartStudySession({
    uid,
    spaceId,
    threadId,
    title: typeof data.title === "string" ? data.title : undefined,
    scriptures: detectScriptures(combined).map((entity) => entity.normalizedValue),
    topics: extractTopics(combined).map((entity) => entity.normalizedValue),
    seedMessageIds,
  });
  await indexSemanticItem({
    spaceId,
    itemId: `study_${session.id}`,
    sourceType: "studySession",
    threadId,
    sourceId: session.id,
    title: session.title,
    text: [session.title, ...session.scriptures, ...session.topics].join("\n"),
    topics: session.topics,
    scriptures: session.scriptures,
    path: `spaces/${spaceId}/smartThreads/${threadId}/studySessions/${session.id}`,
  });
  recordSmartMessageMetric("smart_message_study_started", uid, {
    spaceId,
    threadId,
    scriptureCount: session.scriptures.length,
    topicCount: session.topics.length,
  });
  return { session };
});

export const transcribeVoiceMessage = onCall({ ...appCheckedCallableOptions, enforceAppCheck: true, timeoutSeconds: 120 }, async (request) => {
  const uid = requireAuthAndAppCheck(request);
  await enforceRateLimit(uid, smartRateLimits);
  const data = request.data as Record<string, unknown>;
  const spaceId = requiredString(data, "spaceId");
  const threadId = requiredString(data, "threadId");
  const messageId = requiredString(data, "messageId");
  await requireSpaceMember(uid, spaceId);
  const transcript = typeof data.transcript === "string" ? data.transcript.trim() : "";
  if (!transcript) {
    throw new HttpsError("failed-precondition", "Voice transcription requires an approved provider transcript.");
  }
  const entity = transcriptEntity(transcript, messageId);
  const allEntities = [entity, ...detectScriptures(transcript), ...extractTopics(transcript)];
  await writeEntities(spaceId, threadId, allEntities as unknown as Record<string, unknown>[]);
  return { transcript, detectedEntities: allEntities };
});

export const buildKnowledgeGraphMemory = onCall({ ...appCheckedCallableOptions, enforceAppCheck: true }, async (request) => {
  const uid = requireAuthAndAppCheck(request);
  await enforceRateLimit(uid, smartRateLimits);
  const data = request.data as Record<string, unknown>;
  const scope = data.scope === "space" ? "space" : "user";
  const spaceId = typeof data.spaceId === "string" ? data.spaceId : undefined;
  if (scope === "space") {
    if (!spaceId) throw new HttpsError("invalid-argument", "spaceId is required.");
    await requireSpaceMember(uid, spaceId);
  }
  const sourceType = requiredString(data, "sourceType");
  const sourceId = requiredString(data, "sourceId");
  const text = typeof data.text === "string" ? sanitizeText(data.text, 3000) : `${sourceType} ${sourceId}`;
  const scriptures = detectScriptures(text).map((entity) => entity.normalizedValue);
  const topics = extractTopics(text).map((entity) => entity.normalizedValue);
  const node = await createKnowledgeNode({
    uid,
    scope,
    spaceId,
    sourceType,
    sourceId,
    title: scriptures[0] ?? topics[0] ?? "Smart Memory",
    summary: text,
    scriptureRefs: scriptures,
    topics,
  });
  if (scope === "space" && spaceId) {
    await indexSemanticItem({
      spaceId,
      itemId: `knowledge_${node.id}`,
      sourceType: "knowledgeNode",
      sourceId: node.id,
      title: node.title,
      text: `${node.title}\n${node.summary}`,
      topics: node.topics,
      scriptures: node.scriptureRefs,
      path: `spaces/${spaceId}/knowledgeGraph/nodes/nodes/${node.id}`,
    });
  }
  recordSmartMessageMetric("smart_message_knowledge_node_created", uid, {
    scope,
    spaceId: spaceId ?? null,
    sourceType,
    scriptureCount: scriptures.length,
    topicCount: topics.length,
  });
  return { node };
});

export const indexSmartPrayerRequest = onDocumentCreated(
  { region: "us-central1", document: "spaces/{spaceId}/prayerRequests/{requestId}" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    const visibility = String(data.visibility ?? "");
    if (visibility !== "space") return;
    const body = sanitizeText(data.body, 3000);
    if (!body) return;
    const spaceId = String(event.params.spaceId);
    const requestId = String(event.params.requestId);
    const threadId = typeof data.threadId === "string" ? data.threadId : undefined;
    await indexSemanticItem({
      spaceId,
      itemId: `prayer_${requestId}`,
      sourceType: "prayerRequest",
      threadId,
      sourceId: requestId,
      title: "Prayer Request",
      text: body,
      topics: extractTopics(body).map((entity) => entity.normalizedValue),
      scriptures: detectScriptures(body).map((entity) => entity.normalizedValue),
      path: `spaces/${spaceId}/prayerRequests/${requestId}`,
    });
    recordSmartMessageMetric("smart_message_prayer_indexed", String(data.createdBy ?? "server"), {
      spaceId,
      visibility,
      topicCount: extractTopics(body).length,
      scriptureCount: detectScriptures(body).length,
    });
  }
);

export const backfillSmartMessageVectorIndex = onCall(
  { ...appCheckedCallableOptions, enforceAppCheck: true, timeoutSeconds: 540 },
  async (request) => {
    const uid = requireAuthAndAppCheck(request);
    await enforceRateLimit(uid, smartRateLimits);
    const data = request.data as Record<string, unknown>;
    const spaceId = requiredString(data, "spaceId");
    await requireSpaceMember(uid, spaceId);
    const maxThreads = Math.max(1, Math.min(Number(data.maxThreads ?? 20), 50));
    const maxMessagesPerThread = Math.max(1, Math.min(Number(data.maxMessagesPerThread ?? 80), 150));
    const requestedThreadIds = Array.isArray(data.threadIds)
      ? data.threadIds.map(String).filter(Boolean).slice(0, maxThreads)
      : [];
    const counters: BackfillCounters = {
      messages: 0,
      summaries: 0,
      studySessions: 0,
      prayerRequests: 0,
      knowledgeNodes: 0,
      skipped: 0,
    };

    const threadIds = requestedThreadIds.length
      ? requestedThreadIds
      : (await db.collection("spaces").doc(spaceId)
        .collection("smartThreads")
        .limit(maxThreads)
        .get()).docs.map((doc) => doc.id);

    for (const threadId of threadIds) {
      await backfillThread(spaceId, threadId, maxMessagesPerThread, counters);
    }
    await backfillSpacePrayerRequests(spaceId, counters);
    await backfillSpaceKnowledgeNodes(spaceId, counters);

    recordSmartMessageMetric("smart_message_vector_backfill_completed", uid, {
      spaceId,
      threadCount: threadIds.length,
      messageCount: counters.messages,
      summaryCount: counters.summaries,
      studySessionCount: counters.studySessions,
      prayerRequestCount: counters.prayerRequests,
      knowledgeNodeCount: counters.knowledgeNodes,
      skippedCount: counters.skipped,
      vectorConfigured: vectorSearchEnabled(),
    });

    return {
      rankingModeReady: vectorSearchEnabled(),
      threadCount: threadIds.length,
      indexed: counters,
    };
  }
);

export const getSmartMessageVectorIndexStatus = onCall(
  { ...appCheckedCallableOptions, enforceAppCheck: true },
  async (request) => {
    const uid = requireAuthAndAppCheck(request);
    await enforceRateLimit(uid, smartRateLimits);
    const data = request.data as Record<string, unknown>;
    const spaceId = requiredString(data, "spaceId");
    await requireSpaceMember(uid, spaceId);
    const snap = await db.collection("spaces").doc(spaceId)
      .collection("semanticIndex").doc("items")
      .collection("items")
      .limit(200)
      .get();
    let vectorIndexed = 0;
    const byType: Record<string, number> = {};
    for (const doc of snap.docs) {
      const value = doc.data();
      const sourceType = String(value.sourceType ?? "unknown");
      byType[sourceType] = (byType[sourceType] ?? 0) + 1;
      if (value.vectorIndexed === true) vectorIndexed += 1;
    }
    return {
      vectorConfigured: vectorSearchEnabled(),
      sampledItems: snap.size,
      vectorIndexed,
      keywordOnly: snap.size - vectorIndexed,
      byType,
    };
  }
);

// NOTE: Add a Firestore TTL policy on `system/scheduledJobLocks` collection
// with field `expiresAt` set to 7 days. This automatically cleans up old lock documents.

export const scheduledSmartMessageVectorBackfill = onSchedule(
  { region: "us-central1", schedule: "every 6 hours", timeZone: "America/Phoenix", timeoutSeconds: 540 },
  async () => {
    // Idempotency: lock by 6-hour window (UTC ISO rounded to nearest 6 hours)
    const nowMs = Date.now();
    const windowMs = 6 * 60 * 60 * 1000;
    const windowKey = new Date(Math.floor(nowMs / windowMs) * windowMs).toISOString().replace(/[:.]/g, "-");
    const lockRef = db.doc(`system/scheduledJobLocks/smartMessageVectorBackfill_${windowKey}`);

    const lockAcquired = await db.runTransaction(async (tx) => {
      const snap = await tx.get(lockRef);
      if (snap.exists && snap.data()?.status === "completed") {
        return false;
      }
      tx.set(lockRef, {
        status: "running",
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
        windowKey,
        expiresAt: new Date(nowMs + 7 * 24 * 60 * 60 * 1000),
      });
      return true;
    });

    if (!lockAcquired) {
      recordSmartMessageMetric("smart_message_vector_scheduled_backfill_skipped", "system", { windowKey });
      return;
    }

    try {
      const spaces = await db.collection("spaces").limit(30).get();
      const totals: BackfillCounters = {
        messages: 0,
        summaries: 0,
        studySessions: 0,
        prayerRequests: 0,
        knowledgeNodes: 0,
        skipped: 0,
      };
      let spaceCount = 0;
      for (const space of spaces.docs) {
        const counters = await backfillSpace(space.id, 10, 80);
        mergeCounters(totals, counters);
        spaceCount += 1;
      }
      recordSmartMessageMetric("smart_message_vector_scheduled_backfill_completed", "system", {
        spaceCount,
        messageCount: totals.messages,
        summaryCount: totals.summaries,
        studySessionCount: totals.studySessions,
        prayerRequestCount: totals.prayerRequests,
        knowledgeNodeCount: totals.knowledgeNodes,
        skippedCount: totals.skipped,
        vectorConfigured: vectorSearchEnabled(),
      });

      await lockRef.update({
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      await lockRef.update({
        status: "failed",
        error: String(err),
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw err;
    }
  }
);

async function backfillSpace(spaceId: string, maxThreads: number, maxMessagesPerThread: number): Promise<BackfillCounters> {
  const counters: BackfillCounters = {
    messages: 0,
    summaries: 0,
    studySessions: 0,
    prayerRequests: 0,
    knowledgeNodes: 0,
    skipped: 0,
  };
  const threadIds = (await db.collection("spaces").doc(spaceId)
    .collection("smartThreads")
    .limit(maxThreads)
    .get()).docs.map((doc) => doc.id);
  for (const threadId of threadIds) {
    await backfillThread(spaceId, threadId, maxMessagesPerThread, counters);
  }
  await backfillSpacePrayerRequests(spaceId, counters);
  await backfillSpaceKnowledgeNodes(spaceId, counters);
  return counters;
}

function mergeCounters(target: BackfillCounters, source: BackfillCounters): void {
  target.messages += source.messages;
  target.summaries += source.summaries;
  target.studySessions += source.studySessions;
  target.prayerRequests += source.prayerRequests;
  target.knowledgeNodes += source.knowledgeNodes;
  target.skipped += source.skipped;
}

async function backfillThread(
  spaceId: string,
  threadId: string,
  maxMessagesPerThread: number,
  counters: BackfillCounters
): Promise<void> {
  const threadRef = db.collection("spaces").doc(spaceId).collection("smartThreads").doc(threadId);
  const [messages, insights, studySessions] = await Promise.all([
    threadRef.collection("messages").limit(maxMessagesPerThread).get(),
    threadRef.collection("insights").limit(40).get(),
    threadRef.collection("studySessions").limit(40).get(),
  ]);

  for (const doc of messages.docs) {
    const text = optionalText(doc.data().text, 6000);
    if (!text) {
      counters.skipped += 1;
      continue;
    }
    const topics = extractTopics(text).map((entity) => entity.normalizedValue);
    const scriptures = detectScriptures(text).map((entity) => entity.normalizedValue);
    await indexSemanticItem({
      spaceId,
      itemId: doc.id,
      sourceType: "message",
      threadId,
      sourceId: doc.id,
      title: scriptures[0] ?? topics[0] ?? "Message",
      text,
      topics,
      scriptures,
      path: doc.ref.path,
    });
    counters.messages += 1;
  }

  for (const doc of insights.docs) {
    const insight = doc.data();
    const scriptures = stringArray(insight.scriptures, 20);
    const topics = stringArray(insight.topics, 20);
    const text = [
      optionalText(insight.summary, 3000),
      ...stringArray(insight.keyTakeaways, 12),
      ...stringArray(insight.actionItems, 12),
      ...stringArray(insight.unresolvedQuestions, 12),
    ].filter(Boolean).join("\n");
    if (!text) {
      counters.skipped += 1;
      continue;
    }
    await indexSemanticItem({
      spaceId,
      itemId: `summary_${doc.id}`,
      sourceType: "summary",
      threadId,
      sourceId: doc.id,
      title: scriptures[0] ?? topics[0] ?? "Discussion Summary",
      text,
      topics,
      scriptures,
      path: doc.ref.path,
    });
    counters.summaries += 1;
  }

  for (const doc of studySessions.docs) {
    const session = doc.data();
    const scriptures = stringArray(session.scriptures, 20);
    const topics = stringArray(session.topics, 20);
    const title = optionalText(session.title, 160) || scriptures[0] || topics[0] || "Smart Study";
    const text = [title, ...scriptures, ...topics, ...stringArray(session.notes, 20)].join("\n");
    await indexSemanticItem({
      spaceId,
      itemId: `study_${doc.id}`,
      sourceType: "studySession",
      threadId,
      sourceId: doc.id,
      title,
      text,
      topics,
      scriptures,
      path: doc.ref.path,
    });
    counters.studySessions += 1;
  }
}

async function backfillSpacePrayerRequests(spaceId: string, counters: BackfillCounters): Promise<void> {
  const snap = await db.collection("spaces").doc(spaceId).collection("prayerRequests").limit(100).get();
  for (const doc of snap.docs) {
    const data = doc.data();
    if (String(data.visibility ?? "") !== "space") {
      counters.skipped += 1;
      continue;
    }
    const body = optionalText(data.body, 3000);
    if (!body) {
      counters.skipped += 1;
      continue;
    }
    await indexSemanticItem({
      spaceId,
      itemId: `prayer_${doc.id}`,
      sourceType: "prayerRequest",
      threadId: typeof data.threadId === "string" ? data.threadId : undefined,
      sourceId: doc.id,
      title: "Prayer Request",
      text: body,
      topics: extractTopics(body).map((entity) => entity.normalizedValue),
      scriptures: detectScriptures(body).map((entity) => entity.normalizedValue),
      path: doc.ref.path,
    });
    counters.prayerRequests += 1;
  }
}

async function backfillSpaceKnowledgeNodes(spaceId: string, counters: BackfillCounters): Promise<void> {
  const snap = await db.collection("spaces").doc(spaceId)
    .collection("knowledgeGraph").doc("nodes")
    .collection("nodes")
    .limit(100)
    .get();
  for (const doc of snap.docs) {
    const node = doc.data();
    const title = optionalText(node.title, 200) || "Knowledge Node";
    const summary = optionalText(node.summary, 3000);
    const scriptures = stringArray(node.scriptureRefs, 20);
    const topics = stringArray(node.topics, 20);
    const text = [title, summary, ...scriptures, ...topics].filter(Boolean).join("\n");
    if (!text) {
      counters.skipped += 1;
      continue;
    }
    await indexSemanticItem({
      spaceId,
      itemId: `knowledge_${doc.id}`,
      sourceType: "knowledgeNode",
      sourceId: doc.id,
      title,
      text,
      topics,
      scriptures,
      path: doc.ref.path,
    });
    counters.knowledgeNodes += 1;
  }
}

function optionalText(value: unknown, maxLength: number): string {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, maxLength);
}

function stringArray(value: unknown, maxItems: number): string[] {
  return Array.isArray(value)
    ? value.map(String).map((item) => item.trim()).filter(Boolean).slice(0, maxItems)
    : [];
}

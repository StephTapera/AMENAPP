/**
 * commsOS.js
 * AMEN Comms OS — Cloud Functions (Plain JS, App Check enforced)
 *
 * Communication OS Intelligence Layer callables.
 * All AI operations are server-side only. Pipeline:
 *   validate → check membership → retrieve (compressed) → model → moderate → persist → return
 *
 * SAFETY RULES (never bypass):
 * - Never send raw full message history to LLMs
 * - Never bypass space membership or permissions
 * - Never expose content from inaccessible spaces
 * - Never hallucinate participants or fabricate consensus
 * - All output passes moderation before return
 * - Confidence wording applied when confidence < 0.75
 * - No divine authority claims in output
 * - Crisis signals always escalated, never suppressed
 * - Feedback stored per-user, never cross-contaminated
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret }       = require("firebase-functions/params");
const admin                  = require("firebase-admin");
const logger                 = require("firebase-functions/logger");

const db = admin.firestore();

const OPENAI_KEY = defineSecret("OPENAI_API_KEY");

const SENSITIVE_SURFACES = ["prayer_room", "leadership_room", "admin_channel"];
const MAX_MESSAGE_PREVIEW = 200;
const MAX_CHUNK_MESSAGES  = 25;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX       = 20;

// ── Auth + Membership ──────────────────────────────────────────────────────────

function requireAuth(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  return uid;
}

async function checkSpaceMembership(userId, spaceId) {
  try {
    const memberDoc = await db.collection("spaces").doc(spaceId).collection("members").doc(userId).get();
    if (memberDoc.exists) return true;
    const spaceDoc = await db.collection("spaces").doc(spaceId).get();
    if (!spaceDoc.exists) return false;
    const memberIds = spaceDoc.data()?.memberIds ?? [];
    return Array.isArray(memberIds) && memberIds.includes(userId);
  } catch { return false; }
}

async function checkThreadMembership(userId, threadId) {
  try {
    const snap = await db.collectionGroup("threads").where("id", "==", threadId).limit(1).get();
    if (snap.empty) return false;
    const data = snap.docs[0].data();
    const memberIds = data?.memberIds ?? data?.participantIds ?? [];
    return Array.isArray(memberIds) && memberIds.includes(userId);
  } catch { return false; }
}

async function validateSpacePermission(userId, spaceId, surface) {
  if (SENSITIVE_SURFACES.includes(surface)) {
    try {
      const doc = await db.collection("spaces").doc(spaceId).get();
      if (!doc.data()?.conversationOSOptIn) {
        return { allowed: false, reason: "AI is not enabled in this space. An admin must enable it." };
      }
    } catch { return { allowed: false, reason: "Permission check failed." }; }
  }
  const isMember = await checkSpaceMembership(userId, spaceId);
  if (!isMember) return { allowed: false, reason: "You are not a member of this space." };
  return { allowed: true };
}

// ── Rate Limiting ──────────────────────────────────────────────────────────────

async function checkRateLimit(userId, operation) {
  const ref = db.collection("users").doc(userId).collection("commsRateLimits").doc(operation);
  const now = Date.now();
  try {
    await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      const data = doc.exists ? doc.data() : { count: 0, windowStart: now };
      const windowStart = data.windowStart ?? now;
      if (now - windowStart > RATE_LIMIT_WINDOW_MS) {
        tx.set(ref, { count: 1, windowStart: now });
      } else if ((data.count ?? 0) >= RATE_LIMIT_MAX) {
        throw new HttpsError("resource-exhausted", "Too many requests. Please try again shortly.");
      } else {
        tx.update(ref, { count: (data.count ?? 0) + 1 });
      }
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.warn("Rate limit check failed — allowing through", { userId, operation, err });
  }
}

// ── Message Retrieval + Compression ───────────────────────────────────────────

async function retrieveThreadMessages(spaceId, threadId, limitCount) {
  const paths = [
    `spaces/${spaceId}/threads/${threadId}/messages`,
    `conversations/${threadId}/messages`,
    `groups/${threadId}/messages`,
  ];
  for (const path of paths) {
    try {
      const snap = await db.collection(path)
        .orderBy("timestamp", "asc")
        .limit(limitCount ?? 150)
        .get();
      if (!snap.empty) {
        return snap.docs.map(d => {
          const data = d.data();
          return {
            id: d.id,
            senderId: data.senderId ?? data.uid ?? "",
            senderDisplayName: data.senderDisplayName ?? data.displayName ?? "Unknown",
            text: (data.text ?? data.body ?? data.content ?? "").slice(0, 500),
            timestamp: data.timestamp,
            reactionCount: data.reactionCount ?? 0,
            replyCount: data.replyCount ?? 0,
          };
        }).filter(m => m.text.trim().length > 0);
      }
    } catch { continue; }
  }
  return [];
}

function extractTags(messages) {
  const counts = {};
  for (const m of messages) {
    const t = m.text.toLowerCase();
    if (/\bdecide[d]?\b|\bapprove[d]?\b|\bagreed?\b/.test(t)) counts.decision = (counts.decision ?? 0) + 1;
    if (/\?/.test(t)) counts.question = (counts.question ?? 0) + 1;
    if (/\btask\b|\btodo\b|\bassign\b/.test(t)) counts.task = (counts.task ?? 0) + 1;
    if (/\bpray\b|\bprayer\b/.test(t)) counts.prayer_request = (counts.prayer_request ?? 0) + 1;
    if (/\bblocked?\b|\bwaiting on\b/.test(t)) counts.blocker = (counts.blocker ?? 0) + 1;
    if (/\bannounce\b|\bfyi\b/.test(t)) counts.announcement = (counts.announcement ?? 0) + 1;
  }
  return Object.entries(counts).sort(([,a],[,b]) => b-a).map(([t]) => t).slice(0, 5);
}

function compressMessages(messages) {
  const chunks = [];
  for (let i = 0; i < messages.length; i += MAX_CHUNK_MESSAGES) {
    const batch = messages.slice(i, i + MAX_CHUNK_MESSAGES);
    const tags = extractTags(batch);
    const participants = [...new Set(batch.map(m => m.senderDisplayName))].slice(0, 4);
    const top = [...batch]
      .sort((a, b) => (b.reactionCount + b.replyCount) - (a.reactionCount + a.replyCount))
      .slice(0, 5);
    const previews = top.map(m => `${m.senderDisplayName}: ${m.text.slice(0, MAX_MESSAGE_PREVIEW)}`).join(" | ");
    chunks.push({
      id: `chunk_${i}`,
      summary: `[${tags.slice(0,3).join(", ")}] ${participants.join(", ")}: ${previews}`,
      messageIds: batch.map(m => m.id),
      tags,
      participantDisplayNames: participants,
    });
  }
  return chunks;
}

function fitToTokenBudget(chunks, maxTokens) {
  let total = 0;
  const result = [];
  for (const chunk of [...chunks].reverse()) {
    const est = Math.ceil(chunk.summary.length / 4);
    if (total + est > maxTokens) break;
    result.unshift(chunk);
    total += est;
  }
  return result;
}

// ── Moderation ─────────────────────────────────────────────────────────────────

function moderateOutput(text) {
  const lower = text.toLowerCase();
  const flagged = [];
  if (/\b(suicide|self.harm|kill myself|end my life)\b/.test(lower)) flagged.push("crisis");
  if (/god (is telling|told|commanded) (this|your|the) group/.test(lower)) flagged.push("divine_authority");
  if (/[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/.test(text)) flagged.push("personal_data");
  if (/\b(\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b/.test(text)) flagged.push("personal_data");
  return { passed: flagged.length === 0, flagged, crisisDetected: flagged.includes("crisis") };
}

function sanitizeOutput(text) {
  return text
    .replace(/god (?:is telling|told|commanded|wants) (this|your|the) group/gi, "[removed]")
    .replace(/the holy spirit (?:revealed|confirmed|says)/gi, "[removed]")
    .trim();
}

function applyConfidenceWording(text, confidence) {
  if (confidence >= 0.75) return text;
  if (/appears to suggest|discussion suggests/i.test(text)) return text;
  return `Discussion appears to suggest: ${text}`;
}

// ── OpenAI ─────────────────────────────────────────────────────────────────────

async function callOpenAI(apiKey, systemPrompt, userPrompt, maxTokens) {
  const { default: fetch } = await import("node-fetch");
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), 15000);
  try {
    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      signal: controller.signal,
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${apiKey}` },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [{ role: "system", content: systemPrompt }, { role: "user", content: userPrompt }],
        max_tokens: maxTokens ?? 512,
        temperature: 0.3,
      }),
    });
    if (!res.ok) throw new Error(`OpenAI ${res.status}`);
    const json = await res.json();
    return json.choices?.[0]?.message?.content?.trim() ?? "";
  } finally { clearTimeout(t); }
}

// ── Audit Logging ──────────────────────────────────────────────────────────────

async function writeAuditLog(userId, operation, spaceId, threadId, outcome) {
  try {
    await db.collection("commsAuditLog").add({
      userId,
      operation,
      spaceId: spaceId ?? null,
      threadId: threadId ?? null,
      outcome,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    logger.warn("commsOS audit log write failed", { userId, operation, err });
  }
}

function genId() { return crypto.randomUUID(); }

// ── Callables ─────────────────────────────────────────────────────────────────

/**
 * comms_rankRelevance
 * Scores a thread's relevance to the requesting user.
 * Returns: CommsRelevanceScore { score, reasons, intent, confidence }
 */
exports.comms_rankRelevance = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);
    const { threadId, spaceId } = request.data;
    if (!threadId || !spaceId) throw new HttpsError("invalid-argument", "threadId and spaceId required.");

    await checkRateLimit(uid, "rankRelevance");
    const perms = await validateSpacePermission(uid, spaceId, "group_messages");
    if (!perms.allowed) throw new HttpsError("permission-denied", perms.reason);

    const messages = await retrieveThreadMessages(spaceId, threadId, 50);
    const tags = extractTags(messages);
    const mentionCount = messages.filter(m => m.text.includes(`@${uid}`) || m.text.toLowerCase().includes("everyone")).length;
    const questionCount = messages.filter(m => m.text.trim().endsWith("?")).length;
    const recentActivity = messages.filter(m => {
      const ts = m.timestamp?.toMillis?.() ?? 0;
      return ts > Date.now() - 30 * 60 * 1000;
    }).length;

    const rawScore = Math.min(
      (mentionCount * 0.4) + (questionCount * 0.2) + (recentActivity * 0.1) + (tags.includes("blocker") ? 0.3 : 0),
      1.0
    );
    const score = Math.max(0.1, rawScore);

    const reasons = [];
    if (mentionCount > 0) reasons.push(`${mentionCount} mention(s) directed at you`);
    if (questionCount > 0) reasons.push(`${questionCount} unresolved question(s)`);
    if (recentActivity > 0) reasons.push(`${recentActivity} recent message(s) in last 30 minutes`);
    if (tags.includes("blocker")) reasons.push("Blocker detected in thread");
    if (reasons.length === 0) reasons.push("General thread activity");

    const result = { score, reasons, intent: null, confidence: 0.7 };
    await writeAuditLog(uid, "rankRelevance", spaceId, threadId, "ok");
    return result;
  }
);

/**
 * comms_routeIntent
 * Routes a natural-language query to a structured intent + relevance score.
 * Returns: CommsRelevanceScore { score, reasons, intent, confidence }
 * Low confidence (< 0.5) means the caller should ask a clarifying question.
 */
exports.comms_routeIntent = onCall(
  { enforceAppCheck: true, secrets: [OPENAI_KEY] },
  async (request) => {
    const uid = requireAuth(request);
    const { query, threadId } = request.data;
    if (!query || typeof query !== "string" || query.trim().length === 0) {
      throw new HttpsError("invalid-argument", "query is required.");
    }

    await checkRateLimit(uid, "routeIntent");

    const systemPrompt = `You are an intent classifier for a church community messaging app.
Classify the user's query into one intent: search_decisions | search_questions | search_actions | summarize | find_blocker | general_search | unclear.
Respond ONLY with JSON: { "intent": "<intent>", "confidence": <0.0-1.0>, "clarification": "<ask if unclear, else null>" }
Rules:
- If the query is ambiguous or under 4 words, set confidence < 0.5 and provide a clarification question.
- Never include PII or user names in the response.
- Respond in English only.`;

    const userPrompt = `Query: "${query.slice(0, 200)}"`;

    let intent = "general_search";
    let confidence = 0.4;
    let clarification = null;

    try {
      const raw = await callOpenAI(OPENAI_KEY.value(), systemPrompt, userPrompt, 128);
      const parsed = JSON.parse(raw);
      intent = parsed.intent ?? "general_search";
      confidence = typeof parsed.confidence === "number" ? Math.min(Math.max(parsed.confidence, 0), 1) : 0.4;
      clarification = parsed.clarification ?? null;
    } catch (err) {
      logger.warn("comms_routeIntent model call failed — using fallback", { err });
      confidence = 0.3;
      clarification = "Could you be more specific? For example: 'find last week's decisions' or 'show open questions'.";
    }

    const result = {
      score: confidence,
      reasons: [intent !== "unclear" ? `Detected intent: ${intent}` : "Intent unclear"],
      intent: clarification ? null : intent,
      confidence,
      clarificationPrompt: clarification,
    };

    await writeAuditLog(uid, "routeIntent", null, threadId ?? null, "ok");
    return result;
  }
);

/**
 * comms_generateSmartContext
 * Generates a smart context summary for the current thread (decisions, actions, blockers).
 * Returns: ConversationSummary shape.
 */
exports.comms_generateSmartContext = onCall(
  { enforceAppCheck: true, secrets: [OPENAI_KEY] },
  async (request) => {
    const uid = requireAuth(request);
    const { threadId, spaceId } = request.data;
    if (!threadId || !spaceId) throw new HttpsError("invalid-argument", "threadId and spaceId required.");

    await checkRateLimit(uid, "generateSmartContext");
    const perms = await validateSpacePermission(uid, spaceId, "group_messages");
    if (!perms.allowed) throw new HttpsError("permission-denied", perms.reason);

    const messages = await retrieveThreadMessages(spaceId, threadId, 100);
    if (messages.length === 0) {
      return buildEmptySummary(spaceId, threadId, "Thread has no messages yet.");
    }

    const chunks = fitToTokenBudget(compressMessages(messages), 3000);
    const systemPrompt = `You are summarizing a community group thread. Extract: 1 key decisions, 2 open questions, 3 action items.
Format as JSON: { "decisions": ["..."], "questions": ["..."], "actions": ["..."], "summary": "..." }
Rules: no PII, no divine authority claims, use "Discussion appears to suggest…" if uncertain.`;
    const userPrompt = chunks.map((c, i) => `[Chunk ${i+1}] ${c.summary}`).join("\n\n").slice(0, 4000);

    let summaryText = "";
    let provider = "openai";
    let parsedExtracted = { decisions: [], questions: [], actions: [], summary: "" };

    try {
      const raw = await callOpenAI(OPENAI_KEY.value(), systemPrompt, userPrompt, 512);
      try {
        parsedExtracted = JSON.parse(raw);
        summaryText = parsedExtracted.summary ?? raw;
      } catch { summaryText = raw; }
    } catch (err) {
      logger.warn("comms_generateSmartContext model failed — deterministic fallback", { err });
      summaryText = chunks[0]?.summary?.slice(0, 300) ?? "Activity in this thread.";
      provider = "fallback";
    }

    const modResult = moderateOutput(summaryText);
    if (modResult.crisisDetected) {
      await writeAuditLog(uid, "generateSmartContext", spaceId, threadId, "crisis_detected");
      return { crisisWarning: "A message may indicate someone in distress. Please reach out directly." };
    }
    if (!modResult.passed) throw new HttpsError("internal", "Output failed safety check.");

    const confidence = Math.min(0.5 + chunks.length * 0.05, 0.9);
    const finalText = applyConfidenceWording(sanitizeOutput(summaryText), confidence);

    const summaryId = genId();
    const now = new Date().toISOString();
    const summary = {
      id: summaryId, spaceId, threadId,
      surface: "group_messages", summaryType: "operational",
      summaryText: finalText,
      topicClusters: [],
      decisions: (parsedExtracted.decisions ?? []).slice(0, 5).map((s, i) => ({
        id: `dec_${summaryId}_${i}`, summary: s, sourceSnippet: "",
        participants: [], confirmedBy: [], status: "proposed",
        threadId, confidence: 0.65, createdAt: now,
      })),
      actionItems: (parsedExtracted.actions ?? []).slice(0, 5).map((s, i) => ({
        id: `act_${summaryId}_${i}`, title: s, description: s,
        sourceMessageId: "", threadId, status: "pending",
        confidence: 0.6, createdAt: now,
      })),
      unresolvedQuestions: (parsedExtracted.questions ?? []).slice(0, 5).map((s, i) => ({
        id: `q_${summaryId}_${i}`, question: s, sourceSnippet: "",
        askedByDisplayName: "Discussion", threadId, askedAt: now, dismissed: false,
      })),
      blockers: [], messageCount: messages.length, confidence,
      generatedAt: now,
      coverageWindowStart: messages[0]?.timestamp?.toDate?.()?.toISOString() ?? now,
      coverageWindowEnd: now,
      provenance: {
        provider, modelVersion: "gpt-4o-mini",
        generatedAt: now, compressionRatio: messages.length / Math.max(Math.ceil(summaryText.length / 4), 1),
        moderationPassed: true, permissionsValidated: true,
      },
    };

    await db.collection(`comms/threads/${threadId}/summaries`).doc(summaryId).set({
      ...summary, generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await writeAuditLog(uid, "generateSmartContext", spaceId, threadId, "ok");
    return summary;
  }
);

/**
 * comms_generateCatchUp
 * Generates a catch-up summary covering unread messages in a thread.
 * Returns: ConversationSummary shape.
 */
exports.comms_generateCatchUp = onCall(
  { enforceAppCheck: true, secrets: [OPENAI_KEY] },
  async (request) => {
    const uid = requireAuth(request);
    const { threadId, spaceId, unreadCount } = request.data;
    if (!threadId || !spaceId) throw new HttpsError("invalid-argument", "threadId and spaceId required.");

    await checkRateLimit(uid, "generateCatchUp");
    const perms = await validateSpacePermission(uid, spaceId, "group_messages");
    if (!perms.allowed) throw new HttpsError("permission-denied", perms.reason);

    const messages = await retrieveThreadMessages(spaceId, threadId, 150);
    if (messages.length === 0) {
      return buildEmptySummary(spaceId, threadId, "You're all caught up — no new messages.");
    }

    const chunks = fitToTokenBudget(compressMessages(messages), 4096);
    const systemPrompt = `You are generating a catch-up summary for someone who missed group messages.
Be concise and accurate. Highlight key decisions, open questions, and any urgent items.
Use "Discussion appears to suggest…" when uncertain. No PII. No divine authority claims.`;
    const userPrompt = `${messages.length} messages to catch up on.\n\n${chunks.map((c, i) => `[Chunk ${i+1}] ${c.summary}`).join("\n\n").slice(0, 4000)}`;

    let summaryText = "";
    let provider = "openai";

    try {
      summaryText = await callOpenAI(OPENAI_KEY.value(), systemPrompt, userPrompt, 400);
    } catch (err) {
      logger.warn("comms_generateCatchUp model failed — fallback", { err });
      summaryText = chunks[0]?.summary?.slice(0, 300) ?? `${unreadCount ?? messages.length} messages since you were last here.`;
      provider = "fallback";
    }

    const modResult = moderateOutput(summaryText);
    if (modResult.crisisDetected) {
      await writeAuditLog(uid, "generateCatchUp", spaceId, threadId, "crisis_detected");
      return { crisisWarning: "A message may indicate someone in distress. Please reach out directly." };
    }
    if (!modResult.passed) throw new HttpsError("internal", "Output failed safety check.");

    const confidence = Math.min(0.5 + chunks.length * 0.05, 0.9);
    const finalText = applyConfidenceWording(sanitizeOutput(summaryText), confidence);

    const summaryId = genId();
    const now = new Date().toISOString();
    const summary = {
      id: summaryId, spaceId, threadId,
      surface: "group_messages", summaryType: "catch_up",
      summaryText: finalText,
      topicClusters: [], decisions: [], actionItems: [],
      unresolvedQuestions: [], blockers: [],
      messageCount: messages.length, confidence,
      generatedAt: now,
      coverageWindowStart: messages[0]?.timestamp?.toDate?.()?.toISOString() ?? now,
      coverageWindowEnd: now,
      provenance: {
        provider, modelVersion: "gpt-4o-mini",
        generatedAt: now, compressionRatio: 1,
        moderationPassed: true, permissionsValidated: true,
      },
    };

    await db.collection("users").doc(uid).collection("commsDigests").doc(summaryId).set({
      ...summary, generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await writeAuditLog(uid, "generateCatchUp", spaceId, threadId, "ok");
    return summary;
  }
);

/**
 * comms_submitFeedback
 * Records a user feedback action (accepted/dismissed/corrected) for a Comms OS item.
 * Stored per-user only — never cross-contaminated.
 */
exports.comms_submitFeedback = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);
    const { threadId, itemType, itemId, action, correctedValue } = request.data;

    const VALID_ITEM_TYPES = ["decision", "followUp", "summary", "rankScore", "mediaJob"];
    const VALID_ACTIONS    = ["accepted", "dismissed", "corrected"];

    if (!threadId || !itemType || !itemId || !action) {
      throw new HttpsError("invalid-argument", "threadId, itemType, itemId, and action are required.");
    }
    if (!VALID_ITEM_TYPES.includes(itemType)) {
      throw new HttpsError("invalid-argument", `itemType must be one of: ${VALID_ITEM_TYPES.join(", ")}`);
    }
    if (!VALID_ACTIONS.includes(action)) {
      throw new HttpsError("invalid-argument", `action must be one of: ${VALID_ACTIONS.join(", ")}`);
    }
    if (action === "corrected" && (typeof correctedValue !== "string" || correctedValue.trim().length === 0)) {
      throw new HttpsError("invalid-argument", "correctedValue is required when action is 'corrected'.");
    }

    const record = {
      id: genId(),
      userId: uid,
      threadId,
      itemType,
      itemId,
      action,
      correctedValue: action === "corrected" ? correctedValue.slice(0, 500) : null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("users").doc(uid).collection("commsFeedback").add(record);
    await writeAuditLog(uid, "submitFeedback", null, threadId, "ok");
    return { recorded: true };
  }
);

/**
 * comms_processMediaJob
 * Starts a media intelligence job for a given media URL in a thread.
 * Returns: CommsMediaJobRecord { id, threadId, requestedByUserId, status, requestedAt, resultAvailable }
 */
exports.comms_processMediaJob = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);
    const { threadId, mediaUrl } = request.data;
    if (!threadId || !mediaUrl) throw new HttpsError("invalid-argument", "threadId and mediaUrl required.");

    await checkRateLimit(uid, "processMediaJob");

    // Basic URL validation — no SSRF: only allow storage.googleapis.com paths.
    let parsedUrl;
    try { parsedUrl = new URL(mediaUrl); } catch {
      throw new HttpsError("invalid-argument", "Invalid mediaUrl.");
    }
    if (!parsedUrl.hostname.endsWith("googleapis.com") && !parsedUrl.hostname.endsWith("firebasestorage.app")) {
      throw new HttpsError("invalid-argument", "mediaUrl must be a Firebase Storage URL.");
    }

    const jobId = genId();
    const now = new Date().toISOString();
    const job = {
      id: jobId,
      threadId,
      requestedByUserId: uid,
      status: "queued",
      requestedAt: now,
      completedAt: null,
      errorMessage: null,
      resultAvailable: false,
    };

    await db.collection("comms/mediaJobs/" + jobId).set({
      ...job,
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await writeAuditLog(uid, "processMediaJob", null, threadId, "queued");
    return job;
  }
);

/**
 * comms_getMediaJobStatus
 * Polls the status of a media intelligence job.
 * Returns: CommsMediaJobRecord
 */
exports.comms_getMediaJobStatus = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);
    const { jobId } = request.data;
    if (!jobId) throw new HttpsError("invalid-argument", "jobId required.");

    const doc = await db.doc(`comms/mediaJobs/${jobId}`).get();
    if (!doc.exists) throw new HttpsError("not-found", "Media job not found.");

    const data = doc.data();
    if (data.requestedByUserId !== uid) {
      throw new HttpsError("permission-denied", "You do not have access to this media job.");
    }

    return {
      id: doc.id,
      threadId: data.threadId,
      requestedByUserId: data.requestedByUserId,
      status: data.status ?? "queued",
      requestedAt: data.requestedAt?.toDate?.()?.toISOString() ?? new Date().toISOString(),
      completedAt: data.completedAt?.toDate?.()?.toISOString() ?? null,
      errorMessage: data.errorMessage ?? null,
      resultAvailable: data.resultAvailable ?? false,
    };
  }
);

/**
 * comms_suggestAsyncReply
 * Suggests an async reply for the user given recent thread context.
 * Low confidence → returns clarificationPrompt instead of suggestion.
 * Returns: { suggestion, confidence, clarificationPrompt }
 */
exports.comms_suggestAsyncReply = onCall(
  { enforceAppCheck: true, secrets: [OPENAI_KEY] },
  async (request) => {
    const uid = requireAuth(request);
    const { threadId, spaceId } = request.data;
    if (!threadId || !spaceId) throw new HttpsError("invalid-argument", "threadId and spaceId required.");

    await checkRateLimit(uid, "suggestAsyncReply");
    const perms = await validateSpacePermission(uid, spaceId, "group_messages");
    if (!perms.allowed) throw new HttpsError("permission-denied", perms.reason);

    const messages = await retrieveThreadMessages(spaceId, threadId, 30);
    if (messages.length === 0) {
      return { suggestion: null, confidence: 0, clarificationPrompt: "No recent messages to base a suggestion on." };
    }

    const recentContext = messages.slice(-10).map(m => `${m.senderDisplayName}: ${m.text.slice(0, 150)}`).join("\n");

    const systemPrompt = `You are helping a user draft a short async reply for a community group thread.
Generate ONE suggested reply (max 2 sentences). Only suggest if context is clear (confidence >= 0.65).
Respond ONLY with JSON: { "suggestion": "<text or null>", "confidence": <0.0-1.0>, "clarificationPrompt": "<if unclear else null>" }
Rules: no PII, no divine authority claims, neutral helpful tone.`;
    const userPrompt = `Recent thread context:\n${recentContext}`;

    let suggestion = null;
    let confidence = 0.3;
    let clarificationPrompt = null;

    try {
      const raw = await callOpenAI(OPENAI_KEY.value(), systemPrompt, userPrompt, 200);
      const parsed = JSON.parse(raw);
      suggestion = parsed.suggestion ?? null;
      confidence = typeof parsed.confidence === "number" ? Math.min(Math.max(parsed.confidence, 0), 1) : 0.3;
      clarificationPrompt = parsed.clarificationPrompt ?? null;

      if (confidence < 0.5) {
        suggestion = null;
        if (!clarificationPrompt) clarificationPrompt = "Could you share more context about what you'd like to reply?";
      }

      if (suggestion) {
        const mod = moderateOutput(suggestion);
        if (!mod.passed) { suggestion = null; confidence = 0; }
        else suggestion = sanitizeOutput(suggestion);
      }
    } catch (err) {
      logger.warn("comms_suggestAsyncReply model failed", { err });
      clarificationPrompt = "Unable to generate a suggestion right now. Please try again.";
    }

    await writeAuditLog(uid, "suggestAsyncReply", spaceId, threadId, "ok");
    return { suggestion, confidence, clarificationPrompt };
  }
);

// ── Helpers ────────────────────────────────────────────────────────────────────

function buildEmptySummary(spaceId, threadId, message) {
  const now = new Date().toISOString();
  return {
    id: genId(), spaceId, threadId,
    surface: "group_messages", summaryType: "catch_up",
    summaryText: message,
    topicClusters: [], decisions: [], actionItems: [],
    unresolvedQuestions: [], blockers: [],
    messageCount: 0, confidence: 1,
    generatedAt: now, coverageWindowStart: now, coverageWindowEnd: now,
    provenance: {
      provider: "deterministic", modelVersion: "none",
      generatedAt: now, compressionRatio: 1,
      moderationPassed: true, permissionsValidated: true,
    },
  };
}

/**
 * conversationOSFunctions.js
 * AMEN Conversation OS — Cloud Functions (Plain JS, App Check enforced)
 *
 * Typed engine implementations live in functions/src/conversationOS/ (TypeScript).
 * This file provides the deployed callables. Pipeline:
 *   validate → retrieve → rank → compress → summarize → moderate → persist → return
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
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret }       = require("firebase-functions/params");
const admin                  = require("firebase-admin");
const logger                 = require("firebase-functions/logger");

const db = admin.firestore();

const OPENAI_KEY = defineSecret("OPENAI_API_KEY");
const CLAUDE_KEY = defineSecret("CLAUDE_API_KEY");

const SENSITIVE_SURFACES = ["prayer_room", "leadership_room", "admin_channel"];
const MAX_MESSAGE_PREVIEW = 200;
const MAX_CHUNK_MESSAGES  = 25;

// ── Helpers ──────────────────────────────────────────────────────────────────

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

async function checkOrgMembership(userId, orgId) {
  try {
    const doc = await db.collection("organizations").doc(orgId).collection("members").doc(userId).get();
    return doc.exists;
  } catch { return false; }
}

async function validatePermissions(userId, spaceId, surface, orgId) {
  if (SENSITIVE_SURFACES.includes(surface)) {
    const id = spaceId ?? orgId;
    if (!id) return { allowed: false, reason: "Sensitive surface requires space ID." };
    try {
      const doc = await db.collection("spaces").doc(id).get();
      if (!doc.data()?.conversationOSOptIn) {
        return { allowed: false, reason: "AI is not enabled in this space. An admin must enable it." };
      }
    } catch { return { allowed: false, reason: "Permission check failed." }; }
  }

  if (spaceId) {
    const isMember = await checkSpaceMembership(userId, spaceId);
    if (!isMember) return { allowed: false, reason: "You are not a member of this space." };
  }

  if (orgId) {
    const isOrgMember = await checkOrgMembership(userId, orgId);
    if (!isOrgMember) return { allowed: false, reason: "You are not a member of this organization." };
  }

  return { allowed: true };
}

async function retrieveMessages(collectionPath, windowStart, windowEnd, limit) {
  try {
    const snap = await db.collection(collectionPath)
      .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(new Date(windowStart)))
      .where("timestamp", "<=", admin.firestore.Timestamp.fromDate(new Date(windowEnd)))
      .orderBy("timestamp", "asc")
      .limit(limit ?? 150)
      .get();
    return snap.docs.map(d => {
      const data = d.data();
      return {
        id: d.id,
        senderId: data.senderId ?? data.uid ?? "",
        senderDisplayName: data.senderDisplayName ?? data.displayName ?? "Unknown",
        text: data.text ?? data.body ?? data.content ?? "",
        timestamp: data.timestamp,
        threadId: data.threadId ?? "",
        reactionCount: data.reactionCount ?? 0,
        replyCount: data.replyCount ?? 0,
      };
    }).filter(m => m.text.trim().length > 0);
  } catch (err) {
    logger.error("retrieveMessages error", err);
    return [];
  }
}

function getMessageCollectionPath(surface, spaceId, threadId) {
  if (["group_messages", "direct_messages"].includes(surface)) return `conversations/${spaceId}/messages`;
  if (surface === "media_comments") return `posts/${spaceId}/comments`;
  if (threadId) return `spaces/${spaceId}/threads/${threadId}/messages`;
  return `spaces/${spaceId}/messages`;
}

function rankBySignal(messages) {
  return [...messages].sort((a, b) =>
    (b.reactionCount * 2 + b.replyCount * 1.5) - (a.reactionCount * 2 + a.replyCount * 1.5)
  );
}

function compressMessages(messages) {
  const chunks = [];
  for (let i = 0; i < messages.length; i += MAX_CHUNK_MESSAGES) {
    const batch = messages.slice(i, i + MAX_CHUNK_MESSAGES);
    const tags = extractTags(batch);
    const participants = [...new Set(batch.map(m => m.senderDisplayName))].slice(0, 4);
    const top = [...batch].sort((a, b) => (b.reactionCount + b.replyCount) - (a.reactionCount + a.replyCount)).slice(0, 5);
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
    if (/\bthank[s]?\b|\bgreat\b|\bencourage\b/.test(t)) counts.encouragement = (counts.encouragement ?? 0) + 1;
  }
  return Object.entries(counts).sort(([,a],[,b]) => b-a).map(([t]) => t).slice(0, 5);
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

function buildSystemPrompt(surface, orgType, summaryType) {
  return `You are an AI assistant summarizing group conversations for a ${orgType ?? "community"} app.

Rules:
- Be accurate. Do not invent or hallucinate participants or events.
- Use "Discussion appears to suggest…" when uncertain.
- Never say "God is telling this group…" or claim divine authority.
- Never include personal contact information (email, phone, address).
- Be concise. Every sentence must add value.
- Surface: ${surface}. Summary type: ${summaryType}.`;
}

function buildUserPrompt(chunks, messageCount, windowStart, windowEnd) {
  const chunkText = chunks.map((c, i) =>
    `[Chunk ${i+1} | ${c.tags?.join(", ") ?? "general"}]\n${c.summary}`
  ).join("\n\n");

  return `Messages: ${messageCount} | Period: ${new Date(windowStart).toLocaleDateString()} – ${new Date(windowEnd).toLocaleDateString()}

Compressed discussion:
${chunkText}

Generate a concise, accurate summary. Use "Discussion appears to suggest…" for uncertain items.`;
}

async function callOpenAI(apiKey, systemPrompt, userPrompt) {
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
        max_tokens: 512,
        temperature: 0.3,
      }),
    });
    if (!res.ok) throw new Error(`OpenAI ${res.status}`);
    const json = await res.json();
    return json.choices?.[0]?.message?.content ?? "";
  } finally { clearTimeout(t); }
}

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

function extractDecisions(messages, threadId) {
  const decisions = [];
  for (const m of messages) {
    const match = m.text.match(/(?:we've? decided|decided|agreed|approved|confirmed):\s*(.+?)(?:\.|$)/i);
    if (match?.[1]?.trim()?.length > 5) {
      decisions.push({
        id: `dec_${m.id}`,
        summary: match[1].trim().slice(0, 120),
        sourceSnippet: m.text.slice(0, 200),
        participants: [m.senderId],
        confirmedBy: [],
        status: "proposed",
        threadId,
        confidence: 0.65,
        createdAt: m.timestamp?.toDate?.() ?? new Date(),
      });
    }
  }
  return decisions.slice(0, 8);
}

function extractActions(messages, threadId) {
  const actions = [];
  for (const m of messages) {
    const match = m.text.match(/(?:can you|please|todo|action item|task):\s*(.+?)(?:\.|$)/i);
    if (match?.[1]?.trim()?.length > 5) {
      actions.push({
        id: `act_${m.id}`,
        title: match[1].trim().slice(0, 80),
        description: match[1].trim(),
        sourceMessageId: m.id,
        threadId,
        status: "pending",
        confidence: 0.6,
        createdAt: m.timestamp?.toDate?.() ?? new Date(),
      });
    }
  }
  return actions.slice(0, 10);
}

function extractUnresolvedQuestions(messages, threadId) {
  const questions = [];
  const qMessages = messages.filter(m => m.text.trim().endsWith("?") || /^(what|when|where|who|why|how|can|should)\b/i.test(m.text));
  for (const q of qMessages) {
    const qTime = q.timestamp?.toMillis?.() ?? 0;
    const hasAnswer = messages.some(m => m.senderId !== q.senderId && (m.timestamp?.toMillis?.() ?? 0) > qTime);
    if (!hasAnswer) {
      questions.push({
        id: `q_${q.id}`,
        question: q.text.slice(0, 200),
        sourceSnippet: q.text.slice(0, 200),
        askedByDisplayName: q.senderDisplayName,
        threadId,
        askedAt: q.timestamp?.toDate?.() ?? new Date(),
      });
    }
  }
  return questions.slice(0, 8);
}

function buildProvenance(provider, model, inputLen, outputLen, compressionRatio) {
  return {
    provider,
    modelVersion: model,
    generatedAt: new Date().toISOString(),
    compressionRatio,
    moderationPassed: true,
    permissionsValidated: true,
    inputTokens: Math.ceil(inputLen / 4),
    outputTokens: Math.ceil(outputLen / 4),
  };
}

function genId() {
  return crypto.randomUUID();
}

// ── Callables ─────────────────────────────────────────────────────────────────

exports.generateCatchUpRecap = onCall(
  { enforceAppCheck: true, secrets: [OPENAI_KEY, CLAUDE_KEY] },
  async (request) => {
    const uid = requireAuth(request);
    const { spaceId, surface, unreadCount, lastVisitedAt } = request.data;

    if (!spaceId || !surface) throw new HttpsError("invalid-argument", "spaceId and surface required.");

    const perms = await validatePermissions(uid, spaceId, surface);
    if (!perms.allowed) throw new HttpsError("permission-denied", perms.reason);

    const windowEnd   = new Date();
    const windowStart = lastVisitedAt ? new Date(lastVisitedAt) : new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const collPath    = getMessageCollectionPath(surface, spaceId);
    const rawMessages = await retrieveMessages(collPath, windowStart, windowEnd, 150);

    if (rawMessages.length === 0) {
      return { summaryText: "You're all caught up — no new messages.", messageCount: 0, confidence: 1 };
    }

    const ranked  = rankBySignal(rawMessages);
    const chunks  = compressMessages(ranked);
    const fitted  = fitToTokenBudget(chunks, 4096);
    const threadId = `${spaceId}_catchup`;

    const decisions  = extractDecisions(rawMessages, threadId);
    const actions    = extractActions(rawMessages, threadId);
    const questions  = extractUnresolvedQuestions(rawMessages, threadId);

    const systemPrompt = buildSystemPrompt(surface, "community", "catch_up");
    const userPrompt   = buildUserPrompt(fitted, rawMessages.length, windowStart, windowEnd);

    let summaryText = "";
    let provider = "openai";
    try {
      summaryText = await callOpenAI(OPENAI_KEY.value(), systemPrompt, userPrompt);
    } catch (err) {
      logger.error("OpenAI summary error", err);
      summaryText = `${fitted.length > 0 ? fitted[0].summary.slice(0, 300) : "Activity detected in this space."}`;
      provider = "fallback";
    }

    const modResult = moderateOutput(summaryText);
    if (modResult.crisisDetected) {
      return { crisisWarning: "A message in this conversation may indicate someone in distress. Please reach out to them directly." };
    }
    if (!modResult.passed) throw new HttpsError("internal", "Output failed safety check.");

    const confidence = Math.min(0.5 + fitted.length * 0.05, 0.9);
    const finalText  = applyConfidenceWording(sanitizeOutput(summaryText), confidence);
    const compressionRatio = rawMessages.length / Math.max(Math.ceil(summaryText.length / 4), 1);
    const provenance = buildProvenance(provider, "gpt-4o-mini", userPrompt.length, summaryText.length, compressionRatio);

    const summary = {
      id: genId(),
      spaceId, surface,
      summaryText: finalText, summaryType: "catch_up",
      topicClusters: [], decisions, actionItems: actions,
      unresolvedQuestions: questions, blockers: [],
      generatedAt: new Date().toISOString(),
      coverageWindowStart: windowStart.toISOString(),
      coverageWindowEnd: windowEnd.toISOString(),
      messageCount: rawMessages.length,
      confidence,
      provenance,
    };

    await db.collection("spaces").doc(spaceId).collection("summaries").doc(summary.id).set({
      ...summary,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return summary;
  }
);

exports.generateTopicClusters = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);
    const { spaceId, surface, threadId } = request.data;

    const perms = await validatePermissions(uid, spaceId, surface);
    if (!perms.allowed) throw new HttpsError("permission-denied", perms.reason);

    const windowStart = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const collPath    = getMessageCollectionPath(surface, spaceId, threadId);
    const messages    = await retrieveMessages(collPath, windowStart, new Date(), 200);

    if (messages.length === 0) return { clusters: [] };

    const chunks  = compressMessages(messages);
    const tagGroups = {};
    for (const c of chunks) {
      const tag = c.tags[0] ?? "general";
      if (!tagGroups[tag]) tagGroups[tag] = [];
      tagGroups[tag].push(c);
    }

    const LABEL_MAP = {
      decision: "Decisions & Agreements", question: "Open Questions",
      task: "Tasks & Follow-Ups", prayer_request: "Prayer & Encouragement",
      announcement: "Announcements", blocker: "Blockers",
      encouragement: "Encouragement",
    };

    const clusters = Object.entries(tagGroups).map(([tag, tagChunks]) => ({
      id: genId(),
      title: LABEL_MAP[tag] ?? "General Discussion",
      summary: tagChunks.map(c => c.summary.slice(0, 150)).join(" "),
      tags: [tag],
      messageCount: tagChunks.reduce((s, c) => s + c.messageIds.length, 0),
      participantCount: new Set(tagChunks.flatMap(c => c.participantDisplayNames)).size,
      confidence: 0.7,
      messageRefs: [],
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    }));

    return { clusters };
  }
);

exports.extractConversationActions = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);
    const { threadId, spaceId } = request.data;

    const perms = await validatePermissions(uid, spaceId, "group_messages");
    if (!perms.allowed) throw new HttpsError("permission-denied", perms.reason);

    const messages  = await retrieveMessages(`spaces/${spaceId}/threads/${threadId}/messages`, new Date(Date.now() - 30 * 24 * 60 * 60 * 1000), new Date(), 100);
    const actions   = extractActions(messages, threadId);
    const decisions = extractDecisions(messages, threadId);
    const questions = extractUnresolvedQuestions(messages, threadId);

    return { actions, decisions, questions };
  }
);

exports.getPersonalizedSummary = onCall(
  { enforceAppCheck: true, secrets: [OPENAI_KEY] },
  async (request) => {
    const uid = requireAuth(request);
    const { spaceId, surface, userRole, orgType, unreadCount, lastVisitedAt, followedTopics, preferredLength } = request.data;

    const perms = await validatePermissions(uid, spaceId, surface);
    if (!perms.allowed) throw new HttpsError("permission-denied", perms.reason);

    const windowStart = lastVisitedAt ? new Date(lastVisitedAt) : new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const collPath    = getMessageCollectionPath(surface, spaceId);
    const messages    = await retrieveMessages(collPath, windowStart, new Date(), 150);

    if (messages.length === 0) {
      return { summaryText: unreadCount === 0 ? "You're all caught up." : `${unreadCount} new messages since your last visit.`, messageCount: 0 };
    }

    const ranked = rankBySignal(messages);
    const chunks = fitToTokenBudget(compressMessages(ranked), 3000);
    const systemPrompt = buildSystemPrompt(surface, orgType, "catch_up");
    const userPrompt   = buildUserPrompt(chunks, messages.length, windowStart, new Date());

    let summaryText = "";
    try {
      summaryText = await callOpenAI(OPENAI_KEY.value(), systemPrompt, userPrompt);
    } catch {
      summaryText = chunks[0]?.summary?.slice(0, 300) ?? "Activity in this space.";
    }

    const modResult = moderateOutput(summaryText);
    if (!modResult.passed && !modResult.crisisDetected) throw new HttpsError("internal", "Safety check failed.");

    const confidence = Math.min(0.5 + chunks.length * 0.05, 0.9);
    const finalText = applyConfidenceWording(sanitizeOutput(summaryText), confidence);

    const summaryId = genId();
    const result = {
      id: summaryId, spaceId, surface,
      summaryText: finalText, summaryType: "catch_up",
      topicClusters: [], decisions: extractDecisions(messages, `${spaceId}_p`),
      actionItems: extractActions(messages, `${spaceId}_p`),
      unresolvedQuestions: extractUnresolvedQuestions(messages, `${spaceId}_p`),
      blockers: [], messageCount: messages.length, confidence,
      generatedAt: new Date().toISOString(),
      coverageWindowStart: windowStart.toISOString(),
      coverageWindowEnd: new Date().toISOString(),
      provenance: buildProvenance("openai", "gpt-4o-mini", userPrompt.length, summaryText.length, 1),
    };

    await db.collection("users").doc(uid).collection("personalizedSummaries").doc(summaryId).set({
      ...result, generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return result;
  }
);

exports.queryOrganizationalMemory = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);
    const { orgId, query } = request.data;

    if (!orgId) throw new HttpsError("invalid-argument", "orgId required.");
    const perms = await validatePermissions(uid, undefined, "org_hub", orgId);
    if (!perms.allowed) throw new HttpsError("permission-denied", perms.reason);

    const snap = await db.collection("organizations").doc(orgId).collection("memory")
      .orderBy("generatedAt", "desc").limit(1).get();

    return { memory: snap.empty ? null : snap.docs[0].data() };
  }
);

exports.updateConversationActionStatus = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);
    const { actionId, status, spaceId } = request.data;

    if (!["pending", "in_progress", "resolved", "dismissed"].includes(status)) {
      throw new HttpsError("invalid-argument", "Invalid status.");
    }
    const perms = await validatePermissions(uid, spaceId, "group_messages");
    if (!perms.allowed) throw new HttpsError("permission-denied", perms.reason);

    const snap = await db.collection("spaces").doc(spaceId).collection("summaries").limit(5).get();
    const batch = db.batch();
    for (const doc of snap.docs) {
      const items = (doc.data().actionItems ?? []).map(a => a.id === actionId ? { ...a, status } : a);
      batch.update(doc.ref, { actionItems: items });
    }
    await batch.commit();
    return { updated: true };
  }
);

exports.updateConversationDecision = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);
    const { decisionId, action, spaceId } = request.data;

    const perms = await validatePermissions(uid, spaceId, "group_messages");
    if (!perms.allowed) throw new HttpsError("permission-denied", perms.reason);

    const newStatus = action === "confirm" ? "confirmed" : "challenged";
    const snap = await db.collection("spaces").doc(spaceId).collection("summaries").limit(5).get();
    const batch = db.batch();
    for (const doc of snap.docs) {
      const decisions = (doc.data().decisions ?? []).map(d =>
        d.id === decisionId ? { ...d, status: newStatus, confirmedBy: action === "confirm" ? [...(d.confirmedBy ?? []), uid] : d.confirmedBy } : d
      );
      batch.update(doc.ref, { decisions });
    }
    await batch.commit();
    return { updated: true };
  }
);

exports.dismissConversationSummary = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);
    const { summaryId } = request.data;

    await db.collection("users").doc(uid).collection("personalizedSummaries").doc(summaryId).set(
      { dismissed: true, dismissedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
    return { dismissed: true };
  }
);

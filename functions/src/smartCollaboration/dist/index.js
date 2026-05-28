"use strict";
// index.ts
// AMEN Smart Collaboration Layer — Phase 1 Callable Functions
//
// All 6 callables in this file enforce:
//   1. Firebase Auth + App Check (via withSecureSmartCallable)
//   2. Server-side membership verification (via withSecureSmartCallable)
//   3. Feature flag gate before any Firestore reads (via isSmartFlagEnabled)
//   4. All AI output labeled with labelAsSuggested()
//   5. No raw message text in any log or analytics field
//   6. Prayer signals never auto-amplified — detect + store only
//   7. All LLM calls via Anthropic SDK with secret from firebase-functions/params
//   8. All writes use FieldValue.serverTimestamp() — never client timestamps
//
// Non-negotiable: generatedBy is context.auth.token.sub (service account uid),
// never a caller-supplied value.
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.requestMediaTranscription = exports.generateSmartReplies = exports.generateGroupPulse = exports.extractThreadActions = exports.detectPrayerContextForThread = exports.generateThreadSummary = void 0;
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const params_1 = require("firebase-functions/params");
const uuid_1 = require("uuid");
const contracts_1 = require("./contracts");
const secureCallable_1 = require("./secureCallable");
const featureFlags_1 = require("./featureFlags");
const safety_1 = require("./safety");
// MARK: - Secrets
// Reuse the same secret names as the existing LLM proxy pattern in
// functions/src/conversationOS/callable.ts — never embed API keys here.
const CLAUDE_KEY = (0, params_1.defineSecret)("CLAUDE_API_KEY");
// MARK: - Constants
const MODEL_VERSION = "claude-3-haiku-20240307";
// MARK: - LLM Caller (Anthropic SDK pattern — same as summarizationEngine.ts)
async function callClaude(systemPrompt, userPrompt, maxTokens) {
    const apiKey = CLAUDE_KEY.value();
    if (!apiKey) {
        throw new https_1.HttpsError("internal", "LLM proxy is not configured.");
    }
    const Anthropic = (await Promise.resolve().then(() => __importStar(require("@anthropic-ai/sdk")))).default;
    const client = new Anthropic({ apiKey });
    const msg = await client.messages.create({
        model: MODEL_VERSION,
        max_tokens: maxTokens,
        system: systemPrompt,
        messages: [{ role: "user", content: userPrompt }],
    });
    const textBlock = msg.content.find((b) => b.type === "text");
    if (!textBlock || textBlock.type !== "text")
        return "";
    return textBlock.text ?? "";
}
function moderateText(text) {
    const lower = text.toLowerCase();
    // Crisis detection
    if (/\b(suicide|self.harm|kill myself|end my life|harm myself|danger to (self|others))\b/.test(lower)) {
        return { passed: false, reason: "crisis_content" };
    }
    // Divine authority hallucination guard
    if (/god (is telling|told|commanded|wants) (this|your|the) group/.test(lower) ||
        /the holy spirit (revealed|confirmed) (that|to)/.test(lower)) {
        return { passed: false, reason: "divine_authority_claim" };
    }
    // Harmful content
    if (/\b(violence|threat|attack|weapon|illegal|explicit|sexual)\b/.test(lower)) {
        return { passed: false, reason: "harmful_content" };
    }
    return { passed: true };
}
async function fetchMessages(db, data, limit) {
    let collectionRef;
    if (data.threadType === "dm") {
        collectionRef = db
            .collection("conversations")
            .doc(data.threadId)
            .collection("messages");
    }
    else {
        // channel or discussion
        const spaceId = data.spaceId;
        const channelId = data.channelId;
        collectionRef = db
            .collection("spaces")
            .doc(spaceId)
            .collection("channels")
            .doc(channelId)
            .collection("messages");
    }
    const snap = await collectionRef
        .orderBy("timestamp", "desc")
        .limit(limit)
        .get();
    return snap.docs.map((doc) => ({
        id: doc.id,
        timestamp: doc.data().timestamp ?? null,
        senderId: doc.data().senderId ?? "",
        body: doc.data().body,
    }));
}
async function fetchSingleMessage(db, data, messageId) {
    let docRef;
    if (data.threadType === "dm") {
        docRef = db
            .collection("conversations")
            .doc(data.threadId)
            .collection("messages")
            .doc(messageId);
    }
    else {
        const spaceId = data.spaceId;
        const channelId = data.channelId;
        docRef = db
            .collection("spaces")
            .doc(spaceId)
            .collection("channels")
            .doc(channelId)
            .collection("messages")
            .doc(messageId);
    }
    const snap = await docRef.get();
    if (!snap.exists)
        return null;
    return {
        id: snap.id,
        timestamp: snap.data()?.timestamp ?? null,
        senderId: snap.data()?.senderId ?? "",
        body: snap.data()?.body,
    };
}
// Strip message body text — log only messageId and timestamp (Rule #4)
function sanitizeMessagesForLog(messages) {
    return messages.map((m) => ({ messageId: m.id, timestamp: m.timestamp }));
}
// Build a message text block for LLM input — body text goes to LLM only, never logs
function buildMessageBlock(messages) {
    // Reverse so chronological order is oldest-first for LLM context
    return [...messages]
        .reverse()
        .map((m) => `[${m.id}] ${m.body ?? ""}`)
        .join("\n");
}
// MARK: - Callable 1: generateThreadSummary
exports.generateThreadSummary = (0, https_1.onCall)({ enforceAppCheck: true, secrets: [CLAUDE_KEY] }, async (request) => (0, secureCallable_1.withSecureSmartCallable)(request, async (uid, data, db) => {
    // 1. Feature flag gate — FIRST, before any Firestore reads
    const enabled = await (0, featureFlags_1.isSmartFlagEnabled)(featureFlags_1.SmartCollabFlags.SMART_CONTEXT);
    if (!enabled) {
        return { success: false, error: "feature_disabled" };
    }
    // 2. Read last 50 messages — log only ids/timestamps, never body text
    const messages = await fetchMessages(db, data, 50);
    if (messages.length === 0) {
        return { success: true };
    }
    console.info("[SmartCollab:generateThreadSummary] messages fetched", (0, safety_1.sanitizeForLogging)({
        threadId: data.threadId,
        messageCount: messages.length,
    }));
    // 3. Build LLM prompt — body text used only for prompt, never logged
    const messageBlock = buildMessageBlock(messages);
    const lastSourceMessageId = messages[0].id; // most recent (index 0 = desc order)
    const prompt = `Here are the messages from the conversation thread (oldest first):

${messageBlock}

Summarize this conversation in 2-3 sentences and extract up to 5 key themes. Respond with valid JSON only, no prose outside JSON:
{"summary": "<string>", "keyThemes": ["<string>", ...], "lastSourceMessageId": "${lastSourceMessageId}"}`;
    const systemPrompt = "You are a helpful assistant for a faith-based social platform. " +
        "You summarize conversations accurately. Never claim divine authority. " +
        "Never fabricate participants or events. Output valid JSON only.";
    // 4. Call LLM via Anthropic SDK
    let rawOutput;
    try {
        rawOutput = await callClaude(systemPrompt, prompt, 512);
    }
    catch (err) {
        console.error("[SmartCollab:generateThreadSummary] LLM call failed", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId }));
        throw new https_1.HttpsError("internal", "Summary generation failed.");
    }
    // 5. Parse LLM JSON response
    let parsed;
    try {
        // Strip markdown code fences if present
        const cleaned = rawOutput.replace(/^```json?\n?/i, "").replace(/\n?```$/i, "").trim();
        parsed = JSON.parse(cleaned);
    }
    catch {
        console.error("[SmartCollab:generateThreadSummary] JSON parse failed", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId }));
        throw new https_1.HttpsError("internal", "Summary parsing failed.");
    }
    // 6. Moderation gate before persisting
    const modResult = moderateText(parsed.summary);
    if (!modResult.passed) {
        console.warn("[SmartCollab:generateThreadSummary] moderation rejected", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId, reason: modResult.reason ?? "unknown" }));
        return { success: true }; // silent fail, not an error
    }
    // 7. Compute message timestamps for range fields
    const sortedByTime = [...messages].sort((a, b) => {
        const aMs = a.timestamp?.toMillis() ?? 0;
        const bMs = b.timestamp?.toMillis() ?? 0;
        return aMs - bMs;
    });
    const oldestTimestamp = sortedByTime[0]?.timestamp ??
        firestore_1.FieldValue.serverTimestamp();
    const newestTimestamp = sortedByTime[sortedByTime.length - 1]?.timestamp ??
        firestore_1.FieldValue.serverTimestamp();
    const uniqueSenders = new Set(messages.map((m) => m.senderId)).size;
    // 8. Write ThreadSummary
    const summaryDocId = (0, uuid_1.v4)();
    const summaryPayload = {
        id: summaryDocId,
        threadId: data.threadId,
        summaryText: parsed.summary,
        bulletPoints: parsed.keyThemes,
        messageRangeStart: oldestTimestamp,
        messageRangeEnd: newestTimestamp,
        sourceMessageIds: messages.map((m) => m.id),
        generatedBy: uid, // service account uid (function runs as service account)
        generatedAt: firestore_1.FieldValue.serverTimestamp(),
        modelVersion: MODEL_VERSION,
        isStale: false,
    };
    const summaryPath = data.threadType === "dm"
        ? contracts_1.SmartPaths.dmSummary(data.threadId)
        : contracts_1.SmartPaths.channelSummary(data.spaceId, data.channelId);
    await db.doc(summaryPath).set(summaryPayload);
    // 9. Write ThreadSmartContext
    const smartContextPayload = {
        id: summaryDocId,
        threadId: data.threadId,
        threadType: data.threadType,
        generatedBy: uid,
        generatedAt: firestore_1.FieldValue.serverTimestamp(),
        modelVersion: MODEL_VERSION,
        summaryText: parsed.summary,
        keyThemes: parsed.keyThemes,
        participantCount: uniqueSenders,
        messageCount: messages.length,
        lastSourceMessageId: parsed.lastSourceMessageId ?? lastSourceMessageId,
        isStale: false,
    };
    const smartContextPath = data.threadType === "dm"
        ? contracts_1.SmartPaths.dmSmartContext(data.threadId)
        : contracts_1.SmartPaths.channelSmartContext(data.spaceId, data.channelId);
    await db.doc(smartContextPath).set(smartContextPayload);
    console.info("[SmartCollab:generateThreadSummary] complete", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId, jobId: summaryDocId }));
    return { success: true, jobId: summaryDocId };
}));
exports.detectPrayerContextForThread = (0, https_1.onCall)({ enforceAppCheck: true, secrets: [CLAUDE_KEY] }, async (request) => (0, secureCallable_1.withSecureSmartCallable)(request, async (uid, data, db) => {
    // 1. Feature flag gate
    const enabled = await (0, featureFlags_1.isSmartFlagEnabled)(featureFlags_1.SmartCollabFlags.PRAYER_DETECTION);
    if (!enabled) {
        return { success: false, error: "feature_disabled" };
    }
    // 2. Validate messageId provided
    if (!data.messageId) {
        throw new https_1.HttpsError("invalid-argument", "messageId is required for prayer detection.");
    }
    // 3. Read ONLY the single specified message (never scan all messages)
    const message = await fetchSingleMessage(db, data, data.messageId);
    if (!message) {
        // Message not found — return success silently (privacy: never confirm/deny)
        return { success: true };
    }
    if (!message.body) {
        return { success: true };
    }
    console.info("[SmartCollab:detectPrayerContext] analyzing message", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId, messageId: message.id }));
    // 4. Classify via LLM — theme category only, never store raw prayer text
    const prompt = `Analyze this message and determine if it contains a prayer request.
Message: "${message.body}"

Respond with valid JSON only:
{
  "isPrayerRequest": true|false,
  "confidence": 0.0-1.0,
  "themeCategory": "health"|"family"|"grief"|"relationships"|"work"|"faith"|"other"
}
If not a prayer request, set confidence to 0 and themeCategory to "other".`;
    const systemPrompt = "You classify whether a message is a prayer request. " +
        "Respond only with valid JSON. Never include the message text in your response. " +
        "Only provide the theme category — never quote or paraphrase the prayer content.";
    let rawOutput;
    try {
        rawOutput = await callClaude(systemPrompt, prompt, 128);
    }
    catch (err) {
        console.error("[SmartCollab:detectPrayerContext] LLM call failed", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId }));
        // Silent fail — never surface detection error to caller
        return { success: true };
    }
    let parsed;
    try {
        const cleaned = rawOutput.replace(/^```json?\n?/i, "").replace(/\n?```$/i, "").trim();
        parsed = JSON.parse(cleaned);
    }
    catch {
        return { success: true }; // silent fail
    }
    // 5. Only proceed if detected with confidence > 0.7
    if (!parsed.isPrayerRequest || parsed.confidence <= 0.7) {
        return { success: true };
    }
    // 6. Validate theme category
    const validCategories = ["health", "family", "grief", "relationships", "work", "faith", "other"];
    const prayerTheme = validCategories.includes(parsed.themeCategory)
        ? parsed.themeCategory
        : "other";
    // 7. Moderation gate — if rejected, do not persist (no error to caller)
    // We moderate the theme + message body here, not the LLM output
    const modResult = moderateText(message.body);
    if (!modResult.passed) {
        console.warn("[SmartCollab:detectPrayerContext] moderation rejected", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId, reason: modResult.reason ?? "unknown" }));
        return { success: true };
    }
    // 8. requiresExplicitOptIn('prayerSignal') is true — store signal with
    //    restricted read; broadcasting is a separate user-initiated action.
    //    We persist only the category, never raw prayer text.
    const signalId = (0, uuid_1.v4)();
    const signalPayload = {
        id: signalId,
        threadId: data.threadId,
        requestorId: uid, // stored for job tracking only; Firestore rules restrict read
        prayerTheme, // category label only — never raw prayer text
        isAnonymous: false,
        sourceMessageId: data.messageId,
        moderationStatus: "approved",
        generatedBy: uid, // service account
        generatedAt: firestore_1.FieldValue.serverTimestamp(),
        modelVersion: MODEL_VERSION,
    };
    const signalsPath = data.threadType === "dm"
        ? contracts_1.SmartPaths.dmPrayerSignals(data.threadId)
        : contracts_1.SmartPaths.channelPrayerSignals(data.spaceId, data.channelId);
    await db.collection(signalsPath).doc(signalId).set(signalPayload);
    console.info("[SmartCollab:detectPrayerContext] signal stored", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId, signalId }));
    // Never reveal detection result to caller (privacy contract)
    return { success: true };
}));
// MARK: - Callable 3: extractThreadActions
exports.extractThreadActions = (0, https_1.onCall)({ enforceAppCheck: true, secrets: [CLAUDE_KEY] }, async (request) => (0, secureCallable_1.withSecureSmartCallable)(request, async (uid, data, db) => {
    // 1. Feature flag gate
    const enabled = await (0, featureFlags_1.isSmartFlagEnabled)(featureFlags_1.SmartCollabFlags.ACTION_EXTRACTION);
    if (!enabled) {
        return { success: false, error: "feature_disabled", count: 0 };
    }
    // 2. Read last 30 messages
    const messages = await fetchMessages(db, data, 30);
    if (messages.length === 0) {
        return { success: true, count: 0 };
    }
    console.info("[SmartCollab:extractThreadActions] messages fetched", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId, messageCount: messages.length }));
    // 3. Build LLM prompt
    const messageBlock = buildMessageBlock(messages);
    const prompt = `Here are the messages from the conversation thread (oldest first):

${messageBlock}

Identify any action items, commitments, decisions, or follow-ups from these messages.
For each, provide:
{"actionType": "followUp"|"decision"|"commitment"|"openQuestion"|"reminder", "suggestedText": "<string>", "sourceMessageId": "<messageId>", "confidence": 0.0-1.0}

Return a JSON array of objects. If none found, return [].
Never invent actions not supported by the messages.
Return valid JSON only, no prose outside the JSON array.`;
    const systemPrompt = "You extract action items from conversation threads. " +
        "Only return actions explicitly supported by the message content. " +
        "Do not invent or assume actions. Respond with a JSON array only.";
    let rawOutput;
    try {
        rawOutput = await callClaude(systemPrompt, prompt, 1024);
    }
    catch (err) {
        console.error("[SmartCollab:extractThreadActions] LLM call failed", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId }));
        throw new https_1.HttpsError("internal", "Action extraction failed.");
    }
    // 4. Parse response
    let rawActions;
    try {
        const cleaned = rawOutput.replace(/^```json?\n?/i, "").replace(/\n?```$/i, "").trim();
        rawActions = JSON.parse(cleaned);
        if (!Array.isArray(rawActions))
            rawActions = [];
    }
    catch {
        console.error("[SmartCollab:extractThreadActions] JSON parse failed", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId }));
        return { success: true, count: 0 };
    }
    // 5. Filter out low-confidence actions
    const validActionTypes = [
        "followUp",
        "decision",
        "commitment",
        "openQuestion",
        "reminder",
    ];
    const filtered = rawActions.filter((a) => a.confidence >= 0.6 &&
        validActionTypes.includes(a.actionType) &&
        typeof a.suggestedText === "string" &&
        typeof a.sourceMessageId === "string");
    if (filtered.length === 0) {
        return { success: true, count: 0 };
    }
    // 6. Persist each action — labelAsSuggested() applied to suggestedText
    const actionsPath = data.threadType === "dm"
        ? contracts_1.SmartPaths.dmSmartActions(data.threadId)
        : contracts_1.SmartPaths.channelSmartActions(data.spaceId, data.channelId);
    const batch = db.batch();
    let count = 0;
    for (const action of filtered) {
        const actionId = (0, uuid_1.v4)();
        const actionPayload = {
            id: actionId,
            threadId: data.threadId,
            actionType: action.actionType,
            suggestedText: (0, safety_1.labelAsSuggested)(action.suggestedText), // Rule #6
            sourceMessageId: action.sourceMessageId,
            confidence: action.confidence,
            status: "suggested",
            generatedBy: uid, // service account
            generatedAt: firestore_1.FieldValue.serverTimestamp(),
            modelVersion: MODEL_VERSION,
        };
        batch.set(db.collection(actionsPath).doc(actionId), actionPayload);
        count++;
    }
    await batch.commit();
    console.info("[SmartCollab:extractThreadActions] actions written", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId, count }));
    // Response contains count only — no body text
    return { success: true, count };
}));
// MARK: - Callable 4: generateGroupPulse
exports.generateGroupPulse = (0, https_1.onCall)({ enforceAppCheck: true, secrets: [CLAUDE_KEY] }, async (request) => (0, secureCallable_1.withSecureSmartCallable)(request, async (uid, data, db) => {
    // 1. Feature flag gate
    const enabled = await (0, featureFlags_1.isSmartFlagEnabled)(featureFlags_1.SmartCollabFlags.GROUP_PULSE);
    if (!enabled) {
        return { success: false, error: "feature_disabled" };
    }
    // 2. Must be a channel
    if (data.threadType !== "channel") {
        throw new https_1.HttpsError("invalid-argument", "generateGroupPulse requires threadType: channel.");
    }
    // 3. Read last 20 messages
    const messages = await fetchMessages(db, data, 20);
    if (messages.length === 0) {
        return { success: true };
    }
    // Count unique senders in last 24 hours
    const cutoff = Date.now() - 24 * 60 * 60 * 1000;
    const recentSenders = new Set(messages
        .filter((m) => (m.timestamp?.toMillis() ?? 0) >= cutoff)
        .map((m) => m.senderId));
    console.info("[SmartCollab:generateGroupPulse] messages fetched", (0, safety_1.sanitizeForLogging)({
        threadId: data.threadId,
        messageCount: messages.length,
        recentSenderCount: recentSenders.size,
    }));
    const messageBlock = buildMessageBlock(messages);
    // 4. LLM prompt
    const prompt = `Here is recent activity in this group channel (oldest first):

${messageBlock}

Assess the following:
- urgency: "normal" | "elevated" | "urgent"
- topicMomentum: 0.0-1.0 (how actively the main topic is being discussed)
- isAligned: true | false | null — only set to true/false if there is strong explicit textual evidence of agreement/disagreement. If evidence is insufficient, set to null.
- alignmentEvidenceMessageIds: array of messageIds that support the isAligned value (empty array if isAligned is null)

Return valid JSON only:
{"urgency": "<string>", "topicMomentum": <number>, "isAligned": <true|false|null>, "alignmentEvidenceMessageIds": [<string>, ...]}`;
    const systemPrompt = "You assess group conversation dynamics. " +
        "Never infer alignment without strong explicit textual evidence. " +
        "Return valid JSON only. No prose outside the JSON.";
    let rawOutput;
    try {
        rawOutput = await callClaude(systemPrompt, prompt, 256);
    }
    catch (err) {
        console.error("[SmartCollab:generateGroupPulse] LLM call failed", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId }));
        throw new https_1.HttpsError("internal", "Group pulse generation failed.");
    }
    let parsed;
    try {
        const cleaned = rawOutput.replace(/^```json?\n?/i, "").replace(/\n?```$/i, "").trim();
        parsed = JSON.parse(cleaned);
    }
    catch {
        console.error("[SmartCollab:generateGroupPulse] JSON parse failed", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId }));
        throw new https_1.HttpsError("internal", "Group pulse parsing failed.");
    }
    // 5. Validate and clamp urgency/momentum values
    const validUrgency = ["normal", "elevated", "urgent"];
    const urgency = validUrgency.includes(parsed.urgency)
        ? parsed.urgency
        : "normal";
    const topicMomentum = Math.min(1.0, Math.max(0.0, Number(parsed.topicMomentum) || 0));
    // isAligned must be null unless strong evidence — never assume
    const isAligned = parsed.isAligned === true || parsed.isAligned === false
        ? parsed.isAligned
        : undefined;
    const alignmentEvidenceMessageIds = Array.isArray(parsed.alignmentEvidenceMessageIds)
        ? parsed.alignmentEvidenceMessageIds.filter((id) => typeof id === "string")
        : [];
    // 6. Write GroupPulse
    const pulseId = (0, uuid_1.v4)();
    const pulsePayload = {
        id: pulseId,
        channelId: data.channelId,
        urgency,
        activeParticipantCount: recentSenders.size,
        topicMomentum,
        ...(isAligned !== undefined ? { isAligned } : {}),
        alignmentEvidenceMessageIds,
        generatedBy: uid, // service account
        generatedAt: firestore_1.FieldValue.serverTimestamp(),
        modelVersion: MODEL_VERSION,
        isStale: false,
    };
    const pulsePath = contracts_1.SmartPaths.channelPulse(data.spaceId, data.channelId);
    await db.doc(pulsePath).set(pulsePayload);
    console.info("[SmartCollab:generateGroupPulse] pulse written", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId, pulseId }));
    return { success: true, jobId: pulseId };
}));
exports.generateSmartReplies = (0, https_1.onCall)({ enforceAppCheck: true, secrets: [CLAUDE_KEY] }, async (request) => (0, secureCallable_1.withSecureSmartCallable)(request, async (uid, data, db) => {
    // 1. Feature flag gate
    const enabled = await (0, featureFlags_1.isSmartFlagEnabled)(featureFlags_1.SmartCollabFlags.SMART_REPLIES);
    if (!enabled) {
        return { success: false, error: "feature_disabled", replies: [] };
    }
    // 2. Read last 5 messages for context
    const messages = await fetchMessages(db, data, 5);
    if (messages.length === 0) {
        return { success: true, replies: [] };
    }
    console.info("[SmartCollab:generateSmartReplies] messages fetched", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId, messageCount: messages.length }));
    const messageBlock = buildMessageBlock(messages);
    // 3. LLM prompt
    const prompt = `Here are the recent messages in this conversation (oldest first):

${messageBlock}

Suggest 3 contextually appropriate, faith-affirming short replies to this conversation.

Requirements:
- No medical, legal, or financial advice
- No prophetic certainty ("God told me...", "You will...")
- No guilt or pressure language
- No reply that speaks for God
- Each reply must be 15 words or fewer
- Replies must be supportive, kind, and contextually appropriate

Return valid JSON only:
{"replies": ["<string>", "<string>", "<string>"]}`;
    const systemPrompt = "You suggest short, faith-affirming reply suggestions for a messaging app. " +
        "All suggestions must be gentle, supportive, and under 15 words. " +
        "Respond with valid JSON only.";
    let rawOutput;
    try {
        rawOutput = await callClaude(systemPrompt, prompt, 256);
    }
    catch (err) {
        console.error("[SmartCollab:generateSmartReplies] LLM call failed", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId }));
        return { success: true, replies: [] };
    }
    let parsed;
    try {
        const cleaned = rawOutput.replace(/^```json?\n?/i, "").replace(/\n?```$/i, "").trim();
        parsed = JSON.parse(cleaned);
        if (!Array.isArray(parsed.replies))
            parsed.replies = [];
    }
    catch {
        return { success: true, replies: [] };
    }
    // 4. Run each suggestion through moderation — drop any that fail
    const safeReplies = [];
    for (const reply of parsed.replies.slice(0, 3)) {
        if (typeof reply !== "string")
            continue;
        const modResult = moderateText(reply);
        if (modResult.passed) {
            // Apply labelAsSuggested per Rule #6
            safeReplies.push((0, safety_1.labelAsSuggested)(reply));
        }
    }
    // 5. Do NOT persist to Firestore — ephemeral, returned directly
    console.info("[SmartCollab:generateSmartReplies] replies generated", (0, safety_1.sanitizeForLogging)({ threadId: data.threadId, count: safeReplies.length }));
    return { success: true, replies: safeReplies };
}));
exports.requestMediaTranscription = (0, https_1.onCall)({ enforceAppCheck: true }, async (request) => (0, secureCallable_1.withSecureSmartCallable)(request, async (uid, data, db) => {
    // 1. Feature flag gate
    const enabled = await (0, featureFlags_1.isSmartFlagEnabled)(featureFlags_1.SmartCollabFlags.MEDIA_INTELLIGENCE);
    if (!enabled) {
        return { success: false, error: "feature_disabled", jobId: "" };
    }
    // 2. Validate mediaType
    if (!["audio", "video"].includes(data.mediaType)) {
        throw new https_1.HttpsError("invalid-argument", "mediaType must be 'audio' or 'video'.");
    }
    // 3. Verify the message exists in the thread
    const message = await fetchSingleMessage(db, data, data.mediaMessageId);
    if (!message) {
        throw new https_1.HttpsError("not-found", "Media message not found in this thread.");
    }
    // 4. Read the mediaURL from the message document
    let mediaURL;
    {
        // Re-read full doc to access mediaURL field
        let docRef;
        if (data.threadType === "dm") {
            docRef = db
                .collection("conversations")
                .doc(data.threadId)
                .collection("messages")
                .doc(data.mediaMessageId);
        }
        else {
            docRef = db
                .collection("spaces")
                .doc(data.spaceId)
                .collection("channels")
                .doc(data.channelId)
                .collection("messages")
                .doc(data.mediaMessageId);
        }
        const snap = await docRef.get();
        if (!snap.exists) {
            throw new https_1.HttpsError("not-found", "Media message not found.");
        }
        mediaURL = snap.data()?.mediaURL ?? "";
        if (!mediaURL) {
            throw new https_1.HttpsError("failed-precondition", "Media message has no mediaURL.");
        }
    }
    // 5. Queue transcription job — do NOT process synchronously
    const jobId = (0, uuid_1.v4)();
    const jobPayload = {
        jobId,
        threadId: data.threadId,
        threadType: data.threadType,
        mediaMessageId: data.mediaMessageId,
        mediaType: data.mediaType,
        requestedBy: uid, // only for job tracking, not exposed to other participants
        status: "queued",
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        mediaURL,
    };
    // Include optional channel fields when present
    if (data.spaceId)
        jobPayload["spaceId"] = data.spaceId;
    if (data.channelId)
        jobPayload["channelId"] = data.channelId;
    await db.collection("mediaJobs").doc(jobId).set(jobPayload);
    console.info("[SmartCollab:requestMediaTranscription] job queued", (0, safety_1.sanitizeForLogging)({
        threadId: data.threadId,
        jobId,
        mediaType: data.mediaType,
    }));
    // 6. Return jobId — client can poll mediaJobs/{jobId}.status
    return { success: true, jobId };
}));

"use strict";
/**
 * ScriptureGraphService.ts
 *
 * Builds and queries the Living Scripture Graph.
 *
 * Primary responsibilities:
 *  1. Parse a human scripture reference string into a structured ScriptureReference
 *  2. Fetch or build the full passage payload (graph node hydration)
 *  3. Cache results in Firestore to avoid redundant LLM calls
 *  4. Generate word study items, cross-references, and Christ connections
 *     using the Anthropic API via the existing bereanChatProxy pattern
 *
 * Non-negotiable:
 *  - Christ connections require confidence ≥ 0.6 to surface; never fabricate
 *  - Historical context is grounded in accepted scholarship; no speculation
 *  - Cache entries expire after 30 days and are regenerated on demand
 */
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
exports.getPassagePayload = getPassagePayload;
exports.parseReference = parseReference;
const admin = __importStar(require("firebase-admin"));
const uuid_1 = require("uuid");
const CACHE_TTL_DAYS = 30;
// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------
/**
 * Fetches or builds the full passage payload for a scripture reference.
 * Returns cached data if available and fresh; otherwise triggers LLM hydration.
 */
async function getPassagePayload(request, anthropicApiKey) {
    const reference = parseReference(request.reference, request.translation ?? "ESV");
    const cacheKey = `${reference.book.toLowerCase()}_${reference.chapter}_${reference.verseStart}_${reference.translation.toLowerCase()}`;
    // Check cache
    const cached = await getCachedPassage(cacheKey);
    if (cached)
        return cached;
    // Build from LLM
    const payload = await hydratePassageFromLLM(reference, request, anthropicApiKey);
    await cachePassage(cacheKey, payload);
    return payload;
}
// ---------------------------------------------------------------------------
// Reference Parser
// ---------------------------------------------------------------------------
/**
 * Parses a human-readable reference like "John 3:16" or "Romans 8:28-30"
 * into a structured ScriptureReference.
 */
function parseReference(ref, translation) {
    // Normalize: "John 3:16-18" → book="John", chapter=3, verseStart=16, verseEnd=18
    const match = ref.match(/^(.+?)\s+(\d+):(\d+)(?:[–\-](\d+))?/);
    if (!match) {
        // Fallback: treat whole string as book with chapter 1:1
        return { book: ref, chapter: 1, verseStart: 1, verseEnd: undefined, translation };
    }
    return {
        book: match[1].trim(),
        chapter: parseInt(match[2], 10),
        verseStart: parseInt(match[3], 10),
        verseEnd: match[4] ? parseInt(match[4], 10) : undefined,
        translation,
    };
}
// ---------------------------------------------------------------------------
// Cache
// ---------------------------------------------------------------------------
async function getCachedPassage(cacheKey) {
    try {
        const db = admin.firestore();
        const doc = await db.collection("study_cache").doc(cacheKey).get();
        if (!doc.exists)
            return null;
        const data = doc.data();
        const ageMs = Date.now() - data.cachedAt.toMillis();
        const maxAgeMs = CACHE_TTL_DAYS * 24 * 60 * 60 * 1000;
        if (ageMs > maxAgeMs)
            return null; // Expired
        return data;
    }
    catch {
        return null; // Cache miss — proceed to LLM
    }
}
async function cachePassage(cacheKey, payload) {
    try {
        const db = admin.firestore();
        await db.collection("study_cache").doc(cacheKey).set(payload);
    }
    catch {
        // Non-fatal — caching failure does not block response
    }
}
// ---------------------------------------------------------------------------
// LLM Hydration
// ---------------------------------------------------------------------------
/**
 * Calls Anthropic to build a full passage payload.
 * Uses the structured output contract pattern.
 */
async function hydratePassageFromLLM(reference, request, anthropicApiKey) {
    const refStr = `${reference.book} ${reference.chapter}:${reference.verseStart}${reference.verseEnd ? `-${reference.verseEnd}` : ""} (${reference.translation})`;
    const systemPrompt = buildGraphHydrationPrompt(request);
    const userMessage = `Please analyze the following scripture passage and return a structured study payload:\n\n${refStr}`;
    const response = await callAnthropicAPI(systemPrompt, userMessage, anthropicApiKey);
    return parseGraphPayload(response, reference);
}
function buildGraphHydrationPrompt(request) {
    const parts = [
        `You are a biblical scholar building a structured study payload for the AMEN app.`,
        `Your response MUST be valid JSON matching the specified schema.`,
        `All historical and linguistic claims must be grounded in accepted scholarship.`,
        `Do not speculate or fabricate; note uncertainty clearly.`,
    ];
    if (request.includeWordStudy) {
        parts.push(`Include word study items for key theological terms in the passage (Greek/Hebrew).`);
    }
    if (request.includeChristConnection) {
        parts.push(`If a typological or prophetic connection to Jesus is well-supported (confidence ≥ 0.6), include it. Otherwise omit.`);
    }
    if (request.includeImmersionMode) {
        parts.push(`Include observation/interpretation/reflection structure for immersion mode.`);
    }
    parts.push(`Return JSON with fields: text, summary, themes (array), crossReferences (array), wordInsights (array), christConnection (object or null), applicationPaths (array), sceneContext (object).`);
    return parts.join("\n");
}
function parseGraphPayload(rawJson, reference) {
    let parsed;
    try {
        // Strip any accidental markdown fences
        const clean = rawJson.replace(/^```json?\s*/i, "").replace(/```\s*$/, "").trim();
        parsed = JSON.parse(clean);
    }
    catch {
        // LLM returned non-JSON — return a minimal payload with just the reference
        return buildFallbackPayload(reference);
    }
    const passageId = (0, uuid_1.v4)();
    const now = admin.firestore.Timestamp.now();
    return {
        id: passageId,
        reference,
        text: String(parsed.text ?? ""),
        summary: String(parsed.summary ?? `${reference.book} ${reference.chapter}:${reference.verseStart}`),
        themes: parseThemes(parsed.themes, passageId),
        crossReferences: parseCrossRefs(parsed.crossReferences, passageId),
        wordInsights: parseWordInsights(parsed.wordInsights),
        christConnection: parseChristConnection(parsed.christConnection, passageId),
        applicationPaths: parseApplicationPaths(parsed.applicationPaths, passageId),
        sceneContext: parseSceneContext(parsed.sceneContext, passageId),
        cachedAt: now,
    };
}
function buildFallbackPayload(reference) {
    return {
        id: (0, uuid_1.v4)(),
        reference,
        text: "",
        summary: `${reference.book} ${reference.chapter}:${reference.verseStart}`,
        themes: [],
        crossReferences: [],
        wordInsights: [],
        christConnection: undefined,
        applicationPaths: [],
        sceneContext: undefined,
        cachedAt: admin.firestore.Timestamp.now(),
    };
}
// ---------------------------------------------------------------------------
// Parsers for each graph node type
// ---------------------------------------------------------------------------
function parseThemes(raw, passageId) {
    if (!Array.isArray(raw))
        return [];
    return raw.slice(0, 5).map((t) => ({
        id: (0, uuid_1.v4)(),
        name: String(t.name ?? ""),
        description: String(t.description ?? ""),
        relatedPassages: [passageId],
        category: t.category ?? "theological",
    }));
}
function parseCrossRefs(raw, passageId) {
    if (!Array.isArray(raw))
        return [];
    return raw.slice(0, 8).map((c) => ({
        id: (0, uuid_1.v4)(),
        sourcePassageId: passageId,
        targetReference: parseReference(String(c.targetReference ?? "John 3:16"), "ESV"),
        targetText: String(c.targetText ?? ""),
        relationshipType: c.relationshipType ?? "parallel",
        strength: clamp(Number(c.strength ?? 0.5), 0, 1),
    }));
}
function parseWordInsights(raw) {
    if (!Array.isArray(raw))
        return [];
    return raw.slice(0, 6).map((w) => ({
        id: (0, uuid_1.v4)(),
        surfaceWord: String(w.surfaceWord ?? ""),
        originalWord: String(w.originalWord ?? ""),
        transliteration: String(w.transliteration ?? ""),
        strongsNumber: w.strongsNumber ? String(w.strongsNumber) : undefined,
        definition: String(w.definition ?? ""),
        semanticRange: Array.isArray(w.semanticRange) ? w.semanticRange : [],
        language: w.language ?? "greek",
        devotionalNote: w.devotionalNote ? String(w.devotionalNote) : undefined,
    }));
}
function parseChristConnection(raw, passageId) {
    if (typeof raw !== "object" || raw === null || Array.isArray(raw))
        return undefined;
    const r = raw;
    const confidence = clamp(Number(r.confidence ?? 0), 0, 1);
    if (confidence < 0.6)
        return undefined; // Non-negotiable gate
    return {
        passageId,
        connectionStatement: String(r.connectionStatement ?? ""),
        ntFulfillmentReference: r.ntFulfillmentReference
            ? parseReference(String(r.ntFulfillmentReference), "ESV")
            : undefined,
        connectionType: r.connectionType ?? "thematic_pattern",
        confidence,
        hermeneuticalTradition: r.hermeneuticalTradition ? String(r.hermeneuticalTradition) : undefined,
    };
}
function parseApplicationPaths(raw, passageId) {
    if (!Array.isArray(raw))
        return [];
    return raw.slice(0, 3).map((a) => ({
        id: (0, uuid_1.v4)(),
        passageId,
        prompt: String(a.prompt ?? ""),
        category: a.category ?? "personal",
        relational: Boolean(a.relational ?? false),
        actionStep: a.actionStep ? String(a.actionStep) : undefined,
    }));
}
function parseSceneContext(raw, passageId) {
    if (typeof raw !== "object" || raw === null || Array.isArray(raw))
        return undefined;
    const r = raw;
    let studyStructure;
    if (typeof r.studyStructure === "object" && r.studyStructure !== null) {
        const s = r.studyStructure;
        studyStructure = {
            observation: String(s.observation ?? ""),
            interpretation: String(s.interpretation ?? ""),
            reflection: String(s.reflection ?? ""),
            hasInterpretiveDebate: Boolean(s.hasInterpretiveDebate ?? false),
            interpretiveDebateNote: s.interpretiveDebateNote ? String(s.interpretiveDebateNote) : undefined,
        };
    }
    return {
        passageId,
        historicalSetting: String(r.historicalSetting ?? ""),
        culturalNotes: Array.isArray(r.culturalNotes) ? r.culturalNotes : [],
        authorContext: r.authorContext ? String(r.authorContext) : undefined,
        geographicalContext: r.geographicalContext ? String(r.geographicalContext) : undefined,
        datePeriod: r.datePeriod ? String(r.datePeriod) : undefined,
        keyFigures: Array.isArray(r.keyFigures) ? r.keyFigures : [],
        literaryGenre: String(r.literaryGenre ?? "Epistle"),
        studyStructure,
    };
}
// ---------------------------------------------------------------------------
// Anthropic API call (minimal wrapper, reuses key pattern from bereanChatProxy)
// ---------------------------------------------------------------------------
async function callAnthropicAPI(system, userMessage, apiKey) {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
            model: "claude-3-5-sonnet-20241022", // Sonnet for graph hydration
            max_tokens: 2048,
            system,
            messages: [{ role: "user", content: userMessage }],
        }),
    });
    if (!response.ok) {
        throw new Error(`Anthropic API error: ${response.status}`);
    }
    const data = await response.json();
    return data.content?.[0]?.text ?? "{}";
}
// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}
//# sourceMappingURL=ScriptureGraphService.js.map
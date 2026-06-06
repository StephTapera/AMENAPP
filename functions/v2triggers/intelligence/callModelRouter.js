/**
 * functions/intelligence/callModelRouter.js
 *
 * AMEN Living Intelligence — Provider-Abstracted Model Router
 *
 * Export:
 *   callModel({ task, input, context, userId, safetyLevel })
 *
 * Tasks:
 *   intelligence.summarize      → Berean/Claude. Fail-closed (null on error).
 *   intelligence.classify_need  → Anthropic SDK need classification.
 *   intelligence.match          → Event + prayer matching.
 *   intelligence.world_response → GLOBAL card contested/known factual breakdown.
 *
 * Principles:
 *   - Never fabricate content. Return null on any failure.
 *   - All outputs pass through moderation (fail-closed: null if moderation fails).
 *   - Never hardcode providers — routing is determined by task name.
 *   - Secrets loaded from Secret Manager via defineSecret().
 */

"use strict";

const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

// ─── Secrets ──────────────────────────────────────────────────────────────────
const BEREAN_LLM_KEY    = defineSecret('BEREAN_LLM_KEY');
const ANTHROPIC_API_KEY = defineSecret('ANTHROPIC_API_KEY');

// ─── Constants ────────────────────────────────────────────────────────────────

const BEREAN_API_URL   = 'https://api.berean.ai/v1/chat/completions';
const ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages';
const CLAUDE_MODEL     = 'claude-3-5-sonnet-20241022';

// Moderation: inline (not gateway callable) — gateway is for client-facing checks
// We run a lightweight phrase check here server-side
const CONTENT_BLOCKLIST = [
  'kill', 'suicide', 'self harm', 'csam', 'trafficking',
];

function containsBlocklisted(text) {
  if (!text || typeof text !== 'string') return false;
  const lower = text.toLowerCase();
  return CONTENT_BLOCKLIST.some((phrase) => lower.includes(phrase));
}

// ─── Shared fetch helper ──────────────────────────────────────────────────────

async function fetchJson(url, options) {
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(url, options);
  if (!response.ok) {
    const body = await response.text().catch(() => '(no body)');
    throw new Error(`HTTP ${response.status}: ${body.slice(0, 300)}`);
  }
  return response.json();
}

// ─── Moderation pass ─────────────────────────────────────────────────────────

/**
 * runModerationPass — checks output text before returning to caller.
 * Fail-closed: any failure → return null.
 *
 * @param {string|object} output
 * @returns {string|object|null}
 */
function runModerationPass(output) {
  try {
    const text = typeof output === 'string' ? output : JSON.stringify(output);
    if (containsBlocklisted(text)) {
      console.warn('[callModelRouter] moderation: output blocked by blocklist');
      return null;
    }
    return output;
  } catch (err) {
    console.error('[callModelRouter] moderation pass error — failing closed:', err.message);
    return null;
  }
}

// ─── Bible verse helper ───────────────────────────────────────────────────────

/**
 * lookupBibleVerses — fetch verse text from Firestore bibleVerses collection.
 * Used to ground Berean summaries in real citations.
 *
 * @param {string[]} references  e.g. ['John_3_16', 'Romans_8_28']
 * @returns {Promise<{ reference: string, text: string }[]>}
 */
async function lookupBibleVerses(references) {
  if (!Array.isArray(references) || references.length === 0) return [];

  try {
    const db = admin.firestore();
    const results = await Promise.all(
      references.slice(0, 5).map(async (ref) => {
        const snap = await db.collection('bibleVerses').doc(ref).get();
        if (!snap.exists) return null;
        const data = snap.data();
        return { reference: ref, text: data.text || data.verse || '' };
      }),
    );
    return results.filter(Boolean);
  } catch (err) {
    console.error('[callModelRouter] Bible verse lookup error:', err.message);
    return [];
  }
}

// ─── Task handlers ────────────────────────────────────────────────────────────

/**
 * handleSummarize — generate a 1-3 bullet Berean summary for an IntelligenceCard.
 * Uses BEREAN_LLM_KEY. Falls back to Anthropic if Berean unavailable.
 * Returns null on any error (fail-closed).
 *
 * @param {object} input    { title, backingEntityKind, rawContent, scriptureRefs }
 * @param {object} context  { userId, churchIds }
 * @returns {Promise<string[]|null>}  Array of bullet strings (max 3) or null
 */
async function handleSummarize(input, context) {
  const { title, rawContent, scriptureRefs } = input || {};

  // Fetch real scripture context if refs provided
  const verses = await lookupBibleVerses(scriptureRefs || []);
  const scriptureContext = verses.length > 0
    ? verses.map((v) => `${v.reference}: ${v.text}`).join('\n')
    : '';

  const systemPrompt = [
    'You are the Berean AI, a theologically grounded assistant for the AMEN Christian community.',
    'Your task: produce 1-3 concise bullet-point summary lines for an intelligence card.',
    'Rules:',
    '- Only use real, verifiable information. Never fabricate facts or quotes.',
    '- If scripture is provided, only cite those exact references.',
    '- Keep each bullet under 80 characters.',
    '- Do not use spectacle language (avoid "incredible", "amazing", "shocking").',
    '- Format: return a JSON array of strings, e.g. ["Bullet 1", "Bullet 2"].',
  ].join('\n');

  const userPrompt = [
    `Title: ${title || '(untitled)'}`,
    rawContent ? `\nContent: ${rawContent.slice(0, 1000)}` : '',
    scriptureContext ? `\nScripture context:\n${scriptureContext}` : '',
    '\nReturn a JSON array of 1-3 summary bullet strings.',
  ].join('');

  // Try Berean first
  try {
    const bereanKey = BEREAN_LLM_KEY.value();
    const data = await fetchJson(BEREAN_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${bereanKey}`,
      },
      body: JSON.stringify({
        model: 'berean-1',
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt },
        ],
        max_tokens: 256,
        temperature: 0.3,
      }),
    });

    const raw = data?.choices?.[0]?.message?.content ?? '';
    const bullets = JSON.parse(raw.trim());
    if (Array.isArray(bullets) && bullets.length > 0 && bullets.length <= 3) {
      return runModerationPass(bullets);
    }
    throw new Error('Invalid Berean response shape');
  } catch (bereanErr) {
    console.warn('[callModelRouter] Berean summarize failed, trying Anthropic:', bereanErr.message);
  }

  // Fallback to Anthropic (Claude)
  try {
    const anthropicKey = ANTHROPIC_API_KEY.value();
    const data = await fetchJson(ANTHROPIC_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': anthropicKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: CLAUDE_MODEL,
        system: systemPrompt,
        messages: [{ role: 'user', content: userPrompt }],
        max_tokens: 256,
      }),
    });

    const raw = data?.content?.[0]?.text ?? '';
    // Find the JSON array in the response
    const match = raw.match(/\[[\s\S]*?\]/);
    if (!match) throw new Error('No JSON array in Claude response');
    const bullets = JSON.parse(match[0]);
    if (Array.isArray(bullets) && bullets.length > 0 && bullets.length <= 3) {
      return runModerationPass(bullets);
    }
    throw new Error('Invalid Claude response shape');
  } catch (err) {
    console.error('[callModelRouter] Both Berean and Anthropic summarize failed — returning null:', err.message);
    return null;
  }
}

/**
 * handleClassifyNeed — detect and classify a need from free text.
 * Returns { needType, confidence, urgency } or null on error.
 *
 * @param {object} input    { text, contentType }
 * @param {object} context  { userId }
 * @returns {Promise<{ needType: string, confidence: number, urgency: string }|null>}
 */
async function handleClassifyNeed(input, context) {
  const { text } = input || {};
  if (!text || typeof text !== 'string' || text.trim().length < 5) return null;

  const systemPrompt = [
    'You are a community needs classifier for the AMEN Christian app.',
    'Classify the given text into one need type from:',
    '  VOLUNTEER, DONATION, PRAYER, EMOTIONAL_SUPPORT, PRACTICAL_HELP, INFORMATION, NONE',
    'Also estimate confidence (0.0-1.0) and urgency: LOW, MEDIUM, HIGH, CRITICAL.',
    'Return JSON: { "needType": "...", "confidence": 0.0, "urgency": "..." }',
    'If no need is detected, return { "needType": "NONE", "confidence": 1.0, "urgency": "LOW" }.',
  ].join('\n');

  try {
    const anthropicKey = ANTHROPIC_API_KEY.value();
    const data = await fetchJson(ANTHROPIC_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': anthropicKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: CLAUDE_MODEL,
        system: systemPrompt,
        messages: [{ role: 'user', content: text.slice(0, 2000) }],
        max_tokens: 128,
      }),
    });

    const raw = data?.content?.[0]?.text ?? '';
    const match = raw.match(/\{[\s\S]*?\}/);
    if (!match) throw new Error('No JSON object in response');
    const result = JSON.parse(match[0]);

    if (!result.needType) throw new Error('Missing needType in response');
    return runModerationPass(result);
  } catch (err) {
    console.error('[callModelRouter] classify_need failed — returning null:', err.message);
    return null;
  }
}

/**
 * handleMatch — score how well an event/prayer matches a user context.
 * Returns { matchScore: number, matchReasons: string[] } or null on error.
 *
 * @param {object} input    { entityKind, entityData, userProfile }
 * @param {object} context  { userId, seasonOfLife, liturgicalSeason, churchIds }
 * @returns {Promise<{ matchScore: number, matchReasons: string[] }|null>}
 */
async function handleMatch(input, context) {
  const { entityKind, entityData, userProfile } = input || {};
  if (!entityKind || !entityData) return null;

  const systemPrompt = [
    'You are a faith community matching engine for the AMEN Christian app.',
    'Given a user profile and an entity (event/prayer/opportunity), score how relevant it is.',
    'Return JSON: { "matchScore": 0-100, "matchReasons": ["reason1", "reason2"] }',
    'Be specific and human-readable in matchReasons.',
    'Never fabricate facts. If you cannot determine relevance, return matchScore: 0.',
  ].join('\n');

  const userPrompt = [
    `Entity kind: ${entityKind}`,
    `Entity data: ${JSON.stringify(entityData).slice(0, 800)}`,
    `User profile: ${JSON.stringify(userProfile || {}).slice(0, 400)}`,
    `Context: ${JSON.stringify({ seasonOfLife: context?.seasonOfLife, liturgicalSeason: context?.liturgicalSeason })}`,
  ].join('\n');

  try {
    const anthropicKey = ANTHROPIC_API_KEY.value();
    const data = await fetchJson(ANTHROPIC_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': anthropicKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: CLAUDE_MODEL,
        system: systemPrompt,
        messages: [{ role: 'user', content: userPrompt }],
        max_tokens: 256,
      }),
    });

    const raw = data?.content?.[0]?.text ?? '';
    const match = raw.match(/\{[\s\S]*?\}/);
    if (!match) throw new Error('No JSON in response');
    const result = JSON.parse(match[0]);

    if (typeof result.matchScore !== 'number' || !Array.isArray(result.matchReasons)) {
      throw new Error('Invalid match response shape');
    }
    return runModerationPass(result);
  } catch (err) {
    console.error('[callModelRouter] match failed — returning null:', err.message);
    return null;
  }
}

/**
 * handleWorldResponse — produce a factual breakdown for a GLOBAL tier card.
 * Returns { known: string[], contested: string[], howToRespond: string[] } or null.
 * If source is unverifiable, returns null (fail-closed).
 *
 * @param {object} input    { title, source, rawContent }
 * @param {object} context  { userId }
 * @returns {Promise<{ known: string[], contested: string[], howToRespond: string[] }|null>}
 */
async function handleWorldResponse(input, context) {
  const { title, source, rawContent } = input || {};

  // Fail-closed if source is missing or empty
  if (!source || typeof source !== 'string' || source.trim() === '') {
    console.warn('[callModelRouter] world_response: no source provided — failing closed');
    return null;
  }

  const systemPrompt = [
    'You are a Christian world-response assistant for the AMEN app.',
    'Given a global news item, separate what is factually known from what is contested.',
    'Then suggest how a faithful Christian community might respond.',
    'Return JSON:',
    '{',
    '  "known": ["fact1", "fact2"],',
    '  "contested": ["disputed claim 1", "disputed claim 2"],',
    '  "howToRespond": ["prayer point", "practical step", "community action"]',
    '}',
    'Rules:',
    '- Only include things you are highly confident are factual in "known".',
    '- Never fabricate. If uncertain, put in "contested".',
    '- "howToRespond" should be faith-oriented and actionable.',
    '- Return null if you cannot produce a responsible response.',
  ].join('\n');

  const userPrompt = [
    `Title: ${title || '(untitled)'}`,
    `Source: ${source}`,
    rawContent ? `\nContent: ${rawContent.slice(0, 1000)}` : '',
  ].join('\n');

  try {
    const anthropicKey = ANTHROPIC_API_KEY.value();
    const data = await fetchJson(ANTHROPIC_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': anthropicKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: CLAUDE_MODEL,
        system: systemPrompt,
        messages: [{ role: 'user', content: userPrompt }],
        max_tokens: 512,
      }),
    });

    const raw = data?.content?.[0]?.text ?? '';
    if (/null/i.test(raw.trim()) && raw.trim().length < 10) {
      console.warn('[callModelRouter] world_response: model returned null');
      return null;
    }

    const match = raw.match(/\{[\s\S]*?\}/);
    if (!match) throw new Error('No JSON in response');
    const result = JSON.parse(match[0]);

    if (!Array.isArray(result.known) || !Array.isArray(result.contested) || !Array.isArray(result.howToRespond)) {
      throw new Error('Invalid world_response shape');
    }

    return runModerationPass(result);
  } catch (err) {
    console.error('[callModelRouter] world_response failed — returning null:', err.message);
    return null;
  }
}

// ─── Main router ──────────────────────────────────────────────────────────────

/**
 * callModel — route a task to the appropriate AI provider.
 *
 * @param {object} opts
 * @param {string} opts.task         Task identifier (e.g. 'intelligence.summarize')
 * @param {object} opts.input        Task-specific input data
 * @param {object} opts.context      User/session context
 * @param {string} opts.userId       User ID (for logging)
 * @param {string} opts.safetyLevel  'strict' | 'standard' (default: 'strict')
 * @returns {Promise<any|null>}      Task output or null on any failure
 */
async function callModel({ task, input, context, userId, safetyLevel = 'strict' }) {
  if (!task) {
    console.error('[callModelRouter] task is required');
    return null;
  }

  console.log(`[callModelRouter] task=${task} userId=${userId || 'anon'}`);

  try {
    let result;

    switch (task) {
      case 'intelligence.summarize':
        result = await handleSummarize(input, context);
        break;

      case 'intelligence.classify_need':
        result = await handleClassifyNeed(input, context);
        break;

      case 'intelligence.match':
        result = await handleMatch(input, context);
        break;

      case 'intelligence.world_response':
        result = await handleWorldResponse(input, context);
        break;

      default:
        console.warn(`[callModelRouter] Unknown task: ${task}`);
        return null;
    }

    if (result === null || result === undefined) {
      console.warn(`[callModelRouter] task=${task} returned null`);
      return null;
    }

    return result;
  } catch (err) {
    // Top-level catch — always fail closed
    console.error(`[callModelRouter] Unhandled error for task=${task}:`, err.message);
    return null;
  }
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = { callModel };

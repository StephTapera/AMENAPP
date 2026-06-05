/**
 * commentGateway.js
 *
 * Smart Comment Quality + Safety Gateway (checkCommentQuality)
 *
 * ARCHITECTURE:
 *   Before any comment writes to the database, iOS calls this callable.
 *   This function runs:
 *     1. Auth + input validation
 *     2. Rate limit (60 checks per user per hour)
 *     3. Keyword safety fast-check
 *     4. NVIDIA llama-3.1-70b sentiment/context analysis
 *     5. Quality heuristics (did-you-read, tone, scripture nudge, personal, distress)
 *     6. Returns { action, nudgeType?, nudgeMessage?, reason? } — never writes content itself
 *
 * ACTION CONTRACT:
 *   action:       "publish" | "nudge" | "block"
 *   nudgeType:    "read_first" | "sounds_harsh" | "add_scripture" |
 *                 "move_private" | "ask_mentor"  (present when action === "nudge")
 *   nudgeMessage: human-readable explanation (present when action === "nudge")
 *   reason:       present when action === "block"
 *
 *   "nudge"  = show prompts; user MAY dismiss and post anyway (suggestions, not blocks)
 *   "block"  = hard safety violation from keyword gate or moderation pipeline
 *
 * FALLBACK RULE:
 *   If NVIDIA AI is unavailable, return { action: "publish" } — never block due to
 *   AI being down. Keyword safety gate still runs regardless.
 *
 * HARD RULES ENFORCED HERE:
 *   - Auth check first, every time.
 *   - NVIDIA_API_KEY via Secret Manager only (defineSecret).
 *   - Every path: auth check + input validation + rate limit.
 *   - AI outputs are read-only decision data — never auto-posted.
 *
 * RECORD CONTRACT:
 *   Every call writes a lightweight decision record to
 *   Firestore: commentModerationDecisions/{uid}_{clientCommentId}
 */

'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const db = admin.firestore();

const REGION = 'us-central1';

// ─── NVIDIA Secret ─────────────────────────────────────────────────────────────
const NVIDIA_API_KEY = defineSecret('NVIDIA_API_KEY');

const NVIDIA_NIM_URL   = 'https://integrate.api.nvidia.com/v1/chat/completions';
const NVIDIA_LLM_MODEL = 'meta/llama-3.1-70b-instruct';

// Shared decision persistence from moderationGateway — mirrors the canonical
// moderationDecisions/ write for comments so every content surface is covered.
function getGateway() { return require('./moderationGateway'); }

// ─── Rate-limit helper ────────────────────────────────────────────────────────
// 60 checks per user per rolling hour
const COMMENT_CHECK_LIMIT   = 60;
const COMMENT_WINDOW_MS     = 60 * 60 * 1000; // 1 hour

async function isCommentCheckRateLimited(uid) {
  const now = Date.now();
  const windowStart = now - COMMENT_WINDOW_MS;
  const ref = db.collection('rateLimitCounters').doc(`${uid}_commentCheck`);

  return db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const data = doc.exists ? doc.data() : { timestamps: [] };
    const recent = (data.timestamps || []).filter((ts) => ts > windowStart);

    if (recent.length >= COMMENT_CHECK_LIMIT) return true;

    recent.push(now);
    tx.set(ref, { timestamps: recent }, { merge: true });
    return false;
  });
}

// ─── Keyword-based safety check (fast, synchronous) ──────────────────────────
// Reuses the same normalization and lexicon philosophy as aiModeration.js,
// but kept local to avoid a cross-module circular import.

const BLOCKED_PATTERNS = [
  /\b(kill yourself|kys|go hang yourself|end your life)\b/i,
  /\b(n[i1]gg[ae]r|sp[i1]c|ch[i1]nk|k[i1]ke|f[a4]gg[o0]t|tr[a4]nny)\b/i,
  /\b(suicide|want to die|end it all|kill myself|no reason to live)\b/i,
  /\b(rape you|i will kill|i will hurt|going to hurt|shoot you|stab you)\b/i,
  /\b(porn|porno|onlyfans|send nudes|send pics|naked pics)\b/i,
  /\b(white supremacy|heil|racial holy war|death to all|kkk)\b/i,
];

const WARN_PATTERNS = [
  /\b(stupid|idiot|loser|worthless|pathetic|trash|moron|dumbass)\b/i,
  /\b(damn|hell).{0,20}you\b/i,
  /\b(shut up|go away|nobody cares|no one cares)\b/i,
];

function runKeywordSafety(text) {
  for (const pattern of BLOCKED_PATTERNS) {
    if (pattern.test(text)) return 'block';
  }
  for (const pattern of WARN_PATTERNS) {
    if (pattern.test(text)) return 'warn';
  }
  return 'allow';
}

// ─── Quality heuristics ────────────────────────────────────────────────────────
// Each heuristic returns a nudge string or null.

/**
 * Tone heuristic: very short, all-caps, or exclamation-heavy comments
 * may come across as harsh or reactive.
 */
function checkTone(text) {
  const trimmed = text.trim();
  const allCaps = trimmed === trimmed.toUpperCase() && /[A-Z]{4,}/.test(trimmed);
  const veryShort = trimmed.length < 8 && /[!?]/.test(trimmed);
  const excessiveExclamation = (trimmed.match(/!/g) || []).length >= 4;

  if (allCaps || veryShort || excessiveExclamation) {
    return 'This may sound harsh — want to rewrite before posting?';
  }
  return null;
}

/**
 * Scripture / context heuristic: critical or corrective-sounding comments
 * without any scriptural grounding could benefit from added context.
 */
function checkScriptureContext(text) {
  const lc = text.toLowerCase();
  const hasCorrectiveTone =
    /\b(wrong|incorrect|you need|should|must|have to|don't|never)\b/.test(lc);
  const hasScripture =
    /\b(verse|scripture|bible|word of god|proverbs|psalms|matthew|john|romans|genesis|[0-9]:[0-9])\b/.test(lc);

  if (hasCorrectiveTone && !hasScripture && text.length > 30) {
    return 'Consider adding a Scripture reference or context to support your thought.';
  }
  return null;
}

/**
 * "Did you engage with this content?" heuristic.
 * Very fast, dismissive single-word or meme-like reactions on spiritual posts
 * may benefit from a reflection prompt.
 */
function checkEngagement(text) {
  const DISMISSIVE_PATTERNS = [
    /^(lol|lmao|haha|cap|nah|idk|ok|okay|k|🙄|🥱|😂)+[.!?]*$/i,
    /^(mid|trash|lame|boring|cringe|cope|ratio)\s*[.!?]*$/i,
  ];
  for (const p of DISMISSIVE_PATTERNS) {
    if (p.test(text.trim())) {
      return 'Did you read or watch this fully? A more thoughtful reply builds community.';
    }
  }
  return null;
}

/**
 * Private matter heuristic: comments containing very personal disclosures
 * might be better handled in a private message or mentor conversation.
 */
function checkPrivacyFit(text) {
  const lc = text.toLowerCase();
  const PERSONAL_SIGNALS = [
    'i was abused', 'i am suicidal', 'i self harm', 'i cut myself',
    'my marriage is', 'my divorce', 'i was assaulted', 'i have been cheating',
  ];
  for (const sig of PERSONAL_SIGNALS) {
    if (lc.includes(sig)) {
      return 'This sounds very personal — consider moving this to a private message or asking a mentor instead.';
    }
  }
  return null;
}

/**
 * Length nudge: very long comments (essay-length) may belong in a new post.
 */
function checkLength(text) {
  if (text.trim().length > 800) {
    return 'This is quite long for a comment — consider posting it as its own post instead.';
  }
  return null;
}

/**
 * Collect all active nudges for the given text.
 * Returns an array of non-null nudge strings (up to 5).
 */
function collectNudges(text) {
  const nudges = [
    checkTone(text),
    checkScriptureContext(text),
    checkEngagement(text),
    checkPrivacyFit(text),
    checkLength(text),
  ].filter(Boolean);

  // Cap at 3 nudges per check — avoid overwhelming the user.
  return nudges.slice(0, 3);
}

// ─── Decision record writer ────────────────────────────────────────────────────
async function writeDecisionRecord(uid, clientCommentId, decision, safetyDecision, nudges) {
  // Best-effort — never let a Firestore write failure block the response.
  try {
    const docId = `${uid}_${clientCommentId || admin.firestore().collection('_').doc().id}`;

    // 1. Legacy commentModerationDecisions (existing; keep for backward compat)
    await db.collection('commentModerationDecisions').doc(docId).set({
      uid,
      clientCommentId: clientCommentId || null,
      decision,
      safetyDecision,
      nudgeCount: nudges.length,
      checkedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. Canonical moderationDecisions/ (hard rule: every surface must write here)
    const canonicalDecision = decision === 'publish' ? 'allow'
                            : decision === 'nudge'   ? 'warn'
                            : 'block';
    const { persistDecision } = getGateway();
    await persistDecision({
      uid,
      contentType: 'comment',
      contextId: clientCommentId || null,
      decision: canonicalDecision,
      reason: nudges.length ? nudges[0] : null,
      detectedCategories: safetyDecision !== 'allow' ? [safetyDecision] : [],
      crisisEscalated: false,
      contentLength: 0,
      source: 'commentGateway',
    });
  } catch (err) {
    console.error('[commentGateway] Failed to write decision record:', err.message);
  }
}

// ─── NVIDIA llama-3.1-70b sentiment/context analysis ──────────────────────────
/**
 * Calls NVIDIA llama-3.1-70b-instruct to classify the comment's intent and tone.
 * Returns one nudgeType from the spec set, or null if the comment looks fine.
 * Fails open: any error → return null (never block due to AI being down).
 *
 * Nudge types (spec):
 *   read_first    — reactionary (short/intense, no reference to content)
 *   sounds_harsh  — harsh or confrontational sentiment
 *   add_scripture — scripture-based post context but no reference in comment
 *   move_private  — addresses a specific person / personal disclosure
 *   ask_mentor    — spiritual confusion or emotional distress
 */
async function classifyWithNVIDIA(commentText, postContext, apiKey) {
  const systemPrompt = `You are a comment quality classifier for a Christian social media app called AMEN.
Analyze the comment and classify it into EXACTLY ONE category, or "none" if it seems fine.

Categories:
- read_first: Comment seems reactionary — very short, intense emotion, no reference to the post's content
- sounds_harsh: Comment is harsh, confrontational, dismissive, or uses attacking language
- add_scripture: The post context is scripture-based but this comment has no biblical reference at all
- move_private: Comment addresses a specific individual personally, or contains very personal disclosure
- ask_mentor: Comment expresses spiritual confusion, theological distress, or emotional crisis
- none: Comment seems thoughtful and appropriate

Return a JSON object ONLY: {"nudgeType": "<category>", "reason": "<brief explanation>"}
No other text.`;

  const userPrompt = `Comment: "${commentText.slice(0, 500)}"
${postContext ? `Post context: "${postContext.slice(0, 200)}"` : 'Post context: (not provided)'}`;

  try {
    const res = await fetch(NVIDIA_NIM_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: NVIDIA_LLM_MODEL,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt },
        ],
        max_tokens: 120,
        temperature: 0,
      }),
      signal: AbortSignal.timeout(20000), // 20s inner timeout
    });

    if (!res.ok) {
      console.warn(`[commentGateway] NVIDIA HTTP ${res.status} — falling back to heuristics`);
      return null;
    }

    const data = await res.json();
    const raw = (data.choices?.[0]?.message?.content ?? '').trim();

    // Strip optional code fences
    const cleaned = raw.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '').trim();
    const parsed = JSON.parse(cleaned);
    const VALID_TYPES = new Set(['read_first', 'sounds_harsh', 'add_scripture', 'move_private', 'ask_mentor', 'none']);
    const nudgeType = VALID_TYPES.has(parsed.nudgeType) ? parsed.nudgeType : 'none';
    return {
      nudgeType: nudgeType === 'none' ? null : nudgeType,
      reason: typeof parsed.reason === 'string' ? parsed.reason.slice(0, 200) : null,
    };
  } catch (err) {
    // Fail open — never block due to AI being down
    console.warn('[commentGateway] NVIDIA classify error (fail open):', err.message);
    return null;
  }
}

// Nudge type → human-readable message mapping
const NUDGE_MESSAGES = {
  read_first:    "It looks like you might not have fully read this yet — take a moment before posting?",
  sounds_harsh:  "This might come across as harsh. Consider rephrasing before you post.",
  add_scripture: "This post is grounded in Scripture. Adding a verse reference could strengthen your comment.",
  move_private:  "This feels personal — would a private message be better than a public comment?",
  ask_mentor:    "You seem to be wrestling with something deep. Consider reaching out to a mentor privately.",
};

// ─── Main callable ─────────────────────────────────────────────────────────────

/**
 * checkCommentQuality — callable
 *
 * Request fields:
 *   commentText     {string}  required — comment text, max 2000 chars
 *   postId          {string}  required — the post being commented on
 *   postContext     {string}  optional — brief context about the post (topic/type)
 *   clientCommentId {string}  optional — idempotency key from client
 *
 * Response:
 *   {
 *     action:        "publish" | "nudge" | "block",
 *     nudgeType?:    "read_first" | "sounds_harsh" | "add_scripture" |
 *                    "move_private" | "ask_mentor",
 *     nudgeMessage?: string,
 *     reason?:       string   (present when action === "block")
 *   }
 *
 * Fallback: if AI unavailable → { action: "publish" } — never block due to AI down.
 */
// ─── rewriteCommentTone ────────────────────────────────────────────────────────

/**
 * rewriteCommentTone — callable
 *
 * Takes a comment that was flagged (sounds_harsh, read_first, etc.) and returns
 * 1-3 gentler rewrite suggestions the user can choose from or dismiss.
 *
 * HARD RULES:
 *   - Auth required.
 *   - Suggestions are DRAFTS — client must let user choose; never auto-post.
 *   - Rate-limited to 30 rewrites per user per hour (cheaper than checkCommentQuality).
 *   - If NVIDIA unavailable, returns empty suggestions — never blocks the user.
 *
 * Request:  { commentText: string, nudgeType: string, postContext?: string }
 * Response: { suggestions: string[], nudgeType: string }
 */
exports.rewriteCommentTone = onCall(
  {
    region: REGION,
    secrets: [NVIDIA_API_KEY],
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    const uid = request.auth.uid;

    const rawText    = request.data?.commentText ?? request.data?.text;
    const nudgeType  = request.data?.nudgeType ?? 'sounds_harsh';
    const postCtx    = request.data?.postContext;

    if (!rawText || typeof rawText !== 'string' || rawText.trim().length === 0) {
      throw new HttpsError('invalid-argument', 'commentText is required.');
    }
    const trimmed = rawText.trim().slice(0, 2000);

    // Rate limit: 30 rewrites per hour
    const limited = await isCommentCheckRateLimited(uid);
    if (limited) {
      throw new HttpsError('resource-exhausted', 'Too many rewrite requests. Slow down.');
    }

    const REWRITE_INSTRUCTIONS = {
      sounds_harsh:  'The comment was flagged as harsh or confrontational. Rewrite it so it is still honest but gentler and more constructive.',
      read_first:    'The comment looks reactionary (very short, intense). Rewrite it to be more thoughtful and engaged with the content.',
      add_scripture: 'The comment makes a theological point but has no Scripture grounding. Add a relevant verse reference naturally.',
      move_private:  'The comment addresses a very personal topic. Rewrite it in a way suitable for a public reply, or suggest moving to DM.',
      ask_mentor:    'The comment expresses spiritual confusion or distress. Rewrite it so the user frames it as a question or invites prayer.',
    };

    const instruction = REWRITE_INSTRUCTIONS[nudgeType] || REWRITE_INSTRUCTIONS.sounds_harsh;

    const systemMsg =
      'You are a kind, faith-grounded writing assistant for a Christian social media app called AMEN. ' +
      'You help users express their thoughts more graciously. ' +
      'Return a JSON object with key "suggestions": an array of 2–3 alternative comment texts. ' +
      'Each suggestion must be under 300 characters and sound authentic, not robotic. ' +
      'Return ONLY valid JSON — no markdown, no prose outside the JSON.';

    const userMsg =
      `Original comment: "${trimmed}"\n` +
      (postCtx ? `Post context: "${String(postCtx).slice(0, 200)}"\n` : '') +
      `Task: ${instruction}`;

    let suggestions = [];
    try {
      const apiKey = NVIDIA_API_KEY.value();
      if (apiKey) {
        const raw = await fetch(NVIDIA_NIM_URL, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization:  `Bearer ${apiKey}`,
          },
          body: JSON.stringify({
            model:       NVIDIA_LLM_MODEL,
            messages:    [
              { role: 'system', content: systemMsg },
              { role: 'user',   content: userMsg   },
            ],
            max_tokens:  400,
            temperature: 0.8,
          }),
          signal: AbortSignal.timeout(20000),
        });

        if (raw.ok) {
          const data    = await raw.json();
          const content = (data.choices?.[0]?.message?.content ?? '').trim();
          const cleaned = content.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '').trim();
          const parsed  = JSON.parse(cleaned);
          if (Array.isArray(parsed.suggestions)) {
            suggestions = parsed.suggestions
              .filter((s) => typeof s === 'string' && s.trim().length > 0)
              .map((s) => s.trim().slice(0, 300))
              .slice(0, 3);
          }
        }
      }
    } catch (err) {
      // Fail open — never block the user if AI is unavailable
      console.warn('[commentGateway:rewriteCommentTone] NVIDIA error (fail open):', err.message);
    }

    console.log(`[commentGateway:rewriteCommentTone] uid=${uid} nudgeType=${nudgeType} suggestions=${suggestions.length}`);
    return { suggestions, nudgeType };
  }
);

// ─── checkCommentQuality callable ─────────────────────────────────────────────

exports.checkCommentQuality = onCall(
  {
    region: REGION,
    secrets: [NVIDIA_API_KEY],
    timeoutSeconds: 30,
  },
  async (request) => {
  // ── 1. Auth check ─────────────────────────────────────────────────────────
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be signed in to comment.');
  }
  const uid = request.auth.uid;

  console.log(`[commentGateway] START uid=${uid}`);

  // ── 2. Input validation ───────────────────────────────────────────────────
  // Accept both legacy `text` and new `commentText` field names.
  const rawText = request.data?.commentText ?? request.data?.text;
  const { postId, postContext, clientCommentId } = request.data || {};

  if (!rawText || typeof rawText !== 'string') {
    throw new HttpsError('invalid-argument', 'commentText is required.');
  }
  const trimmed = rawText.trim();
  if (trimmed.length === 0) {
    throw new HttpsError('invalid-argument', 'Comment cannot be empty.');
  }
  if (trimmed.length > 2000) {
    throw new HttpsError('invalid-argument', 'Comment exceeds 2000-character limit.');
  }
  if (!postId || typeof postId !== 'string') {
    throw new HttpsError('invalid-argument', 'postId is required.');
  }
  const safePostContext = postContext && typeof postContext === 'string'
    ? postContext.slice(0, 300)
    : null;

  // ── 3. Rate limit (60 / hour / user) ─────────────────────────────────────
  const limited = await isCommentCheckRateLimited(uid);
  if (limited) {
    throw new HttpsError(
      'resource-exhausted',
      'Too many comment checks. Please slow down and try again shortly.'
    );
  }

  // ── 4. Keyword safety check (fast, synchronous) ───────────────────────────
  const safetyDecision = runKeywordSafety(trimmed);

  if (safetyDecision === 'block') {
    await writeDecisionRecord(uid, clientCommentId, 'block', 'block', []);
    console.log(`[commentGateway] BLOCKED (keyword) uid=${uid} postId=${postId}`);
    return {
      action: 'block',
      reason: 'This comment contains content that cannot be posted.',
    };
  }

  // ── 5. NVIDIA AI classification (llama-3.1-70b) ───────────────────────────
  //    Fail open: if AI unavailable, we skip nudging entirely.
  let aiResult = null;
  try {
    const apiKey = NVIDIA_API_KEY.value();
    if (apiKey) {
      aiResult = await classifyWithNVIDIA(trimmed, safePostContext, apiKey);
    }
  } catch (err) {
    console.warn('[commentGateway] NVIDIA secret access error (fail open):', err.message);
  }

  // ── 6. Build action + nudge ───────────────────────────────────────────────
  //    Priority: AI result > heuristic safety warn > clean publish
  //
  //    If AI is unavailable (aiResult === null) → publish (fail open rule).
  //    If AI returned a nudgeType → nudge with that type.
  //    If keyword warn → sounds_harsh nudge (no full block for warn-level).
  //    Otherwise → publish.

  let action = 'publish';
  let nudgeType = null;
  let nudgeMessage = null;
  let reason = null;

  if (aiResult && aiResult.nudgeType) {
    action = 'nudge';
    nudgeType = aiResult.nudgeType;
    nudgeMessage = NUDGE_MESSAGES[nudgeType] || aiResult.reason || 'Consider revising before posting.';
    reason = aiResult.reason;
  } else if (safetyDecision === 'warn') {
    // Keyword-level warn (no AI result) → sounds_harsh nudge
    action = 'nudge';
    nudgeType = 'sounds_harsh';
    nudgeMessage = NUDGE_MESSAGES.sounds_harsh;
  }
  // else: action stays 'publish'

  // ── 7. Legacy heuristic nudges (only used if AI returned null — additional pass) ──
  //    Run heuristics only when AI was unavailable, to maintain V1 behaviour.
  if (aiResult === null && action === 'publish') {
    const heuristicNudges = collectNudges(trimmed);
    if (heuristicNudges.length > 0) {
      // Map first heuristic to closest nudge type
      const first = heuristicNudges[0];
      if (first.includes('Did you read') || first.includes('more thoughtful')) {
        nudgeType = 'read_first';
      } else if (first.includes('harsh') || first.includes('hurtful')) {
        nudgeType = 'sounds_harsh';
      } else if (first.includes('Scripture') || first.includes('scripture')) {
        nudgeType = 'add_scripture';
      } else if (first.includes('private') || first.includes('personal')) {
        nudgeType = 'move_private';
      } else {
        nudgeType = 'sounds_harsh'; // generic fallback
      }
      action = 'nudge';
      nudgeMessage = NUDGE_MESSAGES[nudgeType] || first;
    }
  }

  // ── 8. Write decision record (always, for audit trail) ────────────────────
  const legacyNudges = nudgeType ? [nudgeMessage] : [];
  await writeDecisionRecord(uid, clientCommentId, action, safetyDecision, legacyNudges);

  console.log(
    `[commentGateway] COMPLETE uid=${uid} postId=${postId} ` +
    `action=${action} nudgeType=${nudgeType || 'none'} aiUsed=${aiResult !== null}`
  );

  // Spec response shape
  const response = { action };
  if (nudgeType) {
    response.nudgeType = nudgeType;
    response.nudgeMessage = nudgeMessage;
  }
  if (action === 'block' && reason) {
    response.reason = reason;
  }
  return response;
});

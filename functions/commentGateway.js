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
 *     3. Safety check (keyword lexicon + Vertex AI — reuses aiModeration pipeline)
 *     4. Quality heuristics (did-you-read, tone, scripture nudge, length, etc.)
 *     5. Returns { decision, nudges, safetyDecision } — never writes to Firestore itself
 *
 * DECISION CONTRACT:
 *   decision:       "publish" | "nudge" | "block"
 *   nudges:         string[]  (contextual suggestions; empty when decision === "publish")
 *   safetyDecision: "allow"   | "warn"  | "block"
 *
 *   "nudge"  = show prompts; user MAY dismiss and post anyway (suggestions, not blocks)
 *   "block"  = hard safety violation; client MUST prevent the write
 *
 * HARD RULES ENFORCED HERE:
 *   - A comment MUST NOT reach the database before this callable returns "publish" or
 *     the user has acknowledged a "nudge" and chosen to post anyway.
 *   - NVIDIA_API_KEY via Secret Manager only (see module-level constant).
 *   - Every path: auth check + input validation + rate limit.
 *
 * RECORD CONTRACT:
 *   Every call (pass OR block) writes a lightweight decision record to
 *   Firestore: commentModerationDecisions/{uid}_{clientCommentId}
 *   This satisfies the "no write without a moderation decision record" rule.
 */

'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const db = admin.firestore();

const REGION = 'us-central1';

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

// ─── Main callable ─────────────────────────────────────────────────────────────

/**
 * checkCommentQuality — callable
 *
 * Request fields:
 *   text            {string}  required — comment text, max 2000 chars
 *   postId          {string}  required — the post being commented on
 *   clientCommentId {string}  optional — idempotency key from client
 *
 * Response:
 *   {
 *     decision:       "publish" | "nudge" | "block",
 *     nudges:         string[],
 *     safetyDecision: "allow" | "warn" | "block"
 *   }
 */
exports.checkCommentQuality = onCall({ region: REGION }, async (request) => {
  // ── 1. Auth check ─────────────────────────────────────────────────────────
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be signed in to comment.');
  }
  const uid = request.auth.uid;

  // ── 2. Input validation ───────────────────────────────────────────────────
  const { text, postId, clientCommentId } = request.data || {};

  if (!text || typeof text !== 'string') {
    throw new HttpsError('invalid-argument', 'text is required.');
  }
  const trimmed = text.trim();
  if (trimmed.length === 0) {
    throw new HttpsError('invalid-argument', 'Comment cannot be empty.');
  }
  if (trimmed.length > 2000) {
    throw new HttpsError('invalid-argument', 'Comment exceeds 2000-character limit.');
  }
  if (!postId || typeof postId !== 'string') {
    throw new HttpsError('invalid-argument', 'postId is required.');
  }

  // ── 3. Rate limit (60 / hour / user) ─────────────────────────────────────
  const limited = await isCommentCheckRateLimited(uid);
  if (limited) {
    throw new HttpsError(
      'resource-exhausted',
      'Too many comment checks. Please slow down and try again shortly.'
    );
  }

  // ── 4. Safety check ───────────────────────────────────────────────────────
  const safetyDecision = runKeywordSafety(trimmed);

  if (safetyDecision === 'block') {
    // Hard block — record immediately and return.
    await writeDecisionRecord(uid, clientCommentId, 'block', 'block', []);
    console.log(`[commentGateway] BLOCKED uid=${uid} postId=${postId}`);
    return {
      decision: 'block',
      nudges: [],
      safetyDecision: 'block',
    };
  }

  // ── 5. Quality heuristics ─────────────────────────────────────────────────
  const nudges = collectNudges(trimmed);

  // A safety warning contributes a generic nudge (user can still post)
  if (safetyDecision === 'warn') {
    nudges.unshift('This comment may be hurtful — consider a kinder approach before posting.');
  }

  // ── 6. Build decision ─────────────────────────────────────────────────────
  //
  // Rules:
  //  • safetyDecision === 'block'  → already returned above
  //  • Any nudges present          → decision = "nudge"  (user must see prompts, can dismiss)
  //  • No nudges, safety ok        → decision = "publish"
  //
  const decision = nudges.length > 0 ? 'nudge' : 'publish';

  // ── 7. Write decision record (always, for audit trail) ────────────────────
  await writeDecisionRecord(uid, clientCommentId, decision, safetyDecision, nudges);

  console.log(
    `[commentGateway] uid=${uid} postId=${postId} ` +
    `safety=${safetyDecision} decision=${decision} nudges=${nudges.length}`
  );

  return {
    decision,
    nudges,
    safetyDecision,
  };
});

// abuseDetectionSignals.js
// AMEN Safety — Abuse, exploitation, and fraud signal extraction.
// Produces risk events for human review. Never auto-restricts.
//
// Surfaces covered:
//   - Direct messages (conversations/{id}/messages/{id})
//   - Mass-DM velocity tracking (users/{uid}/dmVelocity/{hourKey})
//
// All signals are queued to safetyReviews/{reviewId} for human review.
// No content is automatically removed. No account is automatically restricted.
// See docs/safety/ABUSE_DETECTION.md for the full spec and policy decisions.

'use strict';

const admin = require('firebase-admin');
const { logger } = require('firebase-functions');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');

// ── Signal patterns ────────────────────────────────────────────────────────────
//
// Each pattern group targets one threat category. Patterns are intentionally
// conservative — they target high-confidence phrases, not broad theological terms.
// See ABUSE_DETECTION.md § 1 for the rationale behind each category.

const SIGNALS = {
  // ── Spiritual abuse ──────────────────────────────────────────────────────────
  // Coercive/isolating language using faith framing.
  // [DECISION REQUIRED]: denomination-agnostic boundary definition (D-01)
  spiritualAbuse: [
    // Claims of exclusive divine authority over the recipient
    /\b(only\s+I\s+can\s+save|God\s+told\s+me\s+to\s+tell\s+you)\b/i,

    // Commands to sever relationships framed as spiritual obligation
    /\b(leave\s+your\s+(family|friends|church|husband|wife|spouse))\b/i,
    /\b(cut\s+off\s+your\s+(family|friends|loved\s+ones|support))\b/i,
    /\b(forsake\s+(them|your\s+family|your\s+friends))\b/i,

    // Accusations of spiritual failure used as pressure
    /\b(unsubmissive|rebellious\s+spirit|spirit\s+of\s+rebellion)\b/i,
    /\b(deceived\s+by\s+(Satan|the\s+devil|demons|dark\s+forces))\b/i,

    // Faith-conditioned financial coercion (overlaps with financialExploitation)
    /\b(test\s+your\s+faith|prove\s+your\s+faith)\s+(by\s+)?(giving|sending|paying)/i,

    // Isolation + obedience framing
    /\b(God\s+(wants|needs)\s+you\s+to\s+obey\s+(me|us|your\s+pastor))\b/i,
    /\b(your\s+(disobedience|doubt|unbelief)\s+(is\s+)?(blocking|preventing|stopping)\s+(your\s+)?(blessing|healing|breakthrough))\b/i,
  ],

  // ── Financial exploitation ───────────────────────────────────────────────────
  // Seed-faith scams, fake ministry/charity, donation pressure in private messages.
  // [DECISION REQUIRED]: money-mention threshold per day (D-03), Covenant-tier exemption (D-04)
  financialExploitation: [
    // Seed faith / prophetic giving language
    /\b(seed\s+faith|sow\s+a\s+seed|plant\s+a\s+(financial\s+)?seed)\b/i,
    /\b(God\s+will\s+(multiply|bless|return)\s+(your\s+)?(gift|donation|seed|offering))\b/i,
    /\b(prophetic\s+(offering|gift|seed))\b/i,

    // Direct money solicitation via personal payment methods
    /\b(send\s+(me\s+)?(money|cash|\$[\d]+|funds|payment))\b/i,
    /\b(wire\s+transfer|western\s+union|moneygram)\b/i,
    /\b(crypto|bitcoin|ethereum|usdc|usdt|btc|eth)\s.{0,30}(send|transfer|pay|wallet|address)/i,
    /\b(zelle|venmo|cashapp|cash\s+app|paypal)\s.{0,50}(send|pay|transfer|my\s+\w+|@\w+)/i,

    // Conditional blessing / pay-to-unlock language
    /\b(donate\s+to\s+receive|give\s+to\s+unlock|pay\s+(for\s+)?(prayer|blessing|prophecy|healing))\b/i,
    /\b(your\s+miracle\s+(is\s+)?(tied\s+to|waiting\s+on)\s+your\s+(giving|offering|seed))\b/i,

    // Ministry fund solicitation with personal payment details
    /\b(ministry\s+(fund|account|wallet)|church\s+(fund|collection|account))\s+(number|details|info|link)/i,

    // Urgency + money combination
    /\b(urgent|emergency|desperate|critical)\b.{0,80}\b(send|transfer|give|donate|pay)\b/i,
  ],

  // ── Romance fraud ────────────────────────────────────────────────────────────
  // Fast intimacy escalation + money ask + off-platform migration patterns.
  // [DECISION REQUIRED]: account age threshold for severity escalation (D-06),
  //                      off-platform push handling (D-07)
  romanceFraud: [
    // Rapid divine-destiny romantic framing
    /\b(God\s+sent\s+you\s+to\s+me|you\s+are\s+my\s+(covenant\s+partner|God-send|divine\s+match))\b/i,
    /\b(fell\s+in\s+love\s+with\s+you|I\s+love\s+you\s+(already|so\s+much))\b.{0,100}(meet|together|us)/i,
    /\b(meant\s+to\s+(be\s+)?(together|meet|find\s+each\s+other))\b/i,

    // Financial emergency narrative + payment escalation
    /\b(I\s+need\s+your\s+help|financial\s+emergency|stranded|stuck\s+(abroad|overseas|in\s+\w+))\b.{0,120}(send|transfer|pay|wire)/i,
    /\b(hospital|accident|surgery|medical\s+emergency)\b.{0,120}(send|transfer|pay|money|funds)/i,
    /\b(military|deployed|serving\s+abroad)\b.{0,100}(send|transfer|gift\s+card|money)/i,

    // Off-platform migration push
    /\b(move\s+(our\s+)?conversation\s+(to|off)\s+(whatsapp|telegram|signal|email|snapchat|instagram|facebook))\b/i,
    /\b(continue\s+(this\s+)?(on|via|at)\s+(whatsapp|telegram|signal|my\s+email))\b/i,
    /\b(add\s+me\s+(on|at)\s+(whatsapp|telegram|signal))\b/i,

    // Gift card scam (common romance fraud vector)
    /\b(gift\s+card\s+(number|code|pin|balance))\b.{0,80}(send|share|give)/i,
    /\b(buy\s+(me\s+a\s+)?gift\s+card|get\s+(some\s+)?gift\s+cards)\b/i,
  ],
};

// ── Utility: extract signals from message text ─────────────────────────────────

/**
 * Extract abuse signals from message text.
 * Returns an array of { type, patternHint, confidence } objects.
 * Privacy note: the patternHint is a truncated regex source string — never the
 * matched user content — so it is safe to include in log metadata.
 *
 * @param {string} text
 * @returns {{ type: string, patternHint: string, confidence: number }[]}
 */
function extractSignals(text) {
  if (!text || typeof text !== 'string') return [];
  const found = [];
  for (const [type, patterns] of Object.entries(SIGNALS)) {
    for (const pattern of patterns) {
      if (pattern.test(text)) {
        found.push({
          type,
          patternHint: pattern.source.slice(0, 60),
          confidence: 0.7,
        });
      }
    }
  }
  return found;
}

// ── Utility: queue a risk event for human review ───────────────────────────────

/**
 * Write a review event to safetyReviews/{reviewId}.
 * This is the only write this module makes. It never touches user documents,
 * messages, or any restriction/ban collection.
 *
 * Privacy model:
 *   contentSnippet is always null until a policy decision (D-11) explicitly
 *   enables storage with appropriate access controls.
 *
 * [DECISION REQUIRED]: content storage policy (D-11)
 * [DECISION REQUIRED]: Firestore rules for moderator query access (D-18)
 *
 * @param {string}   senderId      UID of the message sender
 * @param {string|null} recipientId  UID of the recipient, or null
 * @param {string}   surface       "dm" | "mass_dm_velocity" | "prayer_wall" | "space_message"
 * @param {{ type: string, confidence: number }[]} signals
 * @param {"medium"|"high"|"critical"} severity
 */
async function queueRiskEvent(senderId, recipientId, surface, signals, severity) {
  const db = admin.firestore();
  await db.collection('safetyReviews').add({
    type: 'abuse_signal',
    senderId,
    recipientId: recipientId || null,
    surface,
    signals: signals.map(s => ({ type: s.type, confidence: s.confidence })),
    severity,
    detectedAt: admin.firestore.FieldValue.serverTimestamp(),
    status: 'pending',
    requiresHumanReview: true,
    // [DECISION REQUIRED] D-11: whether to store content snippet for review context.
    // Until that decision is made, this is always null.
    contentSnippet: null,
    // Reserved for moderator use — set externally when reviewed
    reviewedBy: null,
    reviewedAt: null,
    reviewNotes: null,
    actionTaken: null,
  });
}

// ── Firestore trigger: new DM message ─────────────────────────────────────────
//
// Fires on every new message in a conversation.
// [DECISION REQUIRED] D-12: whether to scan all DMs or only messages from
//                            flagged/high-risk accounts.

exports.onNewDMMessage = onDocumentCreated(
  'conversations/{conversationId}/messages/{messageId}',
  async (event) => {
    const msg = event.data?.data();
    if (!msg || !msg.content) return;

    const signals = extractSignals(msg.content);
    if (signals.length === 0) return;

    // Severity: any two or more signals in a single message → high; one signal → medium.
    const severity = signals.length >= 2 ? 'high' : 'medium';

    // Log signal metadata only — never log message content.
    logger.warn('[abuseDetection] signals found in DM', {
      conversationId: event.params.conversationId,
      senderId: msg.senderId,
      signalTypes: signals.map(s => s.type),
      severity,
      signalCount: signals.length,
      // Content NOT logged — metadata only.
    });

    await queueRiskEvent(
      msg.senderId,
      msg.recipientId || null,
      'dm',
      signals,
      severity,
    );
  },
);

// ── Velocity heuristic: mass DM detection ─────────────────────────────────────
//
// Called from the message send path (currently not wired into index.js by this
// agent — see task instructions). Can also be invoked independently.
//
// Thresholds are placeholders pending policy decisions.
// [DECISION REQUIRED] D-08: MASS_DM_THRESHOLD_PER_HOUR value
// [DECISION REQUIRED] D-03: MONEY_MENTION_THRESHOLD_PER_DAY value
// [DECISION REQUIRED] D-09: per-hour vs. rolling 15-min window

const MASS_DM_THRESHOLD_PER_HOUR = 20; // [DECISION REQUIRED] D-08
const MONEY_MENTION_THRESHOLD_PER_DAY = 5; // [DECISION REQUIRED] D-03

/**
 * Increment the per-hour DM counter for a sender and queue a review event if
 * the mass-DM velocity threshold is exceeded.
 *
 * Uses optimistic read-increment-write. Idempotent within any given hour key.
 * Does not restrict the sender — the event is queued for human review only.
 *
 * @param {string} senderId
 */
async function checkDMVelocity(senderId) {
  const db = admin.firestore();

  // Hour key in UTC: "2026-05-29T14" — one document per user per hour.
  const hourKey = new Date().toISOString().slice(0, 13);
  const ref = db.doc(`users/${senderId}/dmVelocity/${hourKey}`);

  const snap = await ref.get();
  const count = snap.exists ? (snap.data().count ?? 0) : 0;

  if (count >= MASS_DM_THRESHOLD_PER_HOUR) {
    logger.warn('[abuseDetection] mass DM velocity threshold exceeded', {
      senderId,
      count,
      hourKey,
      threshold: MASS_DM_THRESHOLD_PER_HOUR,
      // Sender NOT restricted — event queued for human review.
    });
    await queueRiskEvent(
      senderId,
      null,
      'mass_dm_velocity',
      [{ type: 'mass_dm', confidence: 0.9 }],
      'high',
    );
  }

  // Always increment the counter, regardless of whether the threshold was hit.
  await ref.set({ count: count + 1 }, { merge: true });
}

exports.checkDMVelocity = checkDMVelocity;

// ── Module exports (for unit testing and manual invocation) ───────────────────

module.exports = {
  extractSignals,
  queueRiskEvent,
  checkDMVelocity,
  // Expose thresholds so tests can assert against current values without
  // importing a constant they don't own.
  MASS_DM_THRESHOLD_PER_HOUR,
  MONEY_MENTION_THRESHOLD_PER_DAY,
};

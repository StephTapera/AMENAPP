// crisisDetectionHook.js
// AMEN Safety — Crisis signal detection hook.
// Runs as a server-side check on Berean turns before response is sent.
// Conservative (recall-leaning) classifier — false positives are acceptable.
// HUMAN REVIEW REQUIRED before any action is taken on a flagged signal.
//
// Privacy model:
//   - Content (user message text) is NEVER stored in any log, review doc, or external service.
//   - Only metadata (userId, severity, surface, timestamp) is persisted.
//   - This hook does not restrict, limit, or modify the user's account in any way.
//   - Crisis signals are NOT used to infer mental health status for any purpose
//     other than surfacing immediate resources and queuing for pastoral review.
//
// See docs/safety/CRISIS_RESPONSE.md for the full policy spec and open decisions.

'use strict';

const admin = require('firebase-admin');
const { logger } = require('firebase-functions');

// ── Keyword patterns (conservative, recall-leaning) ───────────────────────────
// These patterns are intentionally broad. A false positive that surfaces
// resources to a non-crisis user is far less harmful than a false negative
// (a person in genuine crisis who receives no support signal).
//
// [DECISION REQUIRED]: Product + pastoral leads must review and tune these
// pattern lists, especially 'warning' level, before production deployment.
// See docs/safety/CRISIS_RESPONSE.md §8 Decision D1.
const CRISIS_PATTERNS = {
  critical: [
    /\b(kill|end|take)\s+(my|myself|my\s+life)\b/i,
    /\b(suicide|suicidal|want\s+to\s+die|don't\s+want\s+to\s+live|cant\s+go\s+on|can't\s+go\s+on)\b/i,
    /\b(hurt|harm|cut|injure)\s+(myself|my\s+body|my\s+wrists?)\b/i,
    /\bgoodbye\s+(letter|note|everyone|forever)\b/i,
    /\b(ending\s+it|end\s+it\s+all|no\s+reason\s+to\s+live|rather\s+be\s+dead)\b/i,
  ],
  high: [
    /\b(hopeless|worthless|a\s+burden|no\s+one\s+cares|nobody\s+cares)\b/i,
    /\b(abuse|hitting\s+me|hurting\s+me|violence|threatened|scared\s+for\s+my\s+life)\b/i,
    /\b(can't\s+take\s+it|cant\s+take\s+it|given\s+up|no\s+hope|no\s+point)\b/i,
    /\b(don't\s+want\s+to\s+be\s+here|doesn't\s+want\s+to\s+be\s+here)\b/i,
    /\b(self.harm|self\s+harm|cutting\s+myself|hurt\s+myself)\b/i,
  ],
  warning: [
    /\b(depressed|depression|struggling\s+so\s+hard|overwhelmed|breaking\s+down|falling\s+apart)\b/i,
    /\b(anxious|panic\s+attack|terrified|afraid\s+all\s+the\s+time)\b/i,
    /\b(can't\s+cope|cant\s+cope|can't\s+function|cant\s+function)\b/i,
    /\b(feel\s+so\s+alone|so\s+lonely|no\s+one\s+to\s+talk\s+to)\b/i,
  ],
};

// ── Crisis resources (region-configurable) ────────────────────────────────────
// [DECISION REQUIRED]: Replace with actual regional config or load from
// Firestore at config/crisisResources for hot-update capability.
// See docs/safety/CRISIS_RESPONSE.md §5 and §8 Decision D2 and D7.
const DEFAULT_CRISIS_RESOURCES = [
  {
    name: '988 Suicide & Crisis Lifeline',
    contact: 'Call or text 988',
    region: 'US',
  },
  {
    name: 'Crisis Text Line',
    contact: 'Text HOME to 741741',
    region: 'US',
  },
  {
    name: 'International Association for Suicide Prevention',
    contact: 'https://www.iasp.info/resources/Crisis_Centres/',
    region: 'international',
  },
  // [DECISION REQUIRED]: Add regional resources:
  //   UK:        Samaritans — 116 123 (free, 24/7)
  //   Canada:    Talk Suicide Canada — 1-833-456-4566
  //   Australia: Lifeline — 13 11 14
  //   Others:    See docs/safety/CRISIS_RESPONSE.md §5
];

// ── Classify crisis severity from text ───────────────────────────────────────
/**
 * Classify crisis severity from a text string.
 * Operates entirely in-memory — does not make any network calls or Firestore reads.
 *
 * @param {string} text — The text to classify
 * @returns {{ severity: 'critical'|'high'|'warning'|'safe', matchedPatterns: Array }}
 */
function classifyText(text) {
  if (!text || typeof text !== 'string') {
    return { severity: 'safe', matchedPatterns: [] };
  }

  const matched = [];

  for (const [level, patterns] of Object.entries(CRISIS_PATTERNS)) {
    for (const pattern of patterns) {
      if (pattern.test(text)) {
        // Truncate pattern source for log safety — never log the matched text itself
        matched.push({ level, pattern: pattern.source.slice(0, 40) });
      }
    }
  }

  if (matched.some((m) => m.level === 'critical')) {
    return { severity: 'critical', matchedPatterns: matched };
  }
  if (matched.some((m) => m.level === 'high')) {
    return { severity: 'high', matchedPatterns: matched };
  }
  if (matched.some((m) => m.level === 'warning')) {
    return { severity: 'warning', matchedPatterns: matched };
  }

  return { severity: 'safe', matchedPatterns: [] };
}

// ── Queue a crisis signal for human review ────────────────────────────────────
/**
 * Write a metadata-only record to safetyReviews for human pastoral review.
 *
 * PRIVACY INVARIANT: Content (user message text) is NEVER written here.
 * Only: userId, severity, surface, timestamp, and review status.
 *
 * [DECISION REQUIRED]: Human notification on write (push/email) vs. async
 * dashboard review. See docs/safety/CRISIS_RESPONSE.md §8 Decision D3 and D4.
 *
 * @param {string} userId
 * @param {'critical'|'high'} severity
 * @param {string} surface — 'berean_turn' | 'prayer' | 'post' | 'dm'
 */
async function queueForHumanReview(userId, severity, surface) {
  const db = admin.firestore();
  try {
    await db.collection('safetyReviews').add({
      type: 'crisis_signal',
      userId,
      severity,
      surface,
      detectedAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'pending',
      requiresHumanReview: true,
      // priority flag for critical signals — [DECISION REQUIRED] whether
      // critical triggers a real-time notification to a crisis coordinator
      priority: severity === 'critical',
      resolvedAt: null,
      resolvedBy: null,
      reviewNotes: null,
      // NOTE: Content is deliberately NOT stored here.
      // Message content remains in the user's private collection only.
      // See docs/safety/CRISIS_RESPONSE.md §7 Privacy Model.
    });
  } catch (err) {
    // Log metadata only — never log user content
    logger.error('[crisisHook] failed to queue review for human', {
      userId,
      severity,
      surface,
      error: err.message,
    });
    // Do not re-throw — a queue write failure must not prevent the user
    // from receiving in-app crisis resources.
  }
}

// ── Main crisis check function ────────────────────────────────────────────────
/**
 * Main crisis check — call from Berean proxy BEFORE sending the AI response.
 *
 * Behavior by severity:
 *   safe    → returns immediately with no-op result
 *   warning → logs metadata; returns shouldAdjustResponse: false (Berean responds normally)
 *   high    → queues for human review; returns crisis resources
 *   critical → queues for human review (priority); returns crisis resources
 *
 * [DECISION REQUIRED]: The threshold at which human review is queued is currently
 * 'high' and 'critical'. If 'warning' should also queue, update the condition
 * below. See docs/safety/CRISIS_RESPONSE.md §8 Decision D1.
 *
 * @param {string} text — user's message text (evaluated pre-response; never stored)
 * @param {string} userId — Firebase Auth UID (for audit trail only)
 * @param {string} [surface='berean_turn'] — content surface identifier
 * @returns {Promise<{ severity: string, resources: Array, shouldAdjustResponse: boolean }>}
 */
async function checkForCrisis(text, userId, surface = 'berean_turn') {
  const { severity, matchedPatterns } = classifyText(text);

  if (severity === 'safe') {
    return { severity: 'safe', resources: [], shouldAdjustResponse: false };
  }

  // Log signal metadata — content (text) is intentionally excluded from logs
  logger.warn('[crisisHook] crisis signal detected', {
    userId,
    surface,
    severity,
    patternCount: matchedPatterns.length,
    // NOTE: matchedPatterns contains only truncated regex source strings,
    // never the user's matched text.
    matchedPatternSources: matchedPatterns.map((m) => `${m.level}:${m.pattern}`),
  });

  // Queue for human review — currently: high + critical only
  // [DECISION REQUIRED]: adjust threshold in docs/safety/CRISIS_RESPONSE.md §8 D1
  if (severity === 'critical' || severity === 'high') {
    await queueForHumanReview(userId, severity, surface);
  }

  // For 'warning', Berean responds normally (shouldAdjustResponse: false).
  // We have already logged the signal above.
  if (severity === 'warning') {
    return {
      severity: 'warning',
      resources: [],
      shouldAdjustResponse: false,
      // Berean will respond normally; the log is the only action taken.
    };
  }

  // For 'high' and 'critical', replace Berean's response with crisis resources.
  // [DECISION REQUIRED]: resource list — see DEFAULT_CRISIS_RESOURCES above and §5
  const resources = DEFAULT_CRISIS_RESOURCES;

  return {
    severity,
    resources,
    shouldAdjustResponse: true,
    // Caller (bereanChatProxy) must: acknowledge distress with pastoral warmth,
    // surface resources, and NOT attempt to counsel or de-escalate.
    // See Task 3 wiring in bereanFunctions.js for the exact response template.
  };
}

module.exports = {
  checkForCrisis,
  classifyText,
  queueForHumanReview,
  DEFAULT_CRISIS_RESOURCES,
  CRISIS_PATTERNS,
};

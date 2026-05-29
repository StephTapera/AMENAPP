// minorSafetyHook.js
// AMEN Safety — Minor account protection scaffold.
// [DECISION REQUIRED]: Enable only after minimum-age policy is confirmed.
//
// FEATURE FLAG: Check AMENFeatureFlags before running any checks.
// This code is scaffolded but NOT active until the policy decisions are made.
//
// See docs/safety/MINOR_SAFETY.md for the full spec, decision table, and legal notes.

'use strict';

const admin = require('firebase-admin');
const { logger } = require('firebase-functions');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');

// ── Feature flag check ─────────────────────────────────────────────────────────
// [DECISION REQUIRED]: set minorSafetyEnabled = true in config/featureFlags
// when minimum-age policy and verification are in place
async function isMinorSafetyEnabled() {
  try {
    const snap = await admin.firestore().doc('config/featureFlags').get();
    return snap.exists ? (snap.data().minorSafetyEnabled ?? false) : false;
  } catch {
    return false; // fail closed — don't run if we can't check the flag
  }
}

// ── Age classification ─────────────────────────────────────────────────────────
// [DECISION REQUIRED]: how age is stored and verified
// Current placeholder: check users/{uid}.birthYear or users/{uid}.isMinor
//
// In practice, AMEN uses users/{uid}.ageTier (server-derived via AgeAssuranceService):
//   "under_minimum" | "teen" | "adult"
// The ageTier field is also exposed as ageBand in some backend paths.
// Treat "teen" and "under_minimum" both as minor for this hook.
// [DECISION REQUIRED]: confirm whether "teen" (13-17) should trigger the same
//   grooming detection path as "under_minimum" (< 13, which should be blocked entirely).
async function isMinorAccount(uid) {
  try {
    const snap = await admin.firestore().collection('users').doc(uid).get();
    if (!snap.exists) return false;
    const data = snap.data();

    // Primary check: server-derived ageTier (set by AgeAssuranceService CF)
    if (data.ageTier === 'under_minimum' || data.ageTier === 'teen') return true;

    // Legacy / migration fallback: explicit isMinor flag
    // [DECISION REQUIRED]: replace with actual age verification field
    if (data.isMinor === true) return true;

    // Legacy fallback: birthYear field
    if (data.birthYear) {
      const age = new Date().getFullYear() - data.birthYear;
      return age < 18; // [DECISION REQUIRED]: confirm 18 as the adult threshold
    }

    return false;
  } catch {
    return false;
  }
}

// ── Conversation participant resolution ───────────────────────────────────────
// [DECISION REQUIRED]: confirm the Firestore schema for conversation participants.
// Current assumption: conversations/{conversationId}.participantIds: string[]
// If the schema differs (e.g. participants subcollection), update this helper.
async function getConversationParticipants(conversationId) {
  try {
    const snap = await admin.firestore()
      .collection('conversations')
      .doc(conversationId)
      .get();
    if (!snap.exists) return [];
    const data = snap.data();
    // Try both common field names
    return data.participantIds ?? data.participants ?? [];
  } catch {
    return [];
  }
}

// ── Grooming pattern detection ─────────────────────────────────────────────────
// These patterns flag messages for human review only — no autonomous action.
// [DECISION REQUIRED]: review and expand this list with Trust & Safety before activation.
// Consider augmenting with an ML model (e.g. Vertex AI) for higher recall.
const GROOMING_PATTERNS = [
  // Fast intimacy / age-leveraging
  /\b(you(?:'re|r(?:e)?)\s+so\s+(?:mature|special|different)\s+for\s+your\s+age)\b/i,
  // Secrecy / caregiver isolation
  /\b(keep\s+(?:this|our\s+conversation)\s+(?:secret|between\s+us))\b/i,
  /\b(don'?t\s+tell\s+your\s+(?:parents?|mom|dad|guardian|family))\b/i,
  // In-person meeting solicitation
  /\b(meet\s+(?:me|up)\s+in\s+person|come\s+(?:see|meet)\s+me)\b/i,
  /\b(where\s+(?:do\s+you\s+)?(?:go\s+to\s+school|live|hang\s+out))\b/i,
  // Off-platform migration
  /\b(move\s+(?:this|our\s+chat)\s+to\s+(?:whatsapp|telegram|snapchat|instagram|signal|kik))\b/i,
  /\b((?:add|follow|dm)\s+me\s+on\s+(?:whatsapp|telegram|snapchat|instagram|signal|kik))\b/i,
  // Personal info extraction
  /\b(give\s+me\s+your\s+(?:number|address|school|location|snap|ig))\b/i,
  /\b(what(?:'s|\s+is)\s+your\s+(?:number|address|school|snap|ig|phone))\b/i,
  // Gift / reward offers (combined with age context)
  /\b(i(?:'ll)?\s+(?:buy|send|get)\s+you\s+(?:a\s+gift|something|money|a\s+present))\b/i,
];

/**
 * Check a message from an adult to a potentially minor recipient for grooming signals.
 * [DECISION REQUIRED]: this check only runs when minor safety is enabled and age
 * verification exists. Confidence scores are static placeholders — replace with
 * ML model scores when available.
 *
 * @param {string} text - The message body to check.
 * @returns {{ pattern: string, confidence: number }[]} Matched signals (empty = no match).
 */
function detectGroomingSignals(text) {
  if (!text || typeof text !== 'string') return [];
  return GROOMING_PATTERNS
    .filter(p => p.test(text))
    .map(p => ({
      pattern: p.source.slice(0, 60), // truncated — no message content stored
      confidence: 0.8,                 // [DECISION REQUIRED]: replace with model score
    }));
}

/**
 * Queue a priority review for potential grooming.
 * Message content is NOT stored — metadata only.
 *
 * [DECISION REQUIRED]: SLA for human review — proposed P0 = 1 hour.
 * [DECISION REQUIRED]: Whether to immediately freeze sender account
 *   or only flag for review. Current scaffold: flag only, no freeze.
 *
 * @param {string} senderId
 * @param {string|null} recipientId
 * @param {{ pattern: string, confidence: number }[]} signals
 * @param {string} conversationId
 */
async function queueGroomingReview(senderId, recipientId, signals, conversationId) {
  const db = admin.firestore();
  await db.collection('safetyReviews').add({
    type: 'grooming_signal',
    priority: 'high',           // [DECISION REQUIRED]: map priority to FCM alert to on-call
    senderId,
    recipientId: recipientId ?? null,
    conversationId: conversationId ?? null,
    signals: signals.map(s => s.pattern), // pattern labels only — no message content
    detectedAt: admin.firestore.FieldValue.serverTimestamp(),
    status: 'pending',
    requiresHumanReview: true,
    requiresImmediateReview: true, // [DECISION REQUIRED]: enforce 1-hour SLA?
    // Content NOT stored — metadata only per privacy requirements.
  });

  // Also write to moderationQueue so the existing Trust & Safety pipeline picks it up.
  await db.collection('moderationQueue').add({
    type: 'youth_safety_alert',
    alertType: 'grooming_signal',
    senderId,
    recipientId: recipientId ?? null,
    conversationId: conversationId ?? null,
    signalCount: signals.length,
    priority: 'high',
    status: 'pending',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ── Guardian alert delivery ────────────────────────────────────────────────────
// If the recipient is a minor with active guardian connections, deliver an alert.
// Delegates to the existing GuardianConnectionService pattern:
//   writes to users/{minorUid}/safety/{alertId}, which triggers
//   forwardYouthAlertToGuardians (Backend/functions/src/safety/GuardianConnectionService.ts).
//
// [DECISION REQUIRED]: confirm this write path is live and GuardianConnectionService
//   CF is deployed before enabling this hook.
async function writeMinorSafetyAlert(minorUid, actorUid, alertType, contextId) {
  try {
    const db = admin.firestore();
    await db.collection('users').doc(minorUid).collection('safety').add({
      alertType,
      actorUid: actorUid ?? null,
      contextId: contextId ?? null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    logger.warn('[minorSafety] failed to write minor safety alert', { minorUid, alertType, err: err.message });
  }
}

// ── Firestore trigger: new DM for minor protection ────────────────────────────
// Fires on every new message in any conversation.
// Gated by isMinorSafetyEnabled() — returns early when flag is off.
//
// [DECISION REQUIRED]: whether to scan all DMs or only cross-age DMs.
// Current scaffold: runs checks only when recipient is confirmed minor.
//
// [DECISION REQUIRED]: whether to extend this trigger to group Space messages
//   (currently scoped to conversations/ only).
exports.onNewDMForMinorProtection = onDocumentCreated(
  { document: 'conversations/{conversationId}/messages/{messageId}', region: 'us-central1' },
  async (event) => {
    // Gate: do nothing unless policy is confirmed and flag is on.
    if (!(await isMinorSafetyEnabled())) return;

    const msg = event.data?.data();
    if (!msg || !msg.content || !msg.senderId) return;

    const { conversationId } = event.params;
    const senderId = msg.senderId;

    // Resolve conversation participants to find the recipient(s).
    const participants = await getConversationParticipants(conversationId);
    const recipientIds = participants.filter(uid => uid !== senderId);

    if (recipientIds.length === 0) {
      logger.debug('[minorSafety] no recipients found', { conversationId });
      return;
    }

    // Check if any recipient is a minor.
    // [DECISION REQUIRED]: in group conversations, apply check if ANY participant is minor?
    //   Current: check all recipients, act if any is a minor.
    let minorRecipientId = null;
    for (const recipientId of recipientIds) {
      if (await isMinorAccount(recipientId)) {
        minorRecipientId = recipientId;
        break;
      }
    }

    if (!minorRecipientId) {
      // No minor recipient — no action needed.
      return;
    }

    // Verify sender is an adult (or unknown = treated as adult for safety purposes).
    const senderIsMinor = await isMinorAccount(senderId);
    // [DECISION REQUIRED]: apply grooming detection to minor-to-minor DMs?
    //   Rationale for adult-only: grooming is typically adult→minor.
    //   Rationale for all: peer-to-peer exploitation also occurs.
    //   Current scaffold: adult→minor only.
    if (senderIsMinor) {
      logger.debug('[minorSafety] minor-to-minor DM — skipping grooming check', {
        conversationId,
        // [DECISION REQUIRED]: add minor-to-minor safety patterns separately?
      });
      return;
    }

    logger.info('[minorSafety] adult-to-minor DM detected, running grooming check', {
      conversationId,
      senderId,
      minorRecipientId,
      // Content NOT logged.
    });

    // Run grooming signal detection on message content.
    const signals = detectGroomingSignals(msg.content);

    if (signals.length > 0) {
      logger.warn('[minorSafety] grooming signals detected', {
        conversationId,
        senderId,
        signalCount: signals.length,
        // Content NOT logged — pattern labels only.
      });

      // Queue for human review (P0 — proposed 1-hour SLA).
      await queueGroomingReview(senderId, minorRecipientId, signals, conversationId);

      // Write to minor's safety subcollection to trigger guardian alert.
      await writeMinorSafetyAlert(minorRecipientId, senderId, 'grooming_signal', conversationId);
    }
  }
);

// ── Apply age-appropriate defaults to a user account ─────────────────────────
/**
 * Apply conservative privacy and interaction defaults when an account is
 * identified or classified as a minor.
 *
 * [DECISION REQUIRED]: confirm each default value with policy/legal before activation.
 * [DECISION REQUIRED]: trigger point — called on ageTier write? On account creation?
 *   The Backend YouthSafetyService.enforceYouthAccountDefaults trigger already handles
 *   ageTier changes. This function is a JavaScript-side equivalent for the functions/
 *   Cloud Functions environment.
 *
 * @param {string} uid - The minor user's UID.
 */
async function applyMinorAccountDefaults(uid) {
  if (!(await isMinorSafetyEnabled())) return;

  const db = admin.firestore();
  await db.collection('users').doc(uid).set({
    // [DECISION REQUIRED]: confirm these default values with policy/legal
    privacySettings: {
      discoverability: 'restricted',       // not shown in People Discovery
      allowDMsFrom: 'confirmed_contacts',  // [DECISION REQUIRED]: guardian-approved only?
      showInSearch: false,                  // [DECISION REQUIRED]: confirm suppression
      showInPeopleDiscovery: false,         // [DECISION REQUIRED]
      publicProfile: false,                 // [DECISION REQUIRED]: private by default for teens
    },
    // Safety defaults (mirrors YouthSafetyService.enforceYouthAccountDefaults)
    dmEnabled: false,
    anonymousMessagingAllowed: false,
    locationExposureAllowed: false,
    matureContentAllowed: false,
    searchableLocation: false,
    // Audit fields
    minorAccountDefaults: true,
    minorDefaultsAppliedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  logger.info('[minorSafety] applied account defaults', { uid });
}

// ── Exports ───────────────────────────────────────────────────────────────────
// detectGroomingSignals and isMinorAccount are exported for unit testing.
// applyMinorAccountDefaults is exported for use by account creation flows.
// onNewDMForMinorProtection is the active Firestore trigger (gated by feature flag).
module.exports = {
  detectGroomingSignals,
  applyMinorAccountDefaults,
  isMinorAccount,
  // onNewDMForMinorProtection is registered above via onDocumentCreated;
  // export it so it can be included in functions/index.js when policy is confirmed.
  // [DECISION REQUIRED]: add to functions/index.js exports only after policy sign-off.
  onNewDMForMinorProtection: exports.onNewDMForMinorProtection,
};

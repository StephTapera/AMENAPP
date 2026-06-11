/**
 * minorProtection.js
 * AMEN — Minor protection layer for the faith-based social platform.
 *
 * All functions in this module are called from trusted Cloud Functions only.
 * None of these exports are exposed as callable endpoints directly; callers
 * are responsible for enforcing authentication and App Check before invoking.
 *
 * Age tier vocabulary (authoritative source: ageTier.js):
 *   blocked  — age < 13   (COPPA hard block; ageTier = "blocked")
 *   tierB    — 13–15      (isMinor = true, minorAgeBand = "13_15")
 *   tierC    — 16–17      (isMinor = true, minorAgeBand = "16_17")
 *   tierD    — 18+        (isMinor = false)
 *
 * Firestore collections written by this module:
 *   users/{uid}                      — safety field updates (setMinorFlag)
 *   safetyAlerts/{alertId}           — adult→minor interaction events
 *   moderationQueue/{itemId}         — flagged-for-review items
 *   inviteSafetyQueue/{itemId}       — Sanctuary invite safety routing
 */

"use strict";

const admin = require("firebase-admin");
const { MINOR_TIERS } = require("../ageTier");

// ---------------------------------------------------------------------------
// SCHEMA DOCUMENTATION
// ---------------------------------------------------------------------------

/**
 * Canonical shape of the `safety` sub-document stored on each user record.
 * Written by setMinorFlag; read by all functions in this module.
 *
 * @typedef {Object} UserSafetySchema
 * @property {"unknown"|"self_attested"|"guardian_verified"|"verified"} ageAssuranceStatus
 * @property {boolean|null} isMinor
 * @property {"under13"|"13_15"|"16_17"|null} minorAgeBand
 * @property {boolean} guardianLinked
 * @property {string[]} guardianIds
 * @property {"restricted"|"guardian_visible"|"disabled"} dmSafetyMode
 * @property {"hidden"|"limited"|"standard"} discoverySafetyMode
 */
const USER_SAFETY_SCHEMA = Object.freeze({
  ageAssuranceStatus: "unknown",   // "unknown" | "self_attested" | "guardian_verified" | "verified"
  isMinor: null,                   // boolean | null — null means not yet determined
  minorAgeBand: null,              // "under13" | "13_15" | "16_17" | null
  guardianLinked: false,
  guardianIds: [],
  dmSafetyMode: "restricted",      // "restricted" | "guardian_visible" | "disabled"
  discoverySafetyMode: "limited",  // "hidden" | "limited" | "standard"
});

// ---------------------------------------------------------------------------
// INTERNAL HELPERS
// ---------------------------------------------------------------------------

/**
 * Fetch the safety sub-document for a single user.
 * Returns an empty object (not null) when the field is absent so callers can
 * safely destructure without null checks.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 * @returns {Promise<{safety: Object, ageTier: string|undefined}>}
 */
async function _getUserSafetyFields(db, uid) {
  const snap = await db.collection("users").doc(uid).get();
  if (!snap.exists) return { safety: {}, ageTier: undefined };
  const data = snap.data();
  return {
    safety: data.safety || {},
    ageTier: data.ageTier,
  };
}

/**
 * Derive isMinor from the server-computed ageTier, falling back to the stored
 * safety.isMinor field. Returns null when both sources are absent.
 *
 * Tier "blocked" (under-13) is treated as minor=true.
 *
 * @param {Object} safetyFields
 * @param {string|undefined} ageTier
 * @returns {boolean|null}
 */
function _resolveIsMinor(safetyFields, ageTier) {
  if (ageTier !== undefined) {
    return MINOR_TIERS.includes(ageTier);
  }
  // Fall back to the stored flag (may be null)
  return safetyFields.isMinor !== undefined ? safetyFields.isMinor : null;
}

/**
 * Determine whether an approved guardian-child relationship exists between
 * two UIDs. An approved relationship exists when either:
 *   - guardianIds in the minor's safety doc contains the adult's UID, OR
 *   - guardianIds in the adult's safety doc contains the minor's UID
 *     (bidirectional: guardian may be linked before minor profile is updated).
 *
 * @param {Object} safetySender
 * @param {Object} safetyRecipient
 * @param {string} senderUid
 * @param {string} recipientUid
 * @returns {boolean}
 */
function _hasApprovedRelationship(safetySender, safetyRecipient, senderUid, recipientUid) {
  const recipientGuardians = safetyRecipient.guardianIds || [];
  const senderGuardians = safetySender.guardianIds || [];
  return (
    recipientGuardians.includes(senderUid) ||
    senderGuardians.includes(recipientUid)
  );
}

/**
 * Generate a short unique ID for alert/queue documents.
 * @returns {string}
 */
function _alertId() {
  return `mp_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

// ---------------------------------------------------------------------------
// PUBLIC EXPORTS
// ---------------------------------------------------------------------------

/**
 * Check whether an adult–minor interaction should be allowed, blocked, or
 * flagged for review.
 *
 * @param {FirebaseFirestore.Firestore} db          Firestore Admin instance.
 * @param {string}   senderUid                       UID of the sender / initiator.
 * @param {string}   recipientUid                    UID of the recipient / target.
 * @param {"dm"|"sanctuary_invite"|"reply"} contentType  Type of interaction.
 * @returns {Promise<{
 *   allowed: boolean,
 *   blocked: boolean,
 *   reason: string,
 *   requiresReview: boolean
 * }>}
 */
async function checkAdultMinorInteraction(db, senderUid, recipientUid, contentType) {
  // Fetch both users in parallel to minimise latency.
  const [senderFields, recipientFields] = await Promise.all([
    _getUserSafetyFields(db, senderUid),
    _getUserSafetyFields(db, recipientUid),
  ]);

  const senderIsMinor   = _resolveIsMinor(senderFields.safety, senderFields.ageTier);
  const recipientIsMinor = _resolveIsMinor(recipientFields.safety, recipientFields.ageTier);

  // Only act when exactly one party is a confirmed minor and the other is a
  // confirmed adult. When either value is null (unknown), fall through to allow
  // with requiresReview=true so the moderation queue can catch edge cases.
  const mixedAdultMinor =
    (senderIsMinor === true && recipientIsMinor === false) ||
    (senderIsMinor === false && recipientIsMinor === true);

  const eitherUnknown = senderIsMinor === null || recipientIsMinor === null;

  if (!mixedAdultMinor && !eitherUnknown) {
    // Both adults, both minors, or same status — no special restriction.
    return { allowed: true, blocked: false, reason: "no_age_restriction", requiresReview: false };
  }

  if (eitherUnknown) {
    // Fail closed per Amen safety policy: unknown age = treated as minor.
    // An unverified user may be a child; we must not allow them into adult DM flows.
    // For DMs, block immediately. For other content types, queue for human review.
    if (contentType === "dm") {
      const alertId2 = _alertId();
      await db.collection("safetyAlerts").doc(alertId2).set({
        id: alertId2,
        senderUid,
        recipientUid,
        contentType,
        action: "blocked",
        reason: "age_unknown_dm_blocked_fail_closed",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {
        allowed: false,
        blocked: true,
        reason: "age_unknown_dm_blocked",
        requiresReview: true,
      };
    }
    // Non-DM content types: allow but always queue for review.
    return {
      allowed: true,
      blocked: false,
      reason: "age_unknown_pending_review",
      requiresReview: true,
    };
  }

  // --- Mixed adult + minor ---
  // Identify which UID is the adult and which is the minor.
  const adultUid = senderIsMinor === false ? senderUid : recipientUid;
  const minorUid = senderIsMinor === true ? senderUid : recipientUid;

  const approved = _hasApprovedRelationship(
    senderFields.safety,
    recipientFields.safety,
    senderUid,
    recipientUid
  );

  if (approved) {
    // Approved guardian/family relationship — allow all interaction types.
    return { allowed: true, blocked: false, reason: "approved_relationship", requiresReview: false };
  }

  // No approved relationship: apply per-contentType rules.
  const alertId = _alertId();
  const alertBase = {
    id: alertId,
    adultUid,
    minorUid,
    senderUid,
    recipientUid,
    contentType,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (contentType === "dm") {
    // Hard block: no DMs from strangers to minors (or from minors to adult strangers).
    await db.collection("safetyAlerts").doc(alertId).set({
      ...alertBase,
      action: "blocked",
      reason: "adult_minor_dm_no_approved_relationship",
    });

    return {
      allowed: false,
      blocked: true,
      reason: "adult_minor_dm_blocked",
      requiresReview: false,
    };
  }

  if (contentType === "sanctuary_invite") {
    // Route to the invite safety queue for human review rather than silently blocking.
    const inviteQueueId = _alertId();
    await db.collection("inviteSafetyQueue").doc(inviteQueueId).set({
      ...alertBase,
      action: "pending_invite_safety_check",
      reason: "adult_minor_sanctuary_invite_requires_review",
      status: "pending",
    });

    return {
      allowed: false,
      blocked: true,
      reason: "sanctuary_invite_routed_to_safety_review",
      requiresReview: true,
    };
  }

  if (contentType === "reply") {
    // Replies are allowed but flagged for pattern-based review.
    // Count how many recent adult→minor reply events exist to detect repetition.
    // SECURITY (H7 fix 2026-06-11): Add a time-window filter so that only
    // alerts from the last 30 days count toward the repetition threshold.
    // Without this filter, a single interaction 6 months ago could trip the
    // pattern detector and either generate false positives or — if the
    // collection grows large — cause the query to scan far too many documents.
    const replyWindowStart = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const recentReplies = await db
      .collection("safetyAlerts")
      .where("adultUid", "==", adultUid)
      .where("minorUid", "==", minorUid)
      .where("contentType", "==", "reply")
      .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(replyWindowStart))
      .orderBy("timestamp", "desc")
      .limit(10)
      .get();

    const replyCount = recentReplies.size;
    const isRepeatedPattern = replyCount >= 3;

    if (isRepeatedPattern) {
      // Persist the pattern alert.
      await db.collection("safetyAlerts").doc(alertId).set({
        ...alertBase,
        action: "allowed_flagged",
        reason: "repeated_adult_minor_reply_pattern",
        priorReplyCount: replyCount,
      });

      // Add to human moderation queue.
      await db.collection("moderationQueue").doc(alertId).set({
        type: "adult_minor_reply_pattern",
        adultUid,
        minorUid,
        senderUid,
        recipientUid,
        replyCount,
        priority: "high",
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        allowed: true,
        blocked: false,
        reason: "reply_allowed_repeated_pattern_flagged",
        requiresReview: true,
      };
    }

    // First few replies — allow without queue entry (low noise).
    return {
      allowed: true,
      blocked: false,
      reason: "reply_allowed_monitoring",
      requiresReview: false,
    };
  }

  // Unknown contentType — allow with review flag.
  return {
    allowed: true,
    blocked: false,
    reason: "unknown_content_type_pending_review",
    requiresReview: true,
  };
}

/**
 * Update the minor-protection safety fields on a user document.
 *
 * IMPORTANT: This function must only be called from a trusted Cloud Function
 * using the Firebase Admin SDK. It must never be exposed as a direct client
 * callable. The caller is responsible for verifying the calling context.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string}  uid
 * @param {boolean|null} isMinor
 * @param {"under13"|"13_15"|"16_17"|null} minorAgeBand
 * @param {"unknown"|"self_attested"|"guardian_verified"|"verified"} ageAssuranceStatus
 * @returns {Promise<void>}
 */
async function setMinorFlag(db, uid, isMinor, minorAgeBand, ageAssuranceStatus) {
  const validAgeAssuranceStatuses = ["unknown", "self_attested", "guardian_verified", "verified"];
  const validMinorAgeBands        = ["under13", "13_15", "16_17", null];

  if (!validAgeAssuranceStatuses.includes(ageAssuranceStatus)) {
    throw new Error(
      `setMinorFlag: invalid ageAssuranceStatus "${ageAssuranceStatus}". ` +
      `Must be one of: ${validAgeAssuranceStatuses.join(", ")}`
    );
  }
  if (!validMinorAgeBands.includes(minorAgeBand)) {
    throw new Error(
      `setMinorFlag: invalid minorAgeBand "${minorAgeBand}". ` +
      `Must be one of: under13, 13_15, 16_17, or null`
    );
  }

  // Default safety modes for minors are more restrictive.
  // Adults receive the standard (unrestricted) defaults.
  const dmSafetyMode        = isMinor ? "restricted"  : "disabled";
  const discoverySafetyMode = isMinor ? "limited"     : "standard";

  await db.collection("users").doc(uid).update({
    "safety.isMinor":              isMinor,
    "safety.minorAgeBand":         minorAgeBand,
    "safety.ageAssuranceStatus":   ageAssuranceStatus,
    "safety.dmSafetyMode":         dmSafetyMode,
    "safety.discoverySafetyMode":  discoverySafetyMode,
    "safety.updatedAt":            admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Determine whether a minor user's profile should be visible to a given viewer
 * in public discovery surfaces (people search, suggested friends, etc.).
 *
 * Rules:
 *   - If the target is NOT a minor: always visible.
 *   - If the target IS a minor AND the viewer is the target: visible.
 *   - If the target IS a minor AND the viewer has an approved relationship: visible.
 *   - If the target is under-13 (ageTier = "blocked"): hidden from all non-guardians.
 *   - Otherwise (minor with no relationship to viewer): discovery is limited.
 *     The minorAgeBand/discoverySafetyMode from the target's safety doc is respected:
 *       "hidden"   → not visible.
 *       "limited"  → not visible in stranger search (default for minors).
 *       "standard" → visible (only reachable if a guardian/admin explicitly set this).
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} viewerUid  UID of the user performing the search.
 * @param {string} targetUid  UID of the profile being looked up.
 * @returns {Promise<{ visible: boolean, reason: string }>}
 */
async function validateMinorDiscovery(db, viewerUid, targetUid) {
  // Self-view is always visible.
  if (viewerUid === targetUid) {
    return { visible: true, reason: "self_view" };
  }

  const [viewerFields, targetFields] = await Promise.all([
    _getUserSafetyFields(db, viewerUid),
    _getUserSafetyFields(db, targetUid),
  ]);

  const targetIsMinor = _resolveIsMinor(targetFields.safety, targetFields.ageTier);

  if (!targetIsMinor) {
    return { visible: true, reason: "target_is_adult" };
  }

  // Under-13 (ageTier = "blocked") — only visible to approved guardians.
  const isUnder13 = targetFields.ageTier === "blocked" ||
    targetFields.safety.minorAgeBand === "under13";

  const approved = _hasApprovedRelationship(
    viewerFields.safety,
    targetFields.safety,
    viewerUid,
    targetUid
  );

  if (approved) {
    return { visible: true, reason: "approved_relationship" };
  }

  if (isUnder13) {
    return { visible: false, reason: "under13_hidden_from_strangers" };
  }

  // 13-17: respect the target's discoverySafetyMode.
  const mode = targetFields.safety.discoverySafetyMode || "limited";

  if (mode === "hidden" || mode === "limited") {
    return { visible: false, reason: `minor_discovery_${mode}` };
  }

  // mode === "standard" was explicitly set by a guardian or admin.
  return { visible: true, reason: "minor_discovery_standard_allowed" };
}

/**
 * Analyse an array of message objects for grooming risk signals.
 *
 * Each message object should have the shape:
 *   { senderUid: string, isAdult: boolean, isMinorRecipient: boolean, text: string }
 *
 * Heuristic checks:
 *   a. Adult asking for photos from a minor.
 *   b. Adult requesting location from a minor.
 *   c. Adult asking to move to another platform.
 *   d. Adult requesting secrecy.
 *   e. Repeated adult-to-minor messages after no reply from the minor.
 *
 * Risk levels:
 *   "none"     — no signals detected.
 *   "low"      — 1 weak signal.
 *   "medium"   — 2 weak signals or 1 strong signal.
 *   "high"     — 3+ signals or a combination of strong signals.
 *   "critical" — pattern indicates active grooming (multiple strong signals).
 *
 * On "high" or "critical" the caller should escalate (e.g. write a safety alert,
 * notify a guardian, or block the conversation).
 *
 * @param {Array<{senderUid: string, isAdult: boolean, isMinorRecipient: boolean, text: string}>} messages
 * @returns {{ risk: "none"|"low"|"medium"|"high"|"critical", flags: string[] }}
 */
function detectGroomingRisk(messages) {
  if (!Array.isArray(messages) || messages.length === 0) {
    return { risk: "none", flags: [] };
  }

  // ---- Heuristic pattern definitions ----

  // (a) Adult asking for photos from a minor.
  const PHOTO_REQUEST = /\b(send|share|show|post|give me|dm me|text me).{0,40}(pic(s|ture)?|photo(s)?|selfie|image|video|clip)\b/i;

  // (b) Adult requesting location.
  const LOCATION_REQUEST = /\b(where (are|do) you|your (address|location|house|home|school|city|neighborhood)|what street|meet (up|me)|come (over|to my))\b/i;

  // (c) Adult asking to move to another platform.
  const OFF_PLATFORM = /\b(whatsapp|telegram|snapchat|kik|discord|text me|my number|call me|dm me on|move (to|off)|leave (this|here)|talk (on|over|via))\b/i;

  // (d) Adult requesting secrecy.
  const SECRECY_REQUEST = /\b(our (little )?secret|don('t| not) tell|between (us|you and me)|keep this (quiet|private|between us)|no one (needs to|should) know|don('t| not) (mention|say|share|show) this)\b/i;

  const activeFlags = [];
  let signalScore  = 0; // Accumulated risk weight.

  // Separate messages from adults directed at minors.
  const adultToMinorMessages = messages.filter(m => m.isAdult && m.isMinorRecipient);

  // (a) Photo request.
  const photoMsg = adultToMinorMessages.find(m => PHOTO_REQUEST.test(m.text));
  if (photoMsg) {
    activeFlags.push("adult_requesting_photos_from_minor");
    signalScore += 3; // Strong signal.
  }

  // (b) Location request.
  const locationMsg = adultToMinorMessages.find(m => LOCATION_REQUEST.test(m.text));
  if (locationMsg) {
    activeFlags.push("adult_requesting_location_from_minor");
    signalScore += 3; // Strong signal.
  }

  // (c) Off-platform solicitation.
  const offPlatformMsg = adultToMinorMessages.find(m => OFF_PLATFORM.test(m.text));
  if (offPlatformMsg) {
    activeFlags.push("adult_asking_to_move_to_another_platform");
    signalScore += 2; // Moderate-strong signal.
  }

  // (d) Secrecy request.
  const secrecyMsg = adultToMinorMessages.find(m => SECRECY_REQUEST.test(m.text));
  if (secrecyMsg) {
    activeFlags.push("adult_requesting_secrecy_from_minor");
    signalScore += 3; // Strong signal (very abnormal in stranger context).
  }

  // (e) Repeated adult messages with no minor reply (unanswered pursuit).
  // Detect runs of 5+ consecutive adult→minor messages without an intervening
  // minor reply.
  let consecutiveAdultMessages = 0;
  let maxRun = 0;
  for (const msg of messages) {
    if (msg.isAdult && msg.isMinorRecipient) {
      consecutiveAdultMessages++;
      maxRun = Math.max(maxRun, consecutiveAdultMessages);
    } else {
      consecutiveAdultMessages = 0;
    }
  }
  if (maxRun >= 5) {
    activeFlags.push("repeated_adult_to_minor_messages_no_reply");
    signalScore += maxRun >= 10 ? 3 : 1; // Strong if very persistent.
  }

  // ---- Map accumulated score to risk level ----
  let risk;
  if (signalScore === 0) {
    risk = "none";
  } else if (signalScore <= 1) {
    risk = "low";
  } else if (signalScore <= 3) {
    risk = "medium";
  } else if (signalScore <= 5) {
    risk = "high";
  } else {
    risk = "critical";
  }

  return { risk, flags: activeFlags };
}

// ---------------------------------------------------------------------------
// MODULE EXPORTS
// ---------------------------------------------------------------------------

module.exports = {
  // Primary callable functions.
  checkAdultMinorInteraction,
  setMinorFlag,
  validateMinorDiscovery,
  detectGroomingRisk,

  // Schema reference exported for documentation and consumer validation.
  USER_SAFETY_SCHEMA,
};

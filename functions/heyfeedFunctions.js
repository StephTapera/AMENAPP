/**
 * heyFeedFunctions.js
 * AMEN Cloud Functions — Hey Feed NL Intelligence Layer
 *
 * Callable:
 *   submitHeyFeedNLRequest    — parse NL text, write preferences to Firestore
 *   removeHeyFeedNLPreference — deactivate a single preference (ownership-verified)
 *   resetHeyFeedNLPreferences — deactivate all active preferences for a user
 *   parseHeyFeedIntent        — parse only, no write (live preview)
 *
 * Scheduled:
 *   expireHeyFeedNLPreferences — every 4 hours, deactivates expired prefs
 *   rebuildFeedControlState    — every 1 hour (lightweight housekeeping)
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule }          = require("firebase-functions/v2/scheduler");
const logger                   = require("firebase-functions/logger");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

// ============================================================================
// CONSTANTS
// ============================================================================

const PARSER_VERSION = 1;

const DURATION_TO_HOURS = {
  session:    3,
  today:      24,
  three_days: 72,
  seven_days: 168,
  persistent: null,
};

function expiryFromDuration(duration) {
  const hours = DURATION_TO_HOURS[duration];
  if (hours === null || hours === undefined) return null;
  const d = new Date();
  d.setHours(d.getHours() + hours);
  return d;
}

const TOPIC_SYNONYMS = {
  testimonies:          ["testimon", "miracle", "story", "stories", "what god did", "answered prayer"],
  prayer_requests:      ["prayer request", "pray for", "need prayer", "intercession"],
  bible_teaching:       ["bible teaching", "biblical", "teaching", "sermon", "devotional", "scripture"],
  practical_faith:      ["practical", "how to", "apply", "daily life", "faith in action"],
  encouragement:        ["encouragement", "uplifting", "hope", "positive", "inspiring", "uplift"],
  church_discovery:     ["church", "churches", "congregation", "ministry", "local church"],
  debate:               ["debate", "argument", "controversy", "controversial", "politics", "heated"],
  promotional_content:  ["promo", "promotional", "marketing", "advertisement", "spam", "ads"],
  grief_support:        ["grief", "loss", "grieving", "sad", "mental health", "struggle", "support"],
  worship_music:        ["worship", "music", "song", "songs", "praise", "hymn"],
  theology:             ["theology", "doctrine", "deep dive", "theological", "apologetics"],
  community:            ["community", "fellowship", "connection", "people", "relationships"],
};

const TOPIC_LABELS = {
  testimonies:          "Testimonies",
  prayer_requests:      "Prayer requests",
  bible_teaching:       "Bible teaching",
  practical_faith:      "Practical faith",
  encouragement:        "Encouragement",
  church_discovery:     "Church discovery",
  debate:               "Debates/arguments",
  promotional_content:  "Promotional content",
  grief_support:        "Grief & support",
  worship_music:        "Worship & music",
  theology:             "Theology",
  community:            "Community life",
};

// ============================================================================
// INTENT PARSER — deterministic, no API calls
// ============================================================================

function parseHeyFeedText(text) {
  const normalized = (text || "").trim().toLowerCase();
  if (!normalized) {
    return {
      action: "balance", targets: [], duration: "three_days", strength: 0.5,
      confidence: 0.10, originalText: text, requiresConfirmation: true,
      parserVersion: PARSER_VERSION,
    };
  }

  const action     = detectAction(normalized);
  const targets    = detectTargets(normalized);
  const duration   = detectDuration(normalized);
  const strength   = detectStrength(normalized);
  const confidence = computeConfidence(targets);

  return {
    action, targets, duration, strength, confidence,
    originalText: text,
    requiresConfirmation: confidence < 0.55 || targets.length === 0,
    parserVersion: PARSER_VERSION,
  };
}

function detectAction(text) {
  const mute     = ["no more", "stop showing", "hide", "never show", "sick of", "tired of",
                    "enough of", "dont show", "don't show", "remove all"];
  const decrease = ["less", "fewer", "reduce", "cut back", "not as much", "avoid", "limit",
                    "see less", "show less", "deprioritize"];
  const increase = ["more", "show me more", "give me more", "see more", "want more",
                    "increase", "prioritize", "boost", "surface more"];
  const explore  = ["explore", "discover", "try new", "something new", "variety",
                    "different", "broaden", "mix it up"];
  const balance  = ["balance", "reset", "rebalance", "neutral", "normal",
                    "go back", "default", "clear"];

  if (mute.some(w => text.includes(w)))     return "mute";
  if (decrease.some(w => text.includes(w))) return "decrease";
  if (increase.some(w => text.includes(w))) return "increase";
  if (explore.some(w => text.includes(w)))  return "explore";
  if (balance.some(w => text.includes(w)))  return "balance";
  return "increase";
}

function detectTargets(text) {
  const found = [];
  for (const [topicId, keywords] of Object.entries(TOPIC_SYNONYMS)) {
    const matches = keywords.filter(kw => text.includes(kw)).length;
    if (matches > 0) {
      const conf = Math.min(1.0, matches * 0.4 + 0.55);
      found.push({ id: topicId, type: "topic", label: TOPIC_LABELS[topicId] || topicId, confidence: conf });
    }
  }
  if (["people i follow", "followed accounts", "accounts i follow"].some(p => text.includes(p))) {
    found.push({ id: "relationship_followed", type: "relationship", label: "People you follow", confidence: 0.92 });
  }
  if (["nearby", "near me", "local", "my area"].some(p => text.includes(p))) {
    found.push({ id: "local_relevance", type: "locality", label: "Local content", confidence: 0.88 });
  }
  if (["repetitive", "same thing", "already seen"].some(p => text.includes(p))) {
    found.push({ id: "repetition", type: "format", label: "Repetitive content", confidence: 0.90 });
  }
  if (["intense", "heavy", "lighter", "calmer"].some(p => text.includes(p))) {
    found.push({ id: "intensity", type: "intensity", label: "Intense/heavy content", confidence: 0.85 });
  }
  return found;
}

function detectDuration(text) {
  if (["tonight", "right now", "just now"].some(p => text.includes(p)))                          return "session";
  if (["today", "this afternoon", "this morning"].some(p => text.includes(p)))                   return "today";
  if (["this week", "week", "7 days"].some(p => text.includes(p)))                               return "seven_days";
  if (["3 days", "three days", "for a bit"].some(p => text.includes(p)))                         return "three_days";
  if (["always", "from now on", "permanently"].some(p => text.includes(p)))                      return "persistent";
  return "three_days";
}

function detectStrength(text) {
  const strong   = ["a lot", "much more", "mostly", "really", "way more", "definitely", "absolutely"];
  const moderate = ["some", "a bit", "somewhat", "kind of", "occasionally", "sometimes"];
  const soft     = ["tiny bit", "slightly", "just a touch", "barely"];
  if (strong.some(w => text.includes(w)))   return 0.90;
  if (moderate.some(w => text.includes(w))) return 0.55;
  if (soft.some(w => text.includes(w)))     return 0.30;
  return 0.70;
}

function computeConfidence(targets) {
  if (targets.length === 0) return 0.20;
  const avg = targets.reduce((sum, t) => sum + t.confidence, 0) / targets.length;
  return Math.min(0.97, avg + Math.min(0.15, (targets.length - 1) * 0.08));
}

// ============================================================================
// CALLABLE FUNCTIONS
// ============================================================================

const submitHeyFeedNLRequest = onCall(
  { enforceAppCheck: true }, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  async (request) => {
    const db = getFirestore();
    const userId = request.auth && request.auth.uid;
    if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

    const text = String((request.data && request.data.text) || "").trim();
    if (!text || text.length < 2) throw new HttpsError("invalid-argument", "Text is required.");
    if (text.length > 500)        throw new HttpsError("invalid-argument", "Text too long (500 char max).");

    const intent = parseHeyFeedText(text);
    if (intent.targets.length === 0) return { ok: false, intent, created: [] };

    const batch   = db.batch();
    const created = [];
    const now     = Timestamp.now();

    for (const target of intent.targets) {
      const prefId = `${userId}_${target.id}_${Date.now()}`;
      const ref = db.collection("users").doc(userId)
        .collection("feedNLPreferences").doc(prefId);

      const expiryDate = expiryFromDuration(intent.duration);
      batch.set(ref, {
        id: prefId,
        userId,
        action:      intent.action,
        targetId:    target.id,
        targetLabel: target.label,
        targetType:  target.type,
        strength:    Math.round(intent.strength * target.confidence * 100) / 100,
        duration:    intent.duration,
        source:      "nl_input",
        isActive:    true,
        isPaused:    false,
        createdAt:   now,
        expiresAt:   expiryDate ? Timestamp.fromDate(expiryDate) : null,
      });
      created.push(prefId);
    }

    // Audit entry
    batch.set(db.collection("users").doc(userId).collection("feedAuditEvents").doc(), {
      type:         "nl_preference_created",
      originalText: text,
      intent:       { action: intent.action, confidence: intent.confidence, duration: intent.duration },
      targetCount:  intent.targets.length,
      createdAt:    now,
    });

    await batch.commit();
    logger.info(`Hey Feed: created ${created.length} prefs for ${userId}`);
    return { ok: true, intent, created };
  }
);

const removeHeyFeedNLPreference = onCall(
  { enforceAppCheck: true }, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  async (request) => {
    const db = getFirestore();
    const userId = request.auth && request.auth.uid;
    if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

    const preferenceId = String((request.data && request.data.preferenceId) || "").trim();
    if (!preferenceId) throw new HttpsError("invalid-argument", "preferenceId required.");

    const ref = db.collection("users").doc(userId)
      .collection("feedNLPreferences").doc(preferenceId);
    const doc = await ref.get();

    if (!doc.exists)                      throw new HttpsError("not-found",          "Preference not found.");
    if (doc.data().userId !== userId)     throw new HttpsError("permission-denied",  "Not your preference.");

    await ref.update({ isActive: false });
    return { ok: true };
  }
);

const resetHeyFeedNLPreferences = onCall(
  { enforceAppCheck: true }, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  async (request) => {
    const db = getFirestore();
    const userId = request.auth && request.auth.uid;
    if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

    const snap = await db.collection("users").doc(userId)
      .collection("feedNLPreferences")
      .where("isActive", "==", true)
      .get();

    if (snap.empty) return { ok: true, cleared: 0 };

    const batch = db.batch();
    snap.docs.forEach(doc => batch.update(doc.ref, { isActive: false }));
    await batch.commit();
    return { ok: true, cleared: snap.size };
  }
);

const parseHeyFeedIntent = onCall(
  { enforceAppCheck: true }, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  async (request) => {
    const userId = request.auth && request.auth.uid;
    if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

    const text = String((request.data && request.data.text) || "").trim();
    if (!text) throw new HttpsError("invalid-argument", "Text required.");

    return { ok: true, intent: parseHeyFeedText(text) };
  }
);

// ============================================================================
// SCHEDULED FUNCTIONS
// ============================================================================

const expireHeyFeedNLPreferences = onSchedule(
  { schedule: "every 4 hours", timeZone: "America/New_York" },
  async () => {
    const db  = getFirestore();
    const now = Timestamp.now();
    logger.info("Hey Feed: running NL preference expiry...");

    const snap = await db.collectionGroup("feedNLPreferences")
      .where("isActive",  "==", true)
      .where("expiresAt", "<=", now)
      .limit(500)
      .get();

    if (snap.empty) { logger.info("Hey Feed: no expired preferences."); return; }

    const batch = db.batch();
    snap.docs.forEach(doc => batch.update(doc.ref, { isActive: false }));
    await batch.commit();
    logger.info(`Hey Feed: expired ${snap.size} NL preferences.`);
  }
);

const rebuildFeedControlState = onSchedule(
  { schedule: "every 1 hours", timeZone: "America/New_York" },
  async () => {
    logger.info("Hey Feed: feed control state rebuild (client-driven).");
  }
);

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  submitHeyFeedNLRequest,
  removeHeyFeedNLPreference,
  resetHeyFeedNLPreferences,
  parseHeyFeedIntent,
  expireHeyFeedNLPreferences,
  rebuildFeedControlState,
};

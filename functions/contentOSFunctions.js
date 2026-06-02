/**
 * contentOSFunctions.js
 * AMEN — ContentOS: Content Discussion, Approval & Forwarding
 *
 * Callable: routeContentAction
 *   In:  { card: ContentCard }
 *   Out: { suggestions: ContentRouteSuggestion[] }
 *
 * Returns ordered action suggestions based on audience, source type, and
 * content flags. Falls back gracefully — the iOS client has local rules
 * and will never surface an empty state.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");

const db = getFirestore();

// ── routeContentAction ────────────────────────────────────────────────────────

exports.routeContentAction = onCall({ enforceAppCheck: false }, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { card } = request.data ?? {};
  if (!card || !card.id || !card.sourceType) {
    throw new HttpsError("invalid-argument", "card.id and card.sourceType are required.");
  }

  const suggestions = buildSuggestions(card, userId);

  // Audit the routing call (non-blocking, best-effort)
  logRoutingAudit(card, userId, suggestions).catch(() => {});

  return { suggestions };
});

// ── Suggestion builder ────────────────────────────────────────────────────────

function buildSuggestions(card, userId) {
  const isAnonymous   = card.isAnonymous   === true;
  const isDM          = card.isDM          === true;
  const isPaid        = card.isPaidContent === true;
  const hasPrayer     = card.hasPrayerContent === true;
  const sourceType    = card.sourceType ?? "post";
  const audience      = card.originalAudience ?? "spaceMembers";
  const sensitivity   = card.sensitivityScore ?? 0;

  // Safety hard-stops: no suggestions at all
  if (isDM || isAnonymous) return [];

  const suggestions = [];

  // Prayer content → prayer room first
  if (hasPrayer || sourceType === "prayer_request") {
    suggestions.push({
      id:         "prayer_room",
      action:     "createPrayerRoom",
      label:      "Start a Prayer Room",
      rationale:  "Open a live prayer circle around this request",
      confidence: 0.92,
    });
  }

  // Testimony / Bible study → study group
  if (sourceType === "testimony" || sourceType === "scripture") {
    suggestions.push({
      id:         "study",
      action:     "createStudy",
      label:      "Turn into a Study",
      rationale:  "Start a Bible study discussion from this content",
      confidence: 0.88,
    });
  }

  // Public or space-scoped → discuss in space
  if (audience === "spaceMembers" || audience === "publicFeed" || audience === "churchMembers") {
    suggestions.push({
      id:         "discuss_space",
      action:     "discussInSpace",
      label:      "Discuss in This Space",
      rationale:  "Open a room for members to dig deeper",
      confidence: 0.85,
    });
  }

  // Paid content: don't suggest external sharing
  if (!isPaid && sensitivity < 0.5) {
    suggestions.push({
      id:         "discuss_connect",
      action:     "discussInConnect",
      label:      "Share to Amen Connect",
      rationale:  "Bring this conversation to a wider audience",
      confidence: 0.70,
    });
  }

  // Church notes save — always available except for DMs (already guarded above)
  suggestions.push({
    id:         "church_notes",
    action:     "saveToChurchNotes",
    label:      "Save to Church Notes",
    rationale:  "Archive this for future reference or study prep",
    confidence: 0.65,
  });

  // Cap at 3 top suggestions by confidence
  suggestions.sort((a, b) => b.confidence - a.confidence);
  return suggestions.slice(0, 3);
}

// ── Audit log (best-effort, non-blocking) ────────────────────────────────────

async function logRoutingAudit(card, userId, suggestions) {
  await db.collection("contentAuditLog").add({
    eventType:   "route_requested",
    actorId:     userId,
    cardId:      card.id,
    sourceType:  card.sourceType,
    audience:    card.originalAudience ?? null,
    suggestions: suggestions.map((s) => s.action),
    createdAt:   Timestamp.now(),
  });
}

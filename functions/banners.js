/**
 * banners.js
 * AMEN App — Selah Banner Rail Cloud Functions
 *
 * Architecture invariants (non-negotiable):
 *   - Client NEVER reads bannerSources directly.
 *   - Server resolves eligibility, ranking, visibility, and CTA validity.
 *   - moderationStatus + safety fields are written ONLY via Admin SDK.
 *   - rankingReason reflects the actual dominant signal; never fabricated.
 *   - Size waterfall: user pref → space default → surface default → standard.
 *   - Every CTA route validated as a well-formed selah:// URI before returning.
 *
 * Exported callables:
 *   resolveBannerRail                   — load ranked banners for a surface
 *   logAmenSpaceBannerEvent             — analytics event sink
 *   validateAmenSpaceBannerCTA          — CTA still valid? (approved, not expired)
 *   setAmenSpaceBannerDisplayPreference — save user's preferred size for a surface
 *   setAmenSpaceDefaultBannerSize       — space admin sets default size
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

// ─── Constants ────────────────────────────────────────────────────────────────

const REGION = "us-central1";

const VALID_SURFACES = new Set([
  "spacesHome", "spaceDetail", "churchProfile", "schoolProfile", "businessProfile",
  "discovery", "events", "jobs", "messagesRooms", "bereanSuggestions", "homeFeed", "userProfile",
]);

const VALID_SIZES = new Set(["compact", "standard", "large", "hero"]);

const VALID_CTA_ACTIONS = new Set(["join", "rsvp", "apply", "open", "pray", "watch"]);

const VALID_EVENTS = new Set([
  "banner_impression", "banner_tap", "banner_dismiss",
  "banner_cta_complete", "banner_hidden_reason",
]);

// Surface defaults mirror AmenSpaceBannerSurface.defaultSize in Swift.
const SURFACE_DEFAULTS = {
  spaceDetail: "large", churchProfile: "large", schoolProfile: "large", businessProfile: "large",
  homeFeed: "compact",
};
function surfaceDefault(surface) {
  return SURFACE_DEFAULTS[surface] || "standard";
}

// ─── Auth / App Check guards ──────────────────────────────────────────────────

function assertAuth(request, label) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", `${label}: authentication required`);
  }
}

function warnIfNoAppCheck(request, label) {
  if (!request.app) {
    console.warn(`[banners] ${label}: App Check token absent — expected in production`);
  }
}

// ─── Selah URI validation ─────────────────────────────────────────────────────

/**
 * Returns true iff `route` is a structurally valid selah:// URI for `ctaAction`.
 * Mirrors AmenSpaceBannerRoute.init?(route:cta:) in Swift exactly.
 */
function isValidSelahRoute(route, ctaAction) {
  if (typeof route !== "string" || !route.startsWith("selah://")) return false;
  try {
    const url = new URL(route);
    if (url.protocol !== "selah:") return false;
    const host = url.hostname;
    const parts = url.pathname.split("/").filter(Boolean);
    const id = parts[0];
    if (!id || !/^[\w-]+$/.test(id)) return false;
    if (url.search || url.hash) return false;
    switch (ctaAction) {
      case "join":  return host === "group"  && parts.length === 1;
      case "rsvp":  return host === "event"  && parts.length === 2 && parts[1] === "rsvp";
      case "apply": return host === "job"    && parts.length === 2 && parts[1] === "apply";
      case "open":  return host === "space"  && parts.length === 1;
      case "pray":  return host === "prayer" && parts.length === 1;
      case "watch": return host === "sermon" && parts.length === 1;
      default:      return false;
    }
  } catch {
    return false;
  }
}

// ─── User context ─────────────────────────────────────────────────────────────

async function loadUserContext(uid) {
  const db = admin.firestore();
  const [membershipSnap, prefSnap, userSnap] = await Promise.allSettled([
    db.collection("users").doc(uid).collection("memberships").limit(80).get(),
    db.collection("bannerDisplayPreferences").doc(uid).get(),
    db.collection("users").doc(uid).get(),
  ]);

  const memberships = membershipSnap.status === "fulfilled"
    ? membershipSnap.value.docs.map((d) => d.id)
    : [];

  const bannerPreferences = prefSnap.status === "fulfilled" && prefSnap.value.exists
    ? prefSnap.value.data()
    : {};

  const userData = userSnap.status === "fulfilled" && userSnap.value.exists
    ? userSnap.value.data()
    : {};

  return {
    memberships,
    bannerPreferences,
    interests: Array.isArray(userData.interests) ? userData.interests : [],
    following: Array.isArray(userData.following) ? userData.following : [],
    location: userData.location || null,
  };
}

// ─── Candidate fetch ──────────────────────────────────────────────────────────

async function fetchCandidates(surface) {
  const db = admin.firestore();
  const now = admin.firestore.Timestamp.now();

  // All server-side filters — client sees NONE of this logic.
  const snap = await db.collection("bannerSources")
    .where("moderationStatus", "==", "approved")
    .where("visibility", "in", ["public", "authenticated"])
    .where("surfaces", "array-contains", surface)
    .where("endsAt", ">", now)
    .orderBy("endsAt")
    .orderBy("priority", "desc")
    .limit(40)
    .get();

  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

// ─── Ranking ──────────────────────────────────────────────────────────────────

/**
 * Derives the dominant ranking signal from actual data — never fabricated.
 * Mirrors the client-side eyebrow label intent but is authoritative.
 */
function dominantRankingReason(banner, userCtx) {
  if (banner.spaceId && userCtx.memberships.includes(banner.spaceId)) return "member";
  if (banner.createdBy && userCtx.following.includes(banner.createdBy)) return "following";
  const bannerTopics = Array.isArray(banner.topics) ? banner.topics : [];
  if (bannerTopics.some((t) => userCtx.interests.includes(t))) return "interest_match";
  if (banner.location && userCtx.location && banner.location === userCtx.location) return "near_you";
  return "featured";
}

function scoreItem(banner, userCtx) {
  let score = typeof banner.priority === "number" ? banner.priority : 0;
  if (banner.spaceId && userCtx.memberships.includes(banner.spaceId)) score += 30;
  if (banner.createdBy && userCtx.following.includes(banner.createdBy)) score += 20;
  if (banner.location && userCtx.location && banner.location === userCtx.location) score += 15;
  const topics = Array.isArray(banner.topics) ? banner.topics : [];
  if (topics.some((t) => userCtx.interests.includes(t))) score += 10;
  return score;
}

// ─── Size waterfall ───────────────────────────────────────────────────────────

async function resolveDisplaySize(db, uid, spaceId, surface, surfaceDefaultOverride) {
  // 1. User preference (stored in bannerDisplayPreferences/{uid}[surface])
  const prefSnap = await db.collection("bannerDisplayPreferences").doc(uid).get();
  if (prefSnap.exists) {
    const pref = prefSnap.data()[surface];
    if (VALID_SIZES.has(pref)) return pref;
  }

  // 2. Space default (stored in amenSpaces/{id}/settings/bannerDisplay.defaultBannerSize)
  if (spaceId) {
    const spaceSettingSnap = await db
      .collection("amenSpaces").doc(spaceId)
      .collection("settings").doc("bannerDisplay")
      .get();
    if (spaceSettingSnap.exists) {
      const spaceDefault = spaceSettingSnap.data().defaultBannerSize;
      if (VALID_SIZES.has(spaceDefault)) return spaceDefault;
    }
  }

  // 3. Surface default passed from the client (mirrors AmenSpaceBannerSurface.defaultSize)
  if (surfaceDefaultOverride && VALID_SIZES.has(surfaceDefaultOverride)) {
    return surfaceDefaultOverride;
  }

  // 4. Standard fallback
  return surfaceDefault(surface);
}

// ─── resolveBannerRail ────────────────────────────────────────────────────────

exports.resolveBannerRail = onCall({ region: REGION }, async (request) => {
  assertAuth(request, "resolveBannerRail");
  warnIfNoAppCheck(request, "resolveBannerRail");

  const { surface, spaceId, surfaceDefaultSize } = request.data || {};

  if (!surface || !VALID_SURFACES.has(surface)) {
    throw new HttpsError("invalid-argument", "resolveBannerRail: invalid or missing surface");
  }

  const uid = request.auth.uid;
  const db = admin.firestore();
  const now = Date.now() / 1000;

  const [userCtx, candidates, resolvedSize] = await Promise.all([
    loadUserContext(uid),
    fetchCandidates(surface),
    resolveDisplaySize(db, uid, spaceId || null, surface, surfaceDefaultSize || null),
  ]);

  // Filter: startsAt not yet reached, route is a valid selah:// URI
  const valid = candidates.filter((b) => {
    if (b.startsAt && b.startsAt.seconds > now) return false;
    const ctaAction = (b.cta && b.cta.action) || b.ctaAction || "open";
    const route = (b.cta && b.cta.route) || b.targetRoute || "";
    if (!isValidSelahRoute(route, ctaAction)) {
      console.log(`[resolveBannerRail] filtered bannerId=${b.id}: unresolvable route "${route}" for action "${ctaAction}"`);
      return false;
    }
    return true;
  });

  // Rank then deduplicate by route
  const seenRoutes = new Set();
  const ranked = valid
    .map((b) => ({ ...b, _score: scoreItem(b, userCtx) }))
    .sort((a, b) => b._score - a._score)
    .filter((b) => {
      const route = (b.cta && b.cta.route) || b.targetRoute || "";
      if (seenRoutes.has(route)) return false;
      seenRoutes.add(route);
      return true;
    })
    .slice(0, 8);

  const banners = ranked.map((b, i) => {
    const ctaAction = (b.cta && b.cta.action) || b.ctaAction || "open";
    const ctaLabel  = (b.cta && b.cta.label)  || b.ctaLabel  || "Open";
    const route     = (b.cta && b.cta.route)  || b.targetRoute || "";
    const reason    = dominantRankingReason(b, userCtx);

    return {
      id:               b.id,
      sourceId:         b.id,
      type:             b.type || "announcement",
      title:            b.title || "",
      subtitle:         b.subtitle || "",
      imageURL:         b.imageURL || null,
      iconURL:          b.iconURL  || null,
      spaceId:          b.spaceId  || null,
      targetRoute:      route,
      cta:              { action: ctaAction, label: ctaLabel, route },
      ctaLabel,
      priority:         typeof b.priority === "number" ? b.priority : 0,
      startsAt:         b.startsAt ? b.startsAt.seconds : null,
      endsAt:           b.endsAt   ? b.endsAt.seconds   : null,
      location:         b.location    || null,
      // moderationStatus / safety fields are NEVER returned from this endpoint.
      // The client contract requires these fields to be absent.
      rankingReason:    reason,
      resolvedSize,
      rank:             i,
      score:            b._score,
    };
  });

  return { banners, resolvedSize, surface };
});

// ─── logAmenSpaceBannerEvent ──────────────────────────────────────────────────

exports.logAmenSpaceBannerEvent = onCall({ region: REGION }, async (request) => {
  assertAuth(request, "logAmenSpaceBannerEvent");

  const {
    bannerId, sourceId, surface, spaceId, route, targetRoute,
    resolvedSize, ctaAction, ctaLabel, eventName, rank, detail, reason, stage,
  } = request.data || {};

  if (!bannerId || typeof bannerId !== "string") {
    throw new HttpsError("invalid-argument", "logAmenSpaceBannerEvent: bannerId required");
  }
  if (!eventName || !VALID_EVENTS.has(eventName)) {
    throw new HttpsError("invalid-argument", `logAmenSpaceBannerEvent: unknown event "${eventName}"`);
  }

  const db = admin.firestore();
  await db.collection("amenSpaceBannerAnalytics").add({
    bannerId,
    sourceId:     sourceId     || bannerId,
    surface:      surface      || "",
    spaceId:      spaceId      || "",
    route:        route        || targetRoute || "",
    targetRoute:  targetRoute  || route       || "",
    resolvedSize: resolvedSize || "standard",
    ctaAction:    ctaAction    || "",
    ctaLabel:     ctaLabel     || "",
    eventName,
    rank:         typeof rank === "number" ? rank : 0,
    detail:       detail  || null,
    reason:       reason  || null,
    stage:        stage   || null,
    userId:       request.auth.uid,
    createdAt:    admin.firestore.FieldValue.serverTimestamp(),
  });

  return { ok: true };
});

// ─── validateAmenSpaceBannerCTA ───────────────────────────────────────────────

exports.validateAmenSpaceBannerCTA = onCall({ region: REGION }, async (request) => {
  assertAuth(request, "validateAmenSpaceBannerCTA");

  const { bannerId, route, targetRoute, ctaAction } = request.data || {};
  const resolvedRoute  = route || targetRoute || "";
  const resolvedAction = ctaAction || "open";

  if (!bannerId || typeof bannerId !== "string") {
    throw new HttpsError("invalid-argument", "validateAmenSpaceBannerCTA: bannerId required");
  }

  if (!isValidSelahRoute(resolvedRoute, resolvedAction)) {
    throw new HttpsError(
      "failed-precondition",
      `validateAmenSpaceBannerCTA: "${resolvedRoute}" is not a valid selah:// URI for action "${resolvedAction}"`
    );
  }

  const db = admin.firestore();
  const snap = await db.collection("bannerSources").doc(bannerId).get();

  if (!snap.exists) {
    throw new HttpsError("not-found", "validateAmenSpaceBannerCTA: banner source not found");
  }

  const data = snap.data();

  if (data.moderationStatus !== "approved") {
    throw new HttpsError("permission-denied", "validateAmenSpaceBannerCTA: banner is not approved");
  }
  if (data.endsAt && data.endsAt.toMillis() < Date.now()) {
    throw new HttpsError("failed-precondition", "validateAmenSpaceBannerCTA: banner has expired");
  }

  return { route: resolvedRoute, targetRoute: resolvedRoute, valid: true };
});

// ─── setAmenSpaceBannerDisplayPreference ─────────────────────────────────────

exports.setAmenSpaceBannerDisplayPreference = onCall({ region: REGION }, async (request) => {
  assertAuth(request, "setAmenSpaceBannerDisplayPreference");

  const { surface, bannerSize } = request.data || {};

  if (!surface || !VALID_SURFACES.has(surface)) {
    throw new HttpsError("invalid-argument", "setAmenSpaceBannerDisplayPreference: invalid surface");
  }
  if (!bannerSize || !VALID_SIZES.has(bannerSize)) {
    throw new HttpsError("invalid-argument", "setAmenSpaceBannerDisplayPreference: invalid bannerSize");
  }

  const db = admin.firestore();
  await db.collection("bannerDisplayPreferences").doc(request.auth.uid).set(
    { [surface]: bannerSize, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );

  return { ok: true };
});

// ─── setAmenSpaceDefaultBannerSize ────────────────────────────────────────────

exports.setAmenSpaceDefaultBannerSize = onCall({ region: REGION }, async (request) => {
  assertAuth(request, "setAmenSpaceDefaultBannerSize");

  const { spaceId, defaultBannerSize } = request.data || {};

  if (!spaceId || typeof spaceId !== "string" || !spaceId.trim()) {
    throw new HttpsError("invalid-argument", "setAmenSpaceDefaultBannerSize: spaceId required");
  }
  if (!defaultBannerSize || !VALID_SIZES.has(defaultBannerSize)) {
    throw new HttpsError("invalid-argument", "setAmenSpaceDefaultBannerSize: invalid defaultBannerSize");
  }

  // Caller must be space admin or owner — no client can self-elevate.
  const db = admin.firestore();
  const memberSnap = await db
    .collection("amenSpaces").doc(spaceId)
    .collection("members").doc(request.auth.uid)
    .get();

  if (!memberSnap.exists || !["admin", "owner"].includes(memberSnap.data().role)) {
    throw new HttpsError("permission-denied", "setAmenSpaceDefaultBannerSize: must be space admin or owner");
  }

  await db.collection("amenSpaces").doc(spaceId)
    .collection("settings").doc("bannerDisplay")
    .set(
      {
        defaultBannerSize,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.auth.uid,
      },
      { merge: true }
    );

  return { ok: true };
});

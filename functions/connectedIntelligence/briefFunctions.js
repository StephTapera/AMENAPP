/**
 * briefFunctions.js — AMEN Connected Intelligence v1, Daily Brief backend
 *
 * OWNER: Agent B (Daily Brief). Single backend module for the pull-based Daily Brief.
 *
 * generateDailyBrief — onCallV2 callable. Assembles ContextItems for the requesting
 * user, respecting:
 *   - per-surface connector grants (GrantSurface.daily_brief MUST be present),
 *   - minor mode (Amen-native items ONLY — zero connector data),
 *   - Sabbath (rest-framing card; safety surfaces still reachable),
 *   - the hard 9-item cap (config.brief.maxItems),
 *   - crisis context (BYPASSES Sabbath + caps),
 * then summarizes via callModel({ task: 'daily_brief' }) and caches the BriefCard at
 * users/{uid}/briefCache/{date}.
 *
 * NEVER a push notification — pull-only (config.brief.pushEnabled === false). This
 * module exposes no scheduled/push trigger.
 *
 * Patterns mirrored from functions/v2functions.js: onCallV2 + requireBereanAuth +
 * enforceRateLimit. callModel + amenRouting.config's real `daily_brief` task key is
 * reused (no fictional callModelDailyBrief / buildDailyIntelligenceBriefs).
 *
 * TONE CONTRACT: matter-of-fact warmth. BANNED strings ("you missed", "streak",
 * "X days since") are stripped server-side as a defense-in-depth guard — zero guilt
 * framing ever reaches the card.
 */

"use strict";

const admin = require("firebase-admin");
const { onCall } = require("firebase-functions/v2/https");
const { HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const { enforceRateLimit } = require("../rateLimiter");
const { callModel } = require("../router/callModel");
const { isShabbatActiveForUser } = require("../shabbatMiddleware");

// Secrets used by the daily_brief route chain (gemini → openai).
const BRIEF_GEMINI_KEY = defineSecret("GEMINI_API_KEY");
const BRIEF_OPENAI_KEY = defineSecret("OPENAI_API_KEY");
const BRIEF_NVIDIA_KEY = defineSecret("NVIDIA_API_KEY"); // daily_brief has outputGuard

// ── CONTRACT MIRRORS ──────────────────────────────────────────────────────────
// Mirror only the literal enum/config values needed server-side. The TS contract
// (src/features/connectedIntelligence.contracts.ts) remains the source of truth.

const MAX_ITEMS_TOTAL = 9; // BriefCard.maxItemsTotal — hard, contract-level cap.
const GENERATE_AFTER_LOCAL_HOUR = 5; // config.brief.generateAfterLocalHour.

const GRANT_SURFACE_DAILY_BRIEF = "daily_brief";

const BRIEF_SECTION = Object.freeze({
  events: "events",
  messages_needing_attention: "messages_needing_attention",
  prayer_updates: "prayer_updates",
  saved_verse: "saved_verse",
  follow_ups: "follow_ups",
  community: "community",
});

// Which sections may be sourced from a connector (vs. Amen-native).
// Minor mode and absent grants both drop these entirely.
const CONNECTOR_BACKED_SECTIONS = new Set([BRIEF_SECTION.events]);

// Section render order (matter-of-fact: safety-adjacent and people first).
const SECTION_ORDER = [
  BRIEF_SECTION.prayer_updates,
  BRIEF_SECTION.messages_needing_attention,
  BRIEF_SECTION.events,
  BRIEF_SECTION.community,
  BRIEF_SECTION.follow_ups,
  BRIEF_SECTION.saved_verse,
];

// Guilt-framing guard. Defense-in-depth — these substrings must never ship.
const BANNED_FRAGMENTS = [
  /you missed/gi,
  /\bstreak\b/gi,
  /\b\d+\s+days?\s+since\b/gi,
];

// ── AUTH HELPER (mirrors v2functions.requireBereanAuth) ─────────────────────────

function requireBereanAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

const db = () => admin.firestore();

// ── DATE / LOCAL-HOUR HELPERS ───────────────────────────────────────────────────

/** YYYY-MM-DD in the user's timezone (defaults to UTC). */
function localDateString(timezone) {
  try {
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone || "UTC",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(new Date());
  } catch (_) {
    return new Date().toISOString().slice(0, 10);
  }
}

/** Local hour 0–23 in the user's timezone. */
function localHour(timezone) {
  try {
    const h = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone || "UTC",
      hour: "numeric",
      hour12: false,
    }).format(new Date());
    return parseInt(h, 10) % 24;
  } catch (_) {
    return new Date().getUTCHours();
  }
}

// ── BANNED-FRAGMENT GUARD ────────────────────────────────────────────────────────

function stripGuiltFraming(text) {
  if (typeof text !== "string") return text;
  let out = text;
  for (const re of BANNED_FRAGMENTS) out = out.replace(re, "");
  // Collapse any double spaces left behind.
  return out.replace(/\s{2,}/g, " ").trim();
}

// ── GRANT RESOLUTION ─────────────────────────────────────────────────────────────

/**
 * Returns the set of ConnectorId values whose active grant includes the
 * daily_brief surface. Minor accounts always get an empty set (connector data
 * is forbidden in minor mode).
 */
async function resolveDailyBriefGrants(uid, minorMode) {
  if (minorMode) return new Set();

  try {
    const snap = await db()
      .collection("users").doc(uid)
      .collection("connectorGrants")
      .where("status", "==", "active")
      .get();

    const granted = new Set();
    snap.forEach((d) => {
      const g = d.data() || {};
      const surfaces = Array.isArray(g.surfaces) ? g.surfaces : [];
      if (g.minorBlocked === true && minorMode) return; // schema assertion, belt-and-braces
      if (surfaces.includes(GRANT_SURFACE_DAILY_BRIEF) && g.connectorId) {
        granted.add(g.connectorId);
      }
    });
    return granted;
  } catch (err) {
    // Fail closed on grants: no grant proof ⇒ no connector data (section absent).
    logger.warn("generateDailyBrief: grant lookup failed — treating as no grants", {
      uid, error: err.message,
    });
    return new Set();
  }
}

// ── CONTEXT-ITEM BUILDERS ────────────────────────────────────────────────────────
// Each returns ContextItem[] with a pointer back to source. Amen-native sources
// read first-party Firestore only; connector sources are gated by grants upstream.

function nativeItem(section, payload, pointer) {
  return {
    source: "amen_native",
    provenance: { sources: [], truthLevel: "grounded" },
    surface: GRANT_SURFACE_DAILY_BRIEF,
    fetchedAt: admin.firestore.Timestamp.now(),
    summaryOnly: true,
    payload: stripGuiltFraming(payload),
    pointer: pointer ?? null,
    _section: section, // internal grouping key; stripped before persist
  };
}

function connectorItem(section, connectorId, payload, pointer) {
  return {
    source: connectorId,
    provenance: { sources: [], truthLevel: "grounded" },
    surface: GRANT_SURFACE_DAILY_BRIEF,
    fetchedAt: admin.firestore.Timestamp.now(),
    summaryOnly: true, // raw third-party content never persists — summary + pointer only
    payload: stripGuiltFraming(payload),
    pointer: pointer ?? null,
    _section: section,
  };
}

/** Events from joined spaces (Amen-native — always allowed, incl. minor mode). */
async function fetchSpaceEvents(uid) {
  try {
    const memberSnap = await db()
      .collectionGroup("members")
      .where("uid", "==", uid)
      .limit(20)
      .get();

    const spaceIds = [];
    memberSnap.forEach((m) => {
      const parent = m.ref.parent?.parent;
      if (parent?.id) spaceIds.push(parent.id);
    });
    if (spaceIds.length === 0) return [];

    const items = [];
    const now = admin.firestore.Timestamp.now();
    for (const spaceId of spaceIds.slice(0, 5)) {
      const evSnap = await db()
        .collection("spaces").doc(spaceId)
        .collection("events")
        .where("startsAt", ">=", now)
        .orderBy("startsAt", "asc")
        .limit(2)
        .get();
      evSnap.forEach((e) => {
        const ev = e.data() || {};
        items.push(nativeItem(
          BRIEF_SECTION.events,
          ev.title ? `Upcoming in your space: ${ev.title}` : "An upcoming event in one of your spaces",
          `amen://spaces/${spaceId}/events/${e.id}`,
        ));
      });
    }
    return items;
  } catch (err) {
    logger.warn("generateDailyBrief: space events fetch failed", { uid, error: err.message });
    return [];
  }
}

/** Saved verse (Amen-native — always allowed, incl. minor mode). */
async function fetchSavedVerse(uid) {
  try {
    const snap = await db()
      .collection("users").doc(uid)
      .collection("savedVerses")
      .orderBy("savedAt", "desc")
      .limit(1)
      .get();
    if (snap.empty) return [];
    const v = snap.docs[0].data() || {};
    const ref = v.reference || v.ref || "A verse you saved";
    return [nativeItem(
      BRIEF_SECTION.saved_verse,
      v.text ? `${ref} — “${v.text}”` : `${ref} is here when you want to return to it.`,
      v.reference ? `amen://bible/${encodeURIComponent(v.reference)}` : null,
    )];
  } catch (err) {
    logger.warn("generateDailyBrief: saved verse fetch failed", { uid, error: err.message });
    return [];
  }
}

/** Group / community activity (Amen-native — always allowed, incl. minor mode). */
async function fetchCommunityActivity(uid) {
  try {
    const snap = await db()
      .collection("users").doc(uid)
      .collection("groupActivity")
      .orderBy("updatedAt", "desc")
      .limit(2)
      .get();
    const items = [];
    snap.forEach((d) => {
      const a = d.data() || {};
      items.push(nativeItem(
        BRIEF_SECTION.community,
        a.summary || "There's new activity in a group you're part of.",
        a.pointer || (a.groupId ? `amen://groups/${a.groupId}` : null),
      ));
    });
    return items;
  } catch (err) {
    logger.warn("generateDailyBrief: community activity fetch failed", { uid, error: err.message });
    return [];
  }
}

/** Prayer updates (Amen-native). */
async function fetchPrayerUpdates(uid) {
  try {
    const snap = await db()
      .collection("users").doc(uid)
      .collection("prayerUpdates")
      .where("acknowledged", "==", false)
      .orderBy("createdAt", "desc")
      .limit(2)
      .get();
    const items = [];
    snap.forEach((d) => {
      const p = d.data() || {};
      items.push(nativeItem(
        BRIEF_SECTION.prayer_updates,
        p.summary || "There's an update on a prayer you're following.",
        p.pointer || (p.prayerId ? `amen://prayers/${p.prayerId}` : null),
      ));
    });
    return items;
  } catch (err) {
    logger.warn("generateDailyBrief: prayer updates fetch failed", { uid, error: err.message });
    return [];
  }
}

/** Messages needing attention (Amen-native). Not surfaced in minor mode of its own. */
async function fetchMessagesNeedingAttention(uid) {
  try {
    const snap = await db()
      .collection("users").doc(uid)
      .collection("threads")
      .where("needsReply", "==", true)
      .orderBy("lastMessageAt", "desc")
      .limit(2)
      .get();
    const items = [];
    snap.forEach((d) => {
      const t = d.data() || {};
      const who = t.peerName ? `${t.peerName}` : "Someone";
      items.push(nativeItem(
        BRIEF_SECTION.messages_needing_attention,
        `${who} is waiting on a reply.`,
        `amen://threads/${d.id}`,
      ));
    });
    return items;
  } catch (err) {
    logger.warn("generateDailyBrief: messages fetch failed", { uid, error: err.message });
    return [];
  }
}

/** Follow-ups the user explicitly chose to continue later (Amen-native). */
async function fetchFollowUps(uid) {
  try {
    const snap = await db()
      .collection("users").doc(uid)
      .collection("followUps")
      .where("status", "==", "open")
      .orderBy("createdAt", "desc")
      .limit(2)
      .get();
    const items = [];
    snap.forEach((d) => {
      const f = d.data() || {};
      items.push(nativeItem(
        BRIEF_SECTION.follow_ups,
        f.label || "Something you set aside to come back to.",
        f.pointer || null,
      ));
    });
    return items;
  } catch (err) {
    logger.warn("generateDailyBrief: follow-ups fetch failed", { uid, error: err.message });
    return [];
  }
}

/**
 * Connector-sourced events (e.g. calendar). ONLY called when the grant set includes
 * ConnectorId.calendar — otherwise the section is ABSENT (never a locked teaser).
 */
async function fetchConnectorEvents(uid, grantedConnectors) {
  if (!grantedConnectors.has("calendar")) return [];
  try {
    // Connector event summaries are written by the connector adapter CF into a
    // first-party mirror (summaries + pointers only — raw content never persists).
    const snap = await db()
      .collection("users").doc(uid)
      .collection("connectorEvents")
      .where("source", "==", "calendar")
      .where("startsAt", ">=", admin.firestore.Timestamp.now())
      .orderBy("startsAt", "asc")
      .limit(3)
      .get();
    const items = [];
    snap.forEach((d) => {
      const e = d.data() || {};
      items.push(connectorItem(
        BRIEF_SECTION.events,
        "calendar",
        e.summary || (e.title ? `On your calendar: ${e.title}` : "An item on your calendar"),
        e.pointer || null,
      ));
    });
    return items;
  } catch (err) {
    logger.warn("generateDailyBrief: connector events fetch failed", { uid, error: err.message });
    return [];
  }
}

// ── ASSEMBLY ─────────────────────────────────────────────────────────────────────

/**
 * Assemble candidate ContextItems honoring minor mode + grants, then enforce the
 * 9-item cap deterministically by SECTION_ORDER. Returns { sections, capped }.
 */
async function assembleSections(uid, { minorMode, grantedConnectors }) {
  const bucket = {
    [BRIEF_SECTION.prayer_updates]: await fetchPrayerUpdates(uid),
    [BRIEF_SECTION.messages_needing_attention]: minorMode ? [] : await fetchMessagesNeedingAttention(uid),
    [BRIEF_SECTION.community]: await fetchCommunityActivity(uid),
    [BRIEF_SECTION.follow_ups]: minorMode ? [] : await fetchFollowUps(uid),
    [BRIEF_SECTION.saved_verse]: await fetchSavedVerse(uid),
    [BRIEF_SECTION.events]: [],
  };

  // Events: Amen-native space events always; connector events only when granted.
  const nativeEvents = await fetchSpaceEvents(uid);
  const connectorEvents = minorMode ? [] : await fetchConnectorEvents(uid, grantedConnectors);
  bucket[BRIEF_SECTION.events] = [...nativeEvents, ...connectorEvents];

  // Enforce hard 9-item cap across all sections, filling by SECTION_ORDER.
  let remaining = MAX_ITEMS_TOTAL;
  let totalCandidates = 0;
  const sections = [];
  for (const section of SECTION_ORDER) {
    const items = bucket[section] || [];
    totalCandidates += items.length;
    if (items.length === 0 || remaining <= 0) {
      if (items.length === 0) continue; // ABSENT section, never an empty teaser
    }
    const take = items.slice(0, Math.max(0, remaining));
    if (take.length > 0) {
      sections.push({ section, items: take });
      remaining -= take.length;
    }
  }

  return { sections, capped: totalCandidates > MAX_ITEMS_TOTAL };
}

/** Strip internal fields before the ContextItem is persisted / returned. */
function cleanItem({ _section, ...item }) {
  return item;
}

/** Build the BriefCard envelope (matches BriefCard contract). */
function buildCard(uid, date, sections, { sabbathSuppressed, minorMode }) {
  return {
    uid,
    date,
    sections: sections.map((s) => ({
      section: s.section,
      items: s.items.map(cleanItem),
    })),
    maxItemsTotal: MAX_ITEMS_TOTAL,
    sabbathSuppressed: !!sabbathSuppressed,
    minorMode: !!minorMode,
  };
}

// ── SUMMARIZATION ────────────────────────────────────────────────────────────────

const BRIEF_SYSTEM_PROMPT = [
  "You write a short daily brief for a Christian app.",
  "Tone: matter-of-fact warmth. Calm, plain, kind. Never anxious.",
  "ABSOLUTE RULES:",
  "- Never use guilt or pressure. Never say 'you missed', 'streak', or 'X days since'.",
  "- Never invent items. Only restate the items provided.",
  "- One short, warm sentence introducing the day. Do not list the items back.",
  "- No emojis. No exclamation marks.",
].join("\n");

/**
 * Produce a one-line intro for the card via the real `daily_brief` route.
 * Failure is non-fatal — the card renders fine without an intro line.
 */
async function summarizeBrief(uid, sections) {
  const itemLines = sections
    .flatMap((s) => s.items.map((i) => `- ${i.payload}`))
    .slice(0, MAX_ITEMS_TOTAL);
  if (itemLines.length === 0) return null;

  try {
    const result = await callModel({
      task: "daily_brief",
      input: itemLines.join("\n"),
      systemPrompt: BRIEF_SYSTEM_PROMPT,
      userId: uid,
    });
    if (result.blocked || result.degraded || typeof result.output !== "string") {
      return null;
    }
    return stripGuiltFraming(result.output).slice(0, 280) || null;
  } catch (err) {
    logger.warn("generateDailyBrief: summarize failed (non-fatal)", { uid, error: err.message });
    return null;
  }
}

// ── CRISIS CONTEXT ───────────────────────────────────────────────────────────────

/**
 * Crisis context BYPASSES Sabbath + caps. If an open crisis support item exists,
 * it is always surfaced (in addition to / instead of normal sections) and is
 * never suppressed by Sabbath or trimmed by the 9-cap.
 */
async function fetchCrisisContext(uid) {
  try {
    const snap = await db()
      .collection("users").doc(uid)
      .collection("safetySurfaces")
      .where("active", "==", true)
      .limit(1)
      .get();
    if (snap.empty) return null;
    const s = snap.docs[0].data() || {};
    return {
      payload: s.message || "Support is available to you right now.",
      pointer: s.pointer || "amen://safety/support",
    };
  } catch (err) {
    logger.warn("generateDailyBrief: crisis context lookup failed", { uid, error: err.message });
    return null;
  }
}

// ── MAIN CALLABLE ────────────────────────────────────────────────────────────────

/**
 * generateDailyBrief({ forceRegenerate?: boolean })
 *
 * Pull-based. Returns a cached BriefCard for today if one exists (unless
 * forceRegenerate), otherwise assembles + caches a fresh one. Honors the
 * generateAfterLocalHour gate: before the local hour, returns yesterday's cache
 * if present rather than generating a new card.
 *
 * Returns: { card: BriefCard, cached: boolean, intro: string | null, capped: boolean }
 */
exports.generateDailyBrief = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 60,
    secrets: [BRIEF_GEMINI_KEY, BRIEF_OPENAI_KEY, BRIEF_NVIDIA_KEY],
  },
  async (request) => {
    const uid = requireBereanAuth(request);
    const forceRegenerate = request.data?.forceRegenerate === true;

    // Rate limit: pull is cheap but cap regeneration abuse — 30/hour.
    await enforceRateLimit(uid, "generateDailyBrief", 30, 3600);

    // ── Resolve user context (timezone, minor flag) ──────────────────────────
    const userSnap = await db().collection("users").doc(uid).get();
    const userData = userSnap.exists ? (userSnap.data() || {}) : {};
    const timezone = userData.timezone || "UTC";
    const minorMode =
      userData.minorScoped === true ||
      userData.isMinor === true ||
      request.auth.token?.minor === true;

    const date = localDateString(timezone);
    const cacheRef = db()
      .collection("users").doc(uid)
      .collection("briefCache").doc(date);

    // ── Crisis context — assembled first; bypasses Sabbath + caps ─────────────
    const crisis = await fetchCrisisContext(uid);

    // ── Sabbath check — rest-framing card, safety still reachable ─────────────
    let sabbathActive = false;
    try {
      sabbathActive = await isShabbatActiveForUser(uid);
    } catch (err) {
      logger.warn("generateDailyBrief: sabbath check failed — treating as inactive", {
        uid, error: err.message,
      });
    }

    if (sabbathActive) {
      // Rest card. Only crisis/safety surfaces remain reachable.
      const restSections = [];
      if (crisis) {
        restSections.push({
          section: BRIEF_SECTION.community,
          items: [cleanItem(nativeItem(BRIEF_SECTION.community, crisis.payload, crisis.pointer))],
        });
      }
      const card = buildCard(uid, date, restSections, {
        sabbathSuppressed: true,
        minorMode,
      });
      // Cache the rest card too (one-per-day).
      await cacheRef.set(
        { ...card, generatedAt: admin.firestore.Timestamp.now(), kind: "sabbath" },
        { merge: false }
      );
      return {
        card,
        cached: false,
        intro: null,
        capped: false,
        sabbath: true,
      };
    }

    // ── Cache hit (pull-one-per-day) ──────────────────────────────────────────
    if (!forceRegenerate) {
      const existing = await cacheRef.get();
      if (existing.exists) {
        const data = existing.data() || {};
        return {
          card: stripCacheMeta(data),
          cached: true,
          intro: data.intro ?? null,
          capped: !!data.capped,
          sabbath: false,
        };
      }

      // Before the local generate hour and no cache yet — return yesterday's card
      // if present rather than generating early (no pre-5am surprises).
      if (localHour(timezone) < GENERATE_AFTER_LOCAL_HOUR) {
        const ySnap = await db()
          .collection("users").doc(uid)
          .collection("briefCache")
          .orderBy("date", "desc")
          .limit(1)
          .get();
        if (!ySnap.empty) {
          const data = ySnap.docs[0].data() || {};
          return {
            card: stripCacheMeta(data),
            cached: true,
            intro: data.intro ?? null,
            capped: !!data.capped,
            sabbath: false,
          };
        }
      }
    }

    // ── Assemble fresh card ───────────────────────────────────────────────────
    const grantedConnectors = await resolveDailyBriefGrants(uid, minorMode);
    const { sections, capped } = await assembleSections(uid, { minorMode, grantedConnectors });

    // Crisis item is appended and is exempt from the cap (bypasses caps).
    if (crisis) {
      sections.unshift({
        section: BRIEF_SECTION.prayer_updates,
        items: [nativeItem(BRIEF_SECTION.prayer_updates, crisis.payload, crisis.pointer)],
      });
    }

    const intro = await summarizeBrief(uid, sections);
    const card = buildCard(uid, date, sections, { sabbathSuppressed: false, minorMode });

    await cacheRef.set(
      {
        ...card,
        intro: intro ?? null,
        capped,
        generatedAt: admin.firestore.Timestamp.now(),
        kind: "standard",
      },
      { merge: false }
    );

    logger.info("generateDailyBrief.complete", {
      uid, date, minorMode, capped,
      sectionCount: card.sections.length,
      connectorGrants: grantedConnectors.size,
    });

    return { card, cached: false, intro: intro ?? null, capped, sabbath: false };
  }
);

/** Remove server-only cache metadata before returning the BriefCard to clients. */
function stripCacheMeta(data) {
  const { intro, capped, generatedAt, kind, ...card } = data;
  return card;
}

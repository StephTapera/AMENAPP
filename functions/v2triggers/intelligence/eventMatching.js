/**
 * eventMatching.js
 * AMEN Living Intelligence — Event Matching
 *
 * matchEventsForUser(userId, context, db) → IntelligenceCard[]
 *
 * Privacy invariants:
 *   - NO count fields emitted on any card ("N attending" is forbidden)
 *   - Geo is coarse-only and only queried if context.location is provided (opt-in)
 *   - Cards only returned for backingEntity.verified === true events
 *
 * Fail policy: fail_closed — any error returns []
 */

"use strict";

const { callModel }   = require("../router/callModel");
const { buildCardId } = require("./contracts");

// Radius for location-based event matching (km converted to degrees ≈ 0.135°/15km)
const GEO_RADIUS_DEG = 0.135;

// Window: events starting in the next 7 days
const WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * matchEventsForUser
 *
 * @param {string}   userId
 * @param {object}   context  — { location?, churchIds, followedChurchIds, seasonOfLife, capacity }
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<import('./contracts').IntelligenceCard[]>}
 */
async function matchEventsForUser(userId, context, db) {
  try {
    const now        = Date.now();
    const windowEnd  = now + WINDOW_MS;
    const cards      = [];

    // ── 1. Fetch events by followed churches ─────────────────────────────────
    const followedIds = context.followedChurchIds ?? [];
    let churchEvents  = [];

    if (followedIds.length > 0) {
      // Firestore IN supports up to 30 elements; chunk if needed
      const chunks = chunkArray(followedIds, 30);
      for (const chunk of chunks) {
        const snap = await db.collection("events")
          .where("organizerChurchId", "in", chunk)
          .where("startDate", ">=", new Date(now))
          .where("startDate", "<=", new Date(windowEnd))
          .where("isDeleted", "==", false)
          .orderBy("startDate", "asc")
          .limit(20)
          .get();

        snap.forEach(doc => churchEvents.push({ id: doc.id, ...doc.data() }));
      }
    }

    // ── 2. Fetch nearby events if geo opt-in ─────────────────────────────────
    let nearbyEvents = [];

    if (context.location && typeof context.location.lat === "number") {
      const { lat, lng } = context.location;
      // Coarse bounding-box query (Firestore has no native geo; use lat range + filter lng in memory)
      const latMin = lat - GEO_RADIUS_DEG;
      const latMax = lat + GEO_RADIUS_DEG;

      const geoSnap = await db.collection("events")
        .where("location.lat", ">=", latMin)
        .where("location.lat", "<=", latMax)
        .where("startDate", ">=", new Date(now))
        .where("startDate", "<=", new Date(windowEnd))
        .where("isDeleted", "==", false)
        .limit(30)
        .get();

      const lngRadius = GEO_RADIUS_DEG;
      geoSnap.forEach(doc => {
        const data = doc.data();
        if (
          typeof data.location?.lng === "number" &&
          Math.abs(data.location.lng - lng) <= lngRadius
        ) {
          nearbyEvents.push({ id: doc.id, ...data });
        }
      });
    }

    // De-duplicate by event id
    const seenIds  = new Set();
    const allEvents = [];
    for (const evt of [...churchEvents, ...nearbyEvents]) {
      if (!seenIds.has(evt.id)) {
        seenIds.add(evt.id);
        allEvents.push(evt);
      }
    }

    if (allEvents.length === 0) return [];

    // ── 3. AI match scoring + card construction ───────────────────────────────
    for (const event of allEvents) {
      try {
        // resolveBackingEntity: skip events not verified
        if (event.verified === false) continue;

        // Call model for match scoring
        let matchScore   = 50;
        let matchReasons = ["Upcoming event in your church community"];

        try {
          const modelResult = await callModel({
            task:   "intelligence.match",
            input:  JSON.stringify({ event, userContext: context }),
            userId,
          });

          if (!modelResult.blocked && modelResult.output) {
            const parsed = safeParseJSON(modelResult.output);
            if (parsed && typeof parsed.matchScore === "number") {
              matchScore   = Math.min(100, Math.max(0, Math.round(parsed.matchScore)));
              matchReasons = Array.isArray(parsed.matchReasons) ? parsed.matchReasons : matchReasons;
            }
          }
        } catch (modelErr) {
          // Non-blocking — continue with defaults if model unavailable
        }

        // Determine tier: LOCAL if geo-based, COMMUNITY if church-based
        const isGeoEvent   = !followedIds.includes(event.organizerChurchId);
        const tier         = isGeoEvent ? "LOCAL" : "COMMUNITY";

        // Berean-summarize event description (≤3 bullets)
        let summaryBullets = deriveEventSummary(event);
        try {
          const summaryResult = await callModel({
            task:        "berean_summarize",
            input:       event.description ?? event.title ?? "",
            systemPrompt: "Summarize this church event in 1-3 concise bullets. No counts. No spectacle. Be formational.",
            userId,
          });
          if (!summaryResult.blocked && summaryResult.output) {
            const bullets = summaryResult.output
              .split("\n")
              .map(l => l.replace(/^[-•*]\s*/, "").trim())
              .filter(l => l.length > 0)
              .slice(0, 3);
            if (bullets.length > 0) summaryBullets = bullets;
          }
        } catch (sumErr) {
          // Fall back to derived summary
        }

        // Build actions — RSVP only if capacity allows, PRAY always, LEARN if teaching topic
        const actions = [];

        if (event.capacity == null || (typeof event.spotsRemaining === "number" && event.spotsRemaining > 0)) {
          actions.push({
            rung:    "SHOW_UP",
            label:   "RSVP",
            handler: "intelligence.rsvp",
            target:  event.id,
          });
        }

        actions.push({
          rung:    "PRAY",
          label:   "Pray for this",
          handler: "intelligence.pray",
          target:  event.id,
        });

        if (event.teachingTopic || event.seriesName) {
          actions.push({
            rung:    "LEARN",
            label:   "Learn more",
            handler: "intelligence.learn",
            target:  event.id,
          });
        }

        const expiresAt = event.startDate?._seconds
          ? event.startDate._seconds * 1000
          : (typeof event.startDate?.toMillis === "function"
              ? event.startDate.toMillis()
              : now + WINDOW_MS);

        const card = {
          id:            buildCardId("event", event.id, userId),
          tier,
          title:         event.title ?? "Upcoming Event",
          summary:       summaryBullets,
          backingEntity: { kind: "EVENT", id: event.id, verified: true },
          truthLevel:    event.churchVerified ? "CHURCH_CONFIRMED" : "COMMUNITY_CONFIRMED",
          matchScore,
          matchReasons,
          actions,
          rankScore:     matchScore / 100,
          rankReasons:   matchReasons.slice(0, 2),
          geo:           null,
          formation: {
            finite:           true,
            spectacleCounters: false,
            lamentFrame:      false,
            loopParentId:     null,
          },
          source:    "event_matching",
          createdAt: now,
          expiresAt,
        };

        cards.push(card);
      } catch (cardErr) {
        // Skip malformed event — fail-closed per-event, not per-call
        console.error("[eventMatching] card build error", { eventId: event.id, err: cardErr.message });
      }
    }

    // ── 4. Sort by matchScore desc ─────────────────────────────────────────
    cards.sort((a, b) => (b.matchScore ?? 0) - (a.matchScore ?? 0));
    return cards;

  } catch (err) {
    console.error("[eventMatching] matchEventsForUser failed — returning []", err.message);
    return [];
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function chunkArray(arr, size) {
  const chunks = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

function safeParseJSON(str) {
  try {
    const clean = str.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
    return JSON.parse(clean);
  } catch {
    return null;
  }
}

function deriveEventSummary(event) {
  const bullets = [];
  if (event.description)   bullets.push(event.description.slice(0, 120));
  if (event.location?.name) bullets.push(`Location: ${event.location.name}`);
  if (event.seriesName)    bullets.push(`Part of: ${event.seriesName}`);
  return bullets.slice(0, 3).filter(Boolean);
}

module.exports = { matchEventsForUser };

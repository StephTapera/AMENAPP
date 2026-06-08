/**
 * churchPulse.js
 * AMEN App — Church Pulse computation engine
 *
 * computeChurchPulse(churchId, db) → ChurchPulse
 *
 * ALL pulse data is derived from REAL Firestore documents only.
 * No synthetic data, no fabricated scores.
 *
 * Pulse score formula (max 100):
 *   events this month:  (count >= 4 → 25, 2–3 → 17, 1 → 10, 0 → 0)
 *   active prayers:     (5+ → 25, 1+ → 20, 0 → 0)
 *   volunteer needs:    (1+ → 15, 0 → 0)
 *   recentTeachingTopic present → 20
 *   memberEngagement:   HIGH → +15, MEDIUM → +10, LOW/UNKNOWN → 0
 *
 * memberEngagement is derived from event + prayer counts — NEVER from raw
 * member count (privacy).
 */

"use strict";

const { Timestamp } = require("firebase-admin/firestore");

/**
 * Compute a ChurchPulse object for the given churchId.
 *
 * @param {string} churchId
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<object>} ChurchPulse
 */
async function computeChurchPulse(churchId, db) {
    const now = Date.now();
    const startOfMonth = new Date();
    startOfMonth.setDate(1);
    startOfMonth.setHours(0, 0, 0, 0);

    // ── 1. Upcoming events (from now forward, ordered by startDate asc) ───────

    const [upcomingEventsSnap, monthEventsSnap, prayersSnap, volunteerSnap] =
        await Promise.all([
            db.collection("events")
                .where("churchId", "==", churchId)
                .where("startDate", ">", Timestamp.fromMillis(now))
                .orderBy("startDate", "asc")
                .limit(10)
                .get(),

            db.collection("events")
                .where("churchId", "==", churchId)
                .where("startDate", ">=", Timestamp.fromDate(startOfMonth))
                .limit(20)
                .get(),

            db.collection("prayers")
                .where("churchId", "==", churchId)
                .where("isPublic", "==", true)
                .where("status", "in", ["ACTIVE", "active", "open"])
                .limit(20)
                .get(),

            db.collection("volunteerOpportunities")
                .where("churchId", "==", churchId)
                .where("isActive", "==", true)
                .limit(10)
                .get(),
        ]);

    // ── 2. Extract raw counts ─────────────────────────────────────────────────

    const upcomingCount = upcomingEventsSnap.size;
    const eventsThisMonthCount = monthEventsSnap.size;
    const activePrayerCount = prayersSnap.size;
    const volunteerCount = volunteerSnap.size;

    // ── 3. Next event ─────────────────────────────────────────────────────────

    let nextEventTitle = null;
    let nextEventDate = null;

    if (!upcomingEventsSnap.empty) {
        const next = upcomingEventsSnap.docs[0].data();
        nextEventTitle = next.title ?? next.name ?? null;
        const sd = next.startDate;
        if (sd && typeof sd.toMillis === "function") {
            nextEventDate = sd.toMillis();
        } else if (typeof sd === "number") {
            nextEventDate = sd;
        }
    }

    // ── 4. Volunteer roles ────────────────────────────────────────────────────

    const volunteerRoles = volunteerSnap.docs
        .map((d) => d.data().role ?? d.data().title ?? null)
        .filter(Boolean)
        .slice(0, 5);

    // ── 5. Recent teaching topic ──────────────────────────────────────────────
    // From the most recent event that has a topicTag or topicTags

    let recentTeachingTopic = null;

    // Check upcoming events first, then fall back to recent past events
    for (const doc of upcomingEventsSnap.docs) {
        const d = doc.data();
        const tag = d.topicTag ?? (Array.isArray(d.topicTags) ? d.topicTags[0] : null) ?? null;
        if (tag) {
            recentTeachingTopic = tag;
            break;
        }
    }

    if (!recentTeachingTopic) {
        // Try the most recent past event
        const recentPastSnap = await db.collection("events")
            .where("churchId", "==", churchId)
            .where("startDate", "<", Timestamp.fromMillis(now))
            .orderBy("startDate", "desc")
            .limit(5)
            .get();

        for (const doc of recentPastSnap.docs) {
            const d = doc.data();
            const tag = d.topicTag ?? (Array.isArray(d.topicTags) ? d.topicTags[0] : null) ?? null;
            if (tag) {
                recentTeachingTopic = tag;
                break;
            }
        }
    }

    // ── 6. Member engagement (derived, never raw member count) ───────────────

    let memberEngagement;
    if (activePrayerCount >= 10 || eventsThisMonthCount >= 6) {
        memberEngagement = "HIGH";
    } else if (activePrayerCount >= 3 || eventsThisMonthCount >= 3) {
        memberEngagement = "MEDIUM";
    } else if (activePrayerCount > 0 || eventsThisMonthCount > 0) {
        memberEngagement = "LOW";
    } else {
        memberEngagement = "UNKNOWN";
    }

    // ── 7. Pulse score (0–100) ────────────────────────────────────────────────

    let score = 0;
    const reasons = [];

    // Events this month
    if (eventsThisMonthCount >= 4) {
        score += 25;
        reasons.push(`${eventsThisMonthCount} events this month`);
    } else if (eventsThisMonthCount >= 2) {
        score += 17;
        reasons.push(`${eventsThisMonthCount} events this month`);
    } else if (eventsThisMonthCount === 1) {
        score += 10;
        reasons.push("1 event this month");
    }

    // Active prayer requests
    if (activePrayerCount >= 5) {
        score += 25;
        reasons.push("Active prayer community");
    } else if (activePrayerCount >= 1) {
        score += 20;
        reasons.push("Active prayer requests");
    }

    // Volunteer needs
    if (volunteerCount >= 1) {
        score += 15;
        reasons.push("Volunteer opportunities posted");
    }

    // Recent teaching topic
    if (recentTeachingTopic) {
        score += 20;
        reasons.push(`Recent teaching: ${recentTeachingTopic}`);
    }

    // Member engagement
    if (memberEngagement === "HIGH") {
        score += 15;
        reasons.push("High community engagement");
    } else if (memberEngagement === "MEDIUM") {
        score += 10;
        reasons.push("Growing community engagement");
    }

    // Cap at 100, floor at 0
    const pulseScore = Math.max(0, Math.min(100, score));

    // ── 8. Build the ChurchPulse object ───────────────────────────────────────

    return {
        churchId,
        computedAt: now,
        upcomingEvents: {
            count: upcomingCount,
            nextEventTitle,
            nextEventDate,
        },
        activePrayerRequests: {
            count: activePrayerCount,
        },
        volunteerNeeds: {
            count: volunteerCount,
            roles: volunteerRoles,
        },
        recentTeachingTopic,
        memberEngagement,
        pulseScore,
        pulseReasons: reasons,
        finite: true,
        spectacleCounters: false,
    };
}

module.exports = { computeChurchPulse };

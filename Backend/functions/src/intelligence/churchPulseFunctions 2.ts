// churchPulseFunctions.ts
// Living Intelligence System — Church Pulse Cloud Functions
//
// Three exports:
//   refreshChurchPulses    — scheduled every 6 hours, updates all verified churches
//   getChurchPulseForUser  — callable, auth required, returns pulse for one church
//   buildChurchPulseCard   — callable, auth required, returns IntelligenceCard shape

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import {
  computeChurchPulse,
  saveChurchPulse,
  getChurchPulse,
  ChurchPulseData,
} from "./churchPulseComputer";
import {
  IntelligenceCard,
  CardAction,
  ACTION_HANDLERS,
} from "./contracts";

// ---------------------------------------------------------------------------
// Scheduled: refresh pulses for all verified churches every 6 hours
// ---------------------------------------------------------------------------

export const refreshChurchPulses = onSchedule(
  { schedule: "every 6 hours", region: "us-central1" },
  async () => {
    const db = admin.firestore();
    const churchesSnap = await db
      .collection("churches")
      .where("verified", "==", true)
      .get();

    logger.info("refreshChurchPulses: starting", { churchCount: churchesSnap.size });

    const results = await Promise.allSettled(
      churchesSnap.docs.map((doc) =>
        computeChurchPulse(doc.id).then(saveChurchPulse)
      )
    );

    const failed = results.filter((r) => r.status === "rejected").length;
    logger.info("refreshChurchPulses: complete", {
      total: churchesSnap.size,
      failed,
    });
  }
);

// ---------------------------------------------------------------------------
// Callable: get pulse for a specific church (auth required)
// ---------------------------------------------------------------------------

export const getChurchPulseForUser = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required to view church pulse.");
    }

    const data = request.data as { churchId?: unknown };
    if (typeof data.churchId !== "string" || data.churchId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "churchId is required.");
    }
    const churchId = data.churchId.trim();

    // Try cached first
    let pulse = await getChurchPulse(churchId);

    if (!pulse) {
      // Compute on-demand if no valid cache exists
      try {
        pulse = await computeChurchPulse(churchId);
        await saveChurchPulse(pulse);
      } catch (err) {
        logger.error("getChurchPulseForUser: compute failed", { churchId, err });
        throw new HttpsError("internal", "Unable to compute church pulse at this time.");
      }
    }

    return pulse;
  }
);

// ---------------------------------------------------------------------------
// Callable: build IntelligenceCard for a church (used by digest builder)
// ---------------------------------------------------------------------------

export const buildChurchPulseCard = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const data = request.data as { churchId?: unknown };
    if (typeof data.churchId !== "string" || data.churchId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "churchId is required.");
    }
    const churchId = data.churchId.trim();
    const uid = request.auth.uid;

    // Fetch or compute pulse
    let pulse: ChurchPulseData;
    const cached = await getChurchPulse(churchId);
    if (cached) {
      pulse = cached;
    } else {
      try {
        pulse = await computeChurchPulse(churchId);
        await saveChurchPulse(pulse);
      } catch (err) {
        logger.error("buildChurchPulseCard: compute failed", { churchId, uid, err });
        throw new HttpsError("internal", "Unable to build church card at this time.");
      }
    }

    // ── Build actions only from signals that are actually present ────────────
    const actions: CardAction[] = [
      {
        rung: "SHOW_UP",
        label: "View church",
        handler: ACTION_HANDLERS.OPEN_CHURCH,
        target: churchId,
      },
    ];

    if (pulse.upcomingEventCount > 0) {
      actions.push({
        rung: "SHOW_UP",
        label: "See upcoming events",
        handler: ACTION_HANDLERS.OPEN_EVENT,
        target: churchId,
      });
    }

    if (pulse.activePrayerRequestCount > 0) {
      actions.push({
        rung: "PRAY",
        label: "See prayer requests",
        handler: ACTION_HANDLERS.OPEN_PRAYER,
        target: churchId,
      });
    }

    if (pulse.volunteerNeedCount > 0) {
      actions.push({
        rung: "SHOW_UP",
        label: "See volunteer needs",
        handler: ACTION_HANDLERS.VOLUNTEER,
        target: churchId,
      });
    }

    // ── Rank reasons ─────────────────────────────────────────────────────────
    const rankReasons: string[] = ["Your church"];
    if (pulse.upcomingEventCount >= 3) rankReasons.push("Active this week");
    if (pulse.activePrayerRequestCount >= 5) rankReasons.push("Community is praying");
    if (pulse.recentTeachingTopics.length >= 2) rankReasons.push("Active teaching ministry");

    // ── Summary bullets (max 3 from real pulseSignals) ────────────────────────
    const summary = pulse.pulseSignals.slice(0, 3);
    if (summary.length === 0) {
      summary.push("Check back soon for updates from this church.");
    }

    const now = Date.now();

    const card: IntelligenceCard = {
      id: `church_pulse_${churchId}`,
      tier: pulse.verified ? "LOCAL" : "COMMUNITY",
      title: `${pulse.churchName} — What's Happening`,
      summary,
      backingEntity: {
        kind: "CHURCH",
        id: churchId,
        verified: pulse.verified,
      },
      truthLevel: pulse.verified ? "CHURCH_CONFIRMED" : "COMMUNITY_CONFIRMED",
      actions,
      rankScore: pulse.pulseScore,
      rankReasons,
      formation: {
        finite: true,
        spectacleCounters: false,
      },
      createdAt: now,
      expiresAt: pulse.expiresAt,
    };

    return card;
  }
);

/**
 * evaluateSabbathMode.ts — Sabbath Mode
 * Firebase gen2 HTTPS callable. Auth + AppCheck required.
 *
 * Input:  { uid?: string, now?: number (epoch ms) }
 * Output: { state, config, session, digest? }
 *
 * MINOR GATE: isMinor==true or ageTier in ['teen','under_minimum'] → STOP.
 * All Firestore writes are additive (merge: true).
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { buildDigest } from "./digestBuilder";

const db = admin.firestore();

interface SabbathConfig {
  chosenDay: "saturday" | "sunday";
  boundary: "localMidnight" | "sundown";
  timezone: string;
  createdAt: number;
  updatedAt: number;
}

function dateInTz(epochMs: number, tz: string): string {
  return new Date(epochMs).toLocaleDateString("en-CA", { timeZone: tz });
}

function weekdayInTz(epochMs: number, tz: string): number {
  return new Date(new Date(epochMs).toLocaleString("en-US", { timeZone: tz })).getDay();
}

function computeState(config: SabbathConfig, nowMs: number): "active" | "inactive" {
  const tz = config.timezone || "UTC";
  const weekday = weekdayInTz(nowMs, tz);
  const targetDay = config.chosenDay === "saturday" ? 6 : 0;
  if (weekday !== targetDay) return "inactive";
  // localMidnight and sundown (fallback) are both full-day on the chosen weekday
  return "active";
}

async function resolveTimezone(uid: string, existingConfig: SabbathConfig | null): Promise<string> {
  if (existingConfig?.timezone) return existingConfig.timezone;
  const policySnap = await db.collection("restModePolicies").doc(uid).get();
  if (policySnap.exists) {
    const tz = (policySnap.data() as { timezone?: string }).timezone;
    if (tz) return tz;
  }
  return "UTC";
}

export const evaluateSabbathMode = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request) => {
    if (!request.app) throw new HttpsError("unauthenticated", "App Check required.");
    if (!request.auth) throw new HttpsError("unauthenticated", "Must be authenticated.");

    const callerUid = request.auth.uid;
    const data = request.data as { uid?: string; now?: number };
    const uid = data.uid ?? callerUid;
    const nowMs = typeof data.now === "number" ? data.now : Date.now();

    if (uid !== callerUid) {
      throw new HttpsError("permission-denied", "You may only evaluate your own Sabbath state.");
    }

    // MINOR GATE
    const userSnap = await db.collection("users").doc(uid).get();
    if (userSnap.exists) {
      const u = userSnap.data() as { isMinor?: boolean; ageTier?: string };
      if (u.isMinor === true) return { MINOR_GATE_REQUIRED: true, reason: "minor account detected" };
      const tier = u.ageTier ?? "";
      if (tier === "under_minimum" || tier === "teen") {
        return { MINOR_GATE_REQUIRED: true, reason: "minor account detected" };
      }
    }

    const configRef = db.collection("users").doc(uid).collection("sabbath").doc("config");
    const configSnap = await configRef.get();

    let config: SabbathConfig;
    if (!configSnap.exists) {
      const resolvedTz = await resolveTimezone(uid, null);
      config = { chosenDay: "sunday", boundary: "localMidnight", timezone: resolvedTz, createdAt: nowMs, updatedAt: nowMs };
      await configRef.set(config, { merge: true });
    } else {
      config = configSnap.data() as SabbathConfig;
    }

    const computedState = computeState(config, nowMs);
    const sessionDate = dateInTz(nowMs, config.timezone ?? "UTC");

    const sessionRef = db.collection("users").doc(uid).collection("sabbathSessions").doc(sessionDate);
    const sessionSnap = await sessionRef.get();
    let session = sessionSnap.exists ? sessionSnap.data() : null;

    let finalState: "active" | "inactive" | "steppedOut" = computedState;
    if (session && (session as { state?: string }).state === "steppedOut") finalState = "steppedOut";

    if (computedState === "active" && !sessionSnap.exists) {
      const newSession = { date: sessionDate, state: "active", enteredAt: nowMs, surfacesUsed: [] };
      await sessionRef.set(newSession, { merge: true });
      session = newSession;
    }

    let digest = null;
    const shouldIncludeDigest =
      session &&
      !(session as { digestShown?: boolean }).digestShown &&
      (finalState === "steppedOut" ||
        (computedState === "inactive" && (session as { state?: string }).state === "active"));

    if (shouldIncludeDigest) {
      try {
        digest = await buildDigest(uid, sessionDate);
      } catch (err) {
        console.error(`[evaluateSabbathMode] buildDigest failed uid=${uid}:`, err);
      }
    }

    return { state: finalState, config, session, ...(digest ? { digest } : {}) };
  }
);

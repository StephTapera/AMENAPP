/**
 * setSabbathPreference.ts — Sabbath Mode
 * Firebase gen2 HTTPS callable. Auth + AppCheck required.
 *
 * Input: { chosenDay: 'saturday'|'sunday', boundary?: string, timezone?: string }
 * All writes additive (merge: true). MINOR GATE enforced.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = admin.firestore();
const VALID_DAYS = ["saturday", "sunday"] as const;
const VALID_BOUNDARIES = ["localMidnight", "sundown"] as const;

export const setSabbathPreference = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request) => {
    if (!request.app) throw new HttpsError("unauthenticated", "App Check required.");
    if (!request.auth) throw new HttpsError("unauthenticated", "Must be authenticated.");

    const uid = request.auth.uid;

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

    const input = (request.data ?? {}) as { chosenDay?: string; boundary?: string; timezone?: string };

    if (!input.chosenDay || !(VALID_DAYS as readonly string[]).includes(input.chosenDay)) {
      throw new HttpsError(
        "invalid-argument",
        `chosenDay must be one of: ${VALID_DAYS.join(", ")}. Received: "${input.chosenDay}".`
      );
    }
    if (input.boundary !== undefined && !(VALID_BOUNDARIES as readonly string[]).includes(input.boundary)) {
      throw new HttpsError(
        "invalid-argument",
        `boundary must be one of: ${VALID_BOUNDARIES.join(", ")}. Received: "${input.boundary}".`
      );
    }
    if (input.timezone !== undefined && (typeof input.timezone !== "string" || !input.timezone.trim())) {
      throw new HttpsError("invalid-argument", "timezone must be a non-empty IANA timezone string.");
    }

    const nowMs = Date.now();
    const update: Record<string, unknown> = { chosenDay: input.chosenDay, updatedAt: nowMs };
    if (input.boundary !== undefined) update.boundary = input.boundary;
    if (input.timezone !== undefined) update.timezone = input.timezone.trim();

    const configRef = db.collection("users").doc(uid).collection("sabbath").doc("config");
    const configSnap = await configRef.get();

    if (!configSnap.exists) {
      update.createdAt = nowMs;
      if (!update.boundary) update.boundary = "localMidnight";
      if (!update.timezone) {
        const policySnap = await db.collection("restModePolicies").doc(uid).get();
        update.timezone = policySnap.exists
          ? ((policySnap.data() as { timezone?: string }).timezone ?? "UTC")
          : "UTC";
      }
    }

    await configRef.set(update, { merge: true });
    const updatedSnap = await configRef.get();
    return { success: true, updatedConfig: updatedSnap.data() };
  }
);

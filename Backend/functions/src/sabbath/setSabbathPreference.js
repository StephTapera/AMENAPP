/**
 * setSabbathPreference.js
 * Phase 2C — Backend (Sabbath Mode)
 *
 * Firebase gen2 HTTPS callable.
 * Auth + App Check required.
 *
 * Input: {
 *   chosenDay: 'saturday' | 'sunday',   // required
 *   boundary?: 'localMidnight' | 'sundown',
 *   timezone?: string                    // IANA timezone string
 * }
 *
 * Validates chosenDay strictly — rejects any value other than 'saturday' | 'sunday'.
 * All writes are additive: uses { merge: true } on users/{uid}/sabbath/config.
 *
 * Returns: { success: true, updatedConfig }
 *
 * MINOR GATE: Rejects requests from minor accounts immediately.
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const db = admin.firestore();

const VALID_DAYS = ["saturday", "sunday"];
const VALID_BOUNDARIES = ["localMidnight", "sundown"];

const setSabbathPreference = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request) => {
    // Auth gate
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }

    const uid = request.auth.uid;

    // MINOR GATE — check before writing anything
    const userSnap = await db.collection("users").doc(uid).get();
    if (userSnap.exists) {
      const userData = userSnap.data();
      if (userData.isMinor === true) {
        return { MINOR_GATE_REQUIRED: true, reason: "minor account detected" };
      }
      const ageTier = userData.ageTier || "";
      if (ageTier === "under_minimum" || ageTier === "teen") {
        return { MINOR_GATE_REQUIRED: true, reason: "minor account detected" };
      }
    }

    // Validate input
    const input = request.data || {};

    // chosenDay is required and must be strictly 'saturday' or 'sunday'
    if (!input.chosenDay || !VALID_DAYS.includes(input.chosenDay)) {
      throw new HttpsError(
        "invalid-argument",
        `chosenDay must be one of: ${VALID_DAYS.join(", ")}. Received: "${input.chosenDay}".`
      );
    }

    // boundary is optional but if provided must be a known value
    if (input.boundary !== undefined && !VALID_BOUNDARIES.includes(input.boundary)) {
      throw new HttpsError(
        "invalid-argument",
        `boundary must be one of: ${VALID_BOUNDARIES.join(", ")}. Received: "${input.boundary}".`
      );
    }

    // timezone is optional; if provided validate it is a non-empty string
    if (input.timezone !== undefined) {
      if (typeof input.timezone !== "string" || input.timezone.trim() === "") {
        throw new HttpsError("invalid-argument", "timezone must be a non-empty IANA timezone string.");
      }
    }

    // Build the update payload (additive — only update what was provided)
    const nowMs = Date.now();
    const update = {
      chosenDay: input.chosenDay,
      updatedAt: nowMs,
    };

    if (input.boundary !== undefined) {
      update.boundary = input.boundary;
    }

    if (input.timezone !== undefined) {
      update.timezone = input.timezone.trim();
    }

    // Additive write — merge: true so existing fields (createdAt, etc.) are preserved
    const configRef = db.collection("users").doc(uid).collection("sabbath").doc("config");

    // Ensure createdAt is set on first write
    const configSnap = await configRef.get();
    if (!configSnap.exists) {
      update.createdAt = nowMs;
      // Apply defaults for fields not provided
      if (!update.boundary) update.boundary = "localMidnight";
      if (!update.timezone) {
        // Attempt to read from restModePolicies as a timezone seed
        const policySnap = await db.collection("restModePolicies").doc(uid).get();
        if (policySnap.exists && policySnap.data().timezone) {
          update.timezone = policySnap.data().timezone;
        } else {
          update.timezone = "UTC";
        }
      }
    }

    await configRef.set(update, { merge: true });

    // Read back the full updated config to return it
    const updatedSnap = await configRef.get();
    const updatedConfig = updatedSnap.data();

    return { success: true, updatedConfig };
  }
);

module.exports = { setSabbathPreference };

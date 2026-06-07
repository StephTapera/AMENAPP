/**
 * evaluateSabbathMode.js
 * Phase 2C — Backend (Sabbath Mode)
 *
 * Firebase gen2 HTTPS callable.
 * Auth + App Check required.
 *
 * Input:  { uid?: string, now?: number (epoch ms) }
 *   uid  — if omitted, defaults to request.auth.uid (caller evaluates their own state)
 *   now  — if omitted, uses server clock
 *
 * Output: { state, config, session, digest? }
 *
 * MINOR GATE: Any uid whose Firestore user document has isMinor == true
 *             or ageTier in ['teen', 'under_minimum'] → STOP immediately,
 *             return { MINOR_GATE_REQUIRED: true }.
 *
 * DESIGN NOTES:
 *   - Digest is built server-side ONLY (via digestBuilder.buildDigest).
 *   - No badge counts are written or returned.
 *   - All Firestore writes use { merge: true } (additive).
 *   - Timezone resolution order:
 *       1. users/{uid}/sabbath/config.timezone  (user-set via setSabbathPreference)
 *       2. restModePolicies/{uid}.timezone      (established rest mode policy)
 *       3. Request header / 'UTC' fallback
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { buildDigest } = require("./digestBuilder");

const db = admin.firestore();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Compute the ISO date string (yyyy-mm-dd) for a given epoch ms in a timezone.
 * @param {number} epochMs
 * @param {string} tz IANA timezone string
 * @returns {string} e.g. "2026-06-08"
 */
function dateInTz(epochMs, tz) {
  const d = new Date(epochMs);
  // toLocaleDateString with locale "en-CA" returns yyyy-mm-dd.
  return d.toLocaleDateString("en-CA", { timeZone: tz });
}

/**
 * Compute the day-of-week (0=Sunday, 6=Saturday) for a given epoch ms in a timezone.
 * @param {number} epochMs
 * @param {string} tz
 * @returns {number}
 */
function weekdayInTz(epochMs, tz) {
  const d = new Date(new Date(epochMs).toLocaleString("en-US", { timeZone: tz }));
  return d.getDay();
}

/**
 * Determine the SabbathState given the user's config and the current epoch ms.
 * 'steppedOut' is resolved by the caller after reading the session doc.
 * This function returns 'active' | 'inactive' only.
 *
 * @param {object} config  SabbathConfig from Firestore
 * @param {number} nowMs   Current epoch ms
 * @returns {'active'|'inactive'}
 */
function computeState(config, nowMs) {
  const tz = config.timezone || "UTC";
  const weekday = weekdayInTz(nowMs, tz); // 0=Sun, 6=Sat

  const targetDay = config.chosenDay === "saturday" ? 6 : 0;
  if (weekday !== targetDay) return "inactive";

  if (config.boundary === "localMidnight") {
    // localMidnight: active all day on chosen day (00:00–23:59)
    // Since we already confirmed weekday matches, it is always active.
    return "active";
  }

  // 'sundown' boundary: would require lat/lng for solar calculation.
  // Per spec, boundary field defaults to 'localMidnight'; sundown is future work.
  // For now treat sundown as full-day active on chosen day (same as localMidnight).
  return "active";
}

/**
 * Resolve the user's timezone from the most authoritative source available.
 * Order: sabbath/config.timezone → restModePolicies.timezone → 'UTC'
 *
 * @param {string} uid
 * @param {object|null} existingConfig  existing sabbath config (may be null)
 * @returns {Promise<string>}
 */
async function resolveTimezone(uid, existingConfig) {
  if (existingConfig && existingConfig.timezone) return existingConfig.timezone;

  // Fall back to restModePolicies/{uid}.timezone
  const policySnap = await db.collection("restModePolicies").doc(uid).get();
  if (policySnap.exists) {
    const tz = policySnap.data().timezone;
    if (tz) return tz;
  }

  return "UTC";
}

// ---------------------------------------------------------------------------
// Callable
// ---------------------------------------------------------------------------

const evaluateSabbathMode = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request) => {
    // Auth gate
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }

    const callerUid = request.auth.uid;
    const uid = request.data.uid || callerUid;
    const nowMs = typeof request.data.now === "number" ? request.data.now : Date.now();

    // Callers may only evaluate their own state (or admin users their own).
    // Enforce ownership: caller may not evaluate another user's Sabbath state.
    if (uid !== callerUid) {
      throw new HttpsError(
        "permission-denied",
        "You may only evaluate your own Sabbath state."
      );
    }

    // MINOR GATE — check user document before doing anything else
    const userSnap = await db.collection("users").doc(uid).get();
    if (userSnap.exists) {
      const userData = userSnap.data();
      if (userData.isMinor === true) {
        return { MINOR_GATE_REQUIRED: true, reason: "minor account detected" };
      }
      // Also check custom claim pattern stored in Firestore ageTier field (defensive check)
      const ageTier = userData.ageTier || "";
      if (ageTier === "under_minimum" || ageTier === "teen") {
        return { MINOR_GATE_REQUIRED: true, reason: "minor account detected" };
      }
    }

    // ------------------------------------------------------------------
    // 1. Read users/{uid}/sabbath/config
    // ------------------------------------------------------------------
    const configRef = db.collection("users").doc(uid).collection("sabbath").doc("config");
    const configSnap = await configRef.get();

    let config;
    const isNewConfig = !configSnap.exists;

    if (isNewConfig) {
      // 2. No config → create default
      const resolvedTz = await resolveTimezone(uid, null);
      config = {
        chosenDay: "sunday",
        boundary: "localMidnight",
        timezone: resolvedTz,
        createdAt: nowMs,
        updatedAt: nowMs,
      };
      await configRef.set(config, { merge: true });
    } else {
      config = configSnap.data();
    }

    // ------------------------------------------------------------------
    // 3. Compute current SabbathState
    // ------------------------------------------------------------------
    const computedState = computeState(config, nowMs);
    const sessionDate = dateInTz(nowMs, config.timezone || "UTC");

    // ------------------------------------------------------------------
    // 4. Read today's session doc users/{uid}/sabbathSessions/{date}
    // ------------------------------------------------------------------
    const sessionRef = db
      .collection("users")
      .doc(uid)
      .collection("sabbathSessions")
      .doc(sessionDate);
    const sessionSnap = await sessionRef.get();
    let session = sessionSnap.exists ? sessionSnap.data() : null;

    // Resolve final state, accounting for steppedOut
    let finalState = computedState;
    if (session && session.state === "steppedOut") {
      finalState = "steppedOut";
    }

    // ------------------------------------------------------------------
    // 5. If state === 'active' and no session → create session
    // ------------------------------------------------------------------
    if (computedState === "active" && !sessionSnap.exists) {
      const newSession = {
        date: sessionDate,
        state: "active",
        enteredAt: nowMs,
        surfacesUsed: [],
      };
      await sessionRef.set(newSession, { merge: true });
      session = newSession;
    }

    // ------------------------------------------------------------------
    // 6. If state === 'inactive' and session.state === 'active' →
    //    window ended normally — leave session as-is (iOS handles transition)
    // ------------------------------------------------------------------
    // (no write needed per spec)

    // ------------------------------------------------------------------
    // 7. Build digest if applicable
    //    Include digest only if:
    //    a) re-entering after steppedOut, OR
    //    b) after an active session ended (window closed)
    //    AND digest has not already been shown (showOnce: true).
    // ------------------------------------------------------------------
    let digest = null;
    const shouldIncludeDigest =
      session &&
      !session.digestShown &&
      (finalState === "steppedOut" ||
        (computedState === "inactive" && session && session.state === "active"));

    if (shouldIncludeDigest) {
      try {
        digest = await buildDigest(uid, sessionDate);
      } catch (err) {
        // Digest build failure must not break the evaluate call
        console.error(`[evaluateSabbathMode] buildDigest failed for uid=${uid}:`, err);
        digest = null;
      }
    }

    return {
      state: finalState,
      config,
      session,
      ...(digest ? { digest } : {}),
    };
  }
);

module.exports = { evaluateSabbathMode };

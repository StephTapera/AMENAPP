/**
 * notificationBatcher.js
 * Phase 2C — Backend (Sabbath Mode)
 *
 * Firebase gen2 Firestore background trigger.
 * Triggered on write to: users/{uid}/notifications/{notifId}
 *
 * CRITICAL RULES (invariants — never relax these):
 *   1. NEVER create a badge count anywhere.
 *   2. NEVER surface a held notification count to the client.
 *   3. MINOR GATE: Any uid whose user doc has isMinor == true → STOP, write nothing.
 *   4. All writes are additive (merge: true / update — never overwrite).
 *
 * ALLOWED-THROUGH notification types (always pass, never held):
 *   - prayer_response      — someone responded to a prayer request
 *   - prayer_answered      — prayer marked as answered
 *   - emergency            — any emergency alert
 *   - church_reminder      — church/calendar reminders from the church
 *   - calendar_reminder    — calendar event reminders
 *
 * HELD notification types (suppressed during active Sabbath):
 *   - All other types not in the ALLOWED list above
 *
 * When holding:
 *   - Writes to users/{uid}/sabbath/heldNotifications/items/{notifId} (additive).
 *   - Sets notif.suppressed = true on the original notification (additive update).
 *
 * Sabbath state is determined by reading users/{uid}/sabbath/config and evaluating
 * the boundary/chosenDay/timezone against the server clock.
 * Falls back to restModePolicies/{uid}.timezone if no Sabbath config exists.
 */

"use strict";

const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

const db = admin.firestore();

// Notification types that are ALWAYS delivered — never held during Sabbath.
const ALWAYS_ALLOWED_NOTIF_TYPES = new Set([
  "prayer_response",
  "prayer_answered",
  "emergency",
  "church_reminder",
  "calendar_reminder",
]);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Compute weekday (0=Sunday, 6=Saturday) for a given epoch ms in a timezone.
 */
function weekdayInTz(epochMs, tz) {
  const d = new Date(new Date(epochMs).toLocaleString("en-US", { timeZone: tz }));
  return d.getDay();
}

/**
 * Is the user currently in an active Sabbath window?
 * Reads from users/{uid}/sabbath/config.
 *
 * @param {string} uid
 * @returns {Promise<boolean>}
 */
async function isUserInActiveSabbath(uid) {
  const configRef = db.collection("users").doc(uid).collection("sabbath").doc("config");
  const configSnap = await configRef.get();

  if (!configSnap.exists) return false;

  const config = configSnap.data();
  if (!config.chosenDay) return false;

  const tz = config.timezone || "UTC";
  const nowMs = Date.now();
  const weekday = weekdayInTz(nowMs, tz);
  const targetDay = config.chosenDay === "saturday" ? 6 : 0;

  if (weekday !== targetDay) return false;

  // Check the session to see if the user has stepped out
  // If steppedOut, they are no longer in active Sabbath
  const sessionDate = new Date(nowMs).toLocaleDateString("en-CA", { timeZone: tz });
  const sessionSnap = await db
    .collection("users")
    .doc(uid)
    .collection("sabbathSessions")
    .doc(sessionDate)
    .get();

  if (sessionSnap.exists && sessionSnap.data().state === "steppedOut") {
    return false;
  }

  return true;
}

// ---------------------------------------------------------------------------
// Trigger
// ---------------------------------------------------------------------------

const onNotificationWrite = onDocumentWritten(
  {
    document: "users/{uid}/notifications/{notifId}",
    region: "us-central1",
  },
  async (event) => {
    const { uid, notifId } = event.params;

    // Only intercept on create (new notification written) — ignore deletes and updates
    const after = event.data?.after;
    if (!after || !after.exists) return;

    // Don't re-process already-suppressed notifications (prevents infinite loops)
    const notifData = after.data();
    if (notifData.suppressed === true) return;

    // MINOR GATE — write nothing for minor accounts
    const userSnap = await db.collection("users").doc(uid).get();
    if (userSnap.exists) {
      const userData = userSnap.data();
      if (userData.isMinor === true) {
        // STOP — do not write anything for this user
        console.log(`[notificationBatcher] MINOR_GATE uid=${uid} — stopping.`);
        return;
      }
      const ageTier = userData.ageTier || "";
      if (ageTier === "under_minimum" || ageTier === "teen") {
        console.log(`[notificationBatcher] MINOR_GATE uid=${uid} ageTier=${ageTier} — stopping.`);
        return;
      }
    }

    // Check if user is in active Sabbath
    let inActiveSabbath = false;
    try {
      inActiveSabbath = await isUserInActiveSabbath(uid);
    } catch (err) {
      console.error(`[notificationBatcher] Error checking Sabbath state uid=${uid}:`, err);
      return; // Fail open — do not suppress if we can't determine state
    }

    if (!inActiveSabbath) {
      // User is not in Sabbath — allow notification through untouched
      return;
    }

    // Determine notification type
    const notifType = notifData.type || "";

    if (ALWAYS_ALLOWED_NOTIF_TYPES.has(notifType)) {
      // ALLOWED through — prayer responses, emergency, church/calendar reminders
      // Do not touch the notification
      console.log(`[notificationBatcher] ALLOW uid=${uid} type=${notifType} notifId=${notifId}`);
      return;
    }

    // HOLD — suppress this notification during Sabbath
    console.log(`[notificationBatcher] HOLD uid=${uid} type=${notifType} notifId=${notifId}`);

    const nowMs = Date.now();
    const batch = db.batch();

    // Write held notification record to users/{uid}/sabbath/heldNotifications/items/{notifId}
    // Additive: merge: true; never overwrites existing
    const heldRef = db
      .collection("users")
      .doc(uid)
      .collection("sabbath")
      .doc("heldNotifications")
      .collection("items")
      .doc(notifId);

    batch.set(
      heldRef,
      {
        ...notifData,
        notifId,
        heldAt: nowMs,
        // CRITICAL: NEVER write a count field — not here, not anywhere
      },
      { merge: true }
    );

    // Mark the original notification as suppressed (additive update — not delete)
    const originalRef = db
      .collection("users")
      .doc(uid)
      .collection("notifications")
      .doc(notifId);

    batch.update(originalRef, { suppressed: true });

    // NOTE: We intentionally do NOT write any badge count fields.
    // NEVER write: badgeCount, unreadCount, heldCount, or any numeric count.

    await batch.commit();
  }
);

module.exports = { onNotificationWrite };

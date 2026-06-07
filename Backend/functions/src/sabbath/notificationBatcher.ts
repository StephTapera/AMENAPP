/**
 * notificationBatcher.ts — Sabbath Mode
 * Firestore trigger: users/{uid}/notifications/{notifId}
 *
 * HOLDS non-essential notifications during active Sabbath.
 * NEVER writes badge counts, held counts, or any numeric aggregate.
 * MINOR GATE: stops all writes for minor accounts.
 */

import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

const db = admin.firestore();

const ALWAYS_ALLOWED_NOTIF_TYPES = new Set([
  "prayer_response",
  "prayer_answered",
  "emergency",
  "church_reminder",
  "calendar_reminder",
]);

function weekdayInTz(epochMs: number, tz: string): number {
  return new Date(new Date(epochMs).toLocaleString("en-US", { timeZone: tz })).getDay();
}

async function isUserInActiveSabbath(uid: string): Promise<boolean> {
  const configSnap = await db.collection("users").doc(uid).collection("sabbath").doc("config").get();
  if (!configSnap.exists) return false;

  const config = configSnap.data() as { chosenDay?: string; timezone?: string };
  if (!config.chosenDay) return false;

  const tz = config.timezone ?? "UTC";
  const nowMs = Date.now();
  const weekday = weekdayInTz(nowMs, tz);
  const targetDay = config.chosenDay === "saturday" ? 6 : 0;
  if (weekday !== targetDay) return false;

  const sessionDate = new Date(nowMs).toLocaleDateString("en-CA", { timeZone: tz });
  const sessionSnap = await db
    .collection("users").doc(uid)
    .collection("sabbathSessions").doc(sessionDate).get();

  if (sessionSnap.exists && (sessionSnap.data() as { state?: string }).state === "steppedOut") {
    return false;
  }
  return true;
}

export const onSabbathNotificationWrite = onDocumentWritten(
  { document: "users/{uid}/notifications/{notifId}", region: "us-central1" },
  async (event) => {
    const { uid, notifId } = event.params;

    const after = event.data?.after;
    if (!after?.exists) return;

    const notifData = after.data() as Record<string, unknown>;
    if (notifData.suppressed === true) return;

    // MINOR GATE
    const userSnap = await db.collection("users").doc(uid).get();
    if (userSnap.exists) {
      const u = userSnap.data() as { isMinor?: boolean; ageTier?: string };
      if (u.isMinor === true || u.ageTier === "under_minimum" || u.ageTier === "teen") {
        console.log(`[notificationBatcher] MINOR_GATE uid=${uid} — stopping.`);
        return;
      }
    }

    let inActiveSabbath = false;
    try {
      inActiveSabbath = await isUserInActiveSabbath(uid);
    } catch (err) {
      console.error(`[notificationBatcher] Sabbath check failed uid=${uid}:`, err);
      return;
    }

    if (!inActiveSabbath) return;

    const notifType = (notifData.type as string) ?? "";
    if (ALWAYS_ALLOWED_NOTIF_TYPES.has(notifType)) {
      console.log(`[notificationBatcher] ALLOW uid=${uid} type=${notifType}`);
      return;
    }

    console.log(`[notificationBatcher] HOLD uid=${uid} type=${notifType} notifId=${notifId}`);
    const nowMs = Date.now();
    const batch = db.batch();

    const heldRef = db
      .collection("users").doc(uid)
      .collection("sabbath").doc("heldNotifications")
      .collection("items").doc(notifId);

    batch.set(heldRef, { ...notifData, notifId, heldAt: nowMs }, { merge: true });

    const originalRef = db.collection("users").doc(uid).collection("notifications").doc(notifId);
    batch.update(originalRef, { suppressed: true });

    // CRITICAL: never write badgeCount, unreadCount, heldCount, or any numeric count
    await batch.commit();
  }
);

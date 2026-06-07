/**
 * digestBuilder.ts — Sabbath Mode
 * Internal module only — NOT an exported callable.
 * Called by evaluateSabbathMode.
 *
 * CONTRACT:
 *   - Digest is built server-side ONLY. Never constructed client-side.
 *   - Capped at MAX_DIGEST_ITEMS (6).
 *   - items[].label: human-readable — NEVER a count.
 *   - Marks digestShown = true on session doc after building (additive).
 *   - Returns null if already shown (showOnce: true).
 */

import * as admin from "firebase-admin";

const db = admin.firestore();

const MAX_DIGEST_ITEMS = 6;

interface SabbathDigestItem {
  label: string;
  deeplink: string;
}

interface SabbathDigest {
  sessionDate: string;
  summaryLine: string;
  items: SabbathDigestItem[];
}

interface NotificationData {
  type?: string;
  title?: string;
  deeplink?: string;
  refId?: string;
  postId?: string;
  prayerId?: string;
  conversationId?: string;
  heldAt?: number;
}

const LABEL_MAP: Record<string, string> = {
  prayer_response:   "Someone responded to your prayer",
  prayer_answered:   "Your prayer was marked answered",
  prayer_support:    "Someone prayed for you",
  church_reminder:   "Church reminder",
  sermon_notes:      "Sermon notes available",
  calendar_reminder: "Calendar reminder",
  testimony:         "Someone shared a testimony",
  daily_verse:       "Today's verse is ready",
  berean_insight:    "A new Berean insight",
  new_follower:      "Someone followed you",
  post_comment:      "A comment on your post",
  post_like:         "Someone liked your post",
  mention:           "You were mentioned",
  dm:                "A message is waiting",
  opportunity:       "A volunteer opportunity",
  church_update:     "Update from your church",
};

function labelForNotification(notif: NotificationData): string {
  const type = notif.type ?? "";
  const label = LABEL_MAP[type] ?? notif.title ?? "A notification is waiting";
  return label.length > 40 ? label.substring(0, 37) + "..." : label;
}

function deeplinkForNotification(notif: NotificationData, notifId: string): string {
  if (notif.deeplink) return notif.deeplink;

  const type = notif.type ?? "";
  const refId = notif.refId ?? notif.postId ?? notif.prayerId ?? notif.conversationId ?? "";

  if (["prayer_response", "prayer_answered", "prayer_support"].includes(type)) {
    return refId ? `amenapp://prayer/${refId}` : "amenapp://prayer";
  }
  if (["church_reminder", "church_update"].includes(type)) return "amenapp://church";
  if (["sermon_notes", "calendar_reminder"].includes(type)) return "amenapp://notes";
  if (["daily_verse", "berean_insight"].includes(type)) return "amenapp://bible";
  if (["post_comment", "post_like", "testimony"].includes(type)) {
    return refId ? `amenapp://post/${refId}` : "amenapp://feed";
  }
  if (type === "mention") return refId ? `amenapp://post/${refId}` : "amenapp://notifications";
  if (type === "dm") return refId ? `amenapp://messages/${refId}` : "amenapp://messages";
  if (type === "new_follower") return "amenapp://profile";

  void notifId;
  return "amenapp://notifications";
}

export async function buildDigest(uid: string, sessionDate: string): Promise<SabbathDigest | null> {
  const sessionRef = db
    .collection("users").doc(uid)
    .collection("sabbathSessions").doc(sessionDate);

  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) return null;

  const session = sessionSnap.data() as { digestShown?: boolean };
  if (session.digestShown === true) return null;

  let heldDocs: admin.firestore.QueryDocumentSnapshot[] = [];
  try {
    const heldQuery = await db
      .collection("users").doc(uid)
      .collection("sabbath").doc("heldNotifications")
      .collection("items")
      .orderBy("heldAt", "asc")
      .get();
    heldDocs = heldQuery.docs;
  } catch {
    heldDocs = [];
  }

  const items: SabbathDigestItem[] = heldDocs.slice(0, MAX_DIGEST_ITEMS).map((doc) => {
    const notif = doc.data() as NotificationData;
    return {
      label: labelForNotification(notif),
      deeplink: deeplinkForNotification(notif, doc.id),
    };
  });

  const digest: SabbathDigest = {
    sessionDate,
    summaryLine: "You rested. Here's the short version.",
    items,
  };

  await sessionRef.set({ digestShown: true }, { merge: true });
  return digest;
}

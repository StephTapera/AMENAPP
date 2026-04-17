/**
 * CloudFunction_NotificationRoutingPipeline.ts
 *
 * Production scaffolding for AMEN's canonical notification event + payload
 * routing pipeline. This file is intentionally contract-heavy so the iOS app
 * and backend evolve against the same payload/version model.
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

type NotificationOpenBehavior =
  | "direct_open"
  | "guarded_open"
  | "inbox_open"
  | "soft_prompt";

type NotificationPayloadVersion = "2" | "3";

type AmenNotificationType =
  | "follow"
  | "follow_request"
  | "follow_request_approved"
  | "like_on_post"
  | "comment_on_post"
  | "reply_to_comment"
  | "mention_in_post"
  | "mention_in_comment"
  | "repost"
  | "quote"
  | "new_message"
  | "message_request"
  | "message_reaction"
  | "safety_guarded_message_event"
  | "prayer_reply"
  | "prayer_update"
  | "testimony_reply"
  | "testimony_reaction"
  | "church_note_reminder"
  | "church_note_growth_loop_prompt"
  | "resource_share"
  | "resource_recommendation"
  | "event_reminder"
  | "church_followed_update"
  | "moderation_update"
  | "account_warning"
  | "appeal_update"
  | "restricted_interaction_notice";

interface RouteIntentPayload {
  version: NotificationPayloadVersion;
  notificationId: string;
  type: AmenNotificationType;
  targetRouteType: string;
  routePayload: Record<string, string>;
  fallbackRouteType?: string;
  fallbackRoutePayload?: Record<string, string>;
  openBehavior: NotificationOpenBehavior;
  safetyState?: "clear" | "guarded" | "restricted" | "moderated";
}

interface CanonicalNotificationRecord extends RouteIntentPayload {
  recipientUserId: string;
  actorIds: string[];
  primaryActorId?: string;
  targetType?: string;
  targetId?: string;
  postId?: string;
  commentId?: string;
  parentCommentId?: string;
  threadId?: string;
  previewText?: string;
  aggregationKey?: string;
  unread: boolean;
  readAt?: FirebaseFirestore.Timestamp | null;
  openedAt?: FirebaseFirestore.Timestamp | null;
  deliveredAt?: FirebaseFirestore.Timestamp | null;
  invalidTarget?: boolean;
  createdAt: FirebaseFirestore.FieldValue;
  updatedAt: FirebaseFirestore.FieldValue;
}

interface PushDispatchEnvelope {
  token: string;
  apns: admin.messaging.ApnsConfig;
  data: Record<string, string>;
  notification?: admin.messaging.Notification;
}

function buildApnsConfig(record: CanonicalNotificationRecord): admin.messaging.ApnsConfig {
  return {
    headers: {
      "apns-priority": record.openBehavior === "direct_open" ? "10" : "5",
      "apns-collapse-id": record.aggregationKey ?? record.notificationId,
    },
    payload: {
      aps: {
        alert: {
          title: "AMEN",
          body: record.previewText ?? "Open AMEN to see your latest update.",
        },
        badge: 1,
        sound: "default",
        category: record.type,
        "mutable-content": 1,
      },
    },
  };
}

function buildPushEnvelope(
  token: string,
  record: CanonicalNotificationRecord
): PushDispatchEnvelope {
  return {
    token,
    apns: buildApnsConfig(record),
    notification: {
      title: "AMEN",
      body: record.previewText ?? "You have a new notification.",
    },
    data: {
      schemaVersion: record.version,
      notificationId: record.notificationId,
      type: record.type,
      targetRouteType: record.targetRouteType,
      routePayload: JSON.stringify(record.routePayload),
      fallbackRouteType: record.fallbackRouteType ?? "",
      fallbackRoutePayload: JSON.stringify(record.fallbackRoutePayload ?? {}),
      openBehavior: record.openBehavior,
      safetyState: record.safetyState ?? "clear",
    },
  };
}

export const composeNotificationPayload = functions.https.onCall(async (data) => {
  const record = data as CanonicalNotificationRecord;
  return buildPushEnvelope("dry-run-token", record);
});

export const dispatchPush = functions.https.onCall(async (data) => {
  const envelope = data as PushDispatchEnvelope;
  return admin.messaging().send({
    token: envelope.token,
    apns: envelope.apns,
    notification: envelope.notification,
    data: envelope.data,
  });
});

export const recordNotificationOpen = functions.https.onCall(async (data) => {
  const { recipientUserId, notificationId, routeResult } = data;
  await admin
    .firestore()
    .collection("users")
    .doc(recipientUserId)
    .collection("notification_open_events")
    .add({
      notificationId,
      routeResult,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  return { ok: true };
});

export const markNotificationRead = functions.https.onCall(async (data) => {
  const { recipientUserId, notificationId } = data;
  await admin
    .firestore()
    .collection("users")
    .doc(recipientUserId)
    .collection("notifications")
    .doc(notificationId)
    .set(
      {
        unread: false,
        readAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  return { ok: true };
});

export const cleanupExpiredNotifications = functions.pubsub
  .schedule("every 24 hours")
  .onRun(async () => {
    functions.logger.info("cleanupExpiredNotifications scaffold invoked");
    return null;
  });

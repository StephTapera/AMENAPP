import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";

type NotificationOpenBehavior = "directOpen" | "guardedOpen" | "inboxOpen" | "softPrompt";
type NotificationPayloadVersion = "3";
type AmenNotificationType =
  | "like_on_post"
  | "comment_on_post"
  | "reply_to_comment"
  | "prayer_supported"
  | "prayer_reply"
  | "prayer_update"
  | "verse_shared"
  | "selah_reflection"
  | "berean_insight"
  | "church_update"
  | "church_note_shared"
  | "follow"
  | "mention"
  | "repost"
  | "system";
type CanonicalCategory = "prayer" | "community" | "scripture" | "church" | "berean" | "comments" | "system";
type PriorityBucket = "P0" | "P1" | "P2" | "P3" | "P4";
type PrivacyLevel = "public" | "protected" | "sensitive";
type SafetyClass =
  | "normal"
  | "encouragement"
  | "sensitive"
  | "urgent_prayer"
  | "pastoral_care"
  | "potential_crisis"
  | "argumentative"
  | "spam"
  | "abuse";
type MeaningIntent =
  | "prayer_support"
  | "prayer_reply"
  | "prayer_update"
  | "encouragement"
  | "scripture_shared"
  | "selah_reflection"
  | "berean_insight"
  | "church_update"
  | "church_announcement"
  | "church_note"
  | "comment"
  | "reply"
  | "mention"
  | "follow"
  | "repost"
  | "general_engagement"
  | "system";

interface ActivityEventRecord {
  id: string;
  recipientId: string;
  actorId?: string;
  actorDisplayName?: string;
  actorPhotoURL?: string;
  type: AmenNotificationType;
  category?: CanonicalCategory;
  targetType?: string;
  targetId?: string;
  targetParentId?: string | null;
  title?: string;
  body?: string;
  previewText?: string;
  privacyLevel?: PrivacyLevel;
  routeType?: string;
  routePayload?: Record<string, string>;
  metadata?: Record<string, string>;
  deliveryChannel?: string;
  pushAllowed?: boolean;
  openBehavior?: NotificationOpenBehavior;
  collapseKey?: string;
  createdAt?: admin.firestore.Timestamp;
}

interface ClassificationResult {
  meaningIntent: MeaningIntent;
  safetyClass: SafetyClass;
  privacyLevel: PrivacyLevel;
  classificationConfidence: number;
  classificationSource: "rules" | "model" | "fallback";
  fallbackReason: string | null;
}

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
  id: string;
  recipientId: string;
  category: CanonicalCategory;
  priority: PriorityBucket;
  priorityScore: number;
  groupKey: string;
  title: string;
  subtitle?: string;
  previewText?: string;
  privacyLevel: PrivacyLevel;
  safetyClass: SafetyClass;
  meaningIntent: MeaningIntent;
  sourceEventIds: string[];
  actors: Array<{
    userId: string;
    displayName: string;
    photoURL?: string;
  }>;
  target: {
    type: string;
    id: string;
    parentId?: string | null;
  };
  classificationConfidence: number;
  classificationSource: "rules" | "model" | "fallback";
  fallbackReason: string | null;
  readAt?: admin.firestore.Timestamp | null;
  seenAt?: admin.firestore.Timestamp | null;
  openedAt?: admin.firestore.Timestamp | null;
  dismissedAt?: admin.firestore.Timestamp | null;
  deliveredAt?: admin.firestore.Timestamp | null;
  invalidTarget?: boolean;
  createdAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  updatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  lastEventAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
}

interface PendingNotificationRecord {
  id: string;
  notificationGroupId: string;
  recipientId: string;
  pushToken?: string;
  routePayload: Record<string, string>;
  targetRouteType: string;
  fallbackRouteType?: string;
  fallbackRoutePayload?: Record<string, string>;
  openBehavior: NotificationOpenBehavior;
  type: AmenNotificationType;
  title: string;
  body: string;
  badgeCount: number;
  status: "pending" | "retry_queued" | "sent" | "failed" | "dead_lettered";
  retryCount: number;
  maxRetries: number;
  nextAttemptAt?: admin.firestore.Timestamp;
  createdAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  updatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
}

interface PushDispatchEnvelope {
  token: string;
  apns: admin.messaging.ApnsConfig;
  data: Record<string, string>;
  notification?: admin.messaging.Notification;
}

export const canonicalNotificationCollections = {
  activityEvents: "activity_events",
  notificationGroups: "notification_groups",
  notificationGroupEvents: "notification_group_events",
  pendingNotifications: "pending_notifications",
  deliveryLogs: "notification_delivery_logs",
  deadLetters: "notification_dead_letters",
} as const;

const db = admin.firestore();
const MAX_RETRIES = 4;

function notificationMetricsRef() {
  return db.collection("notification_metrics").doc("current");
}

async function incrementMetric(metric: string, amount = 1): Promise<void> {
  await notificationMetricsRef().set(
    {
      [metric]: admin.firestore.FieldValue.increment(amount),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

function buildApnsConfig(record: PendingNotificationRecord): admin.messaging.ApnsConfig {
  return {
    headers: {
      "apns-priority": record.openBehavior === "directOpen" ? "10" : "5",
      "apns-collapse-id": record.notificationGroupId,
    },
    payload: {
      aps: {
        alert: {
          title: record.title,
          body: record.body,
        },
        badge: record.badgeCount,
        sound: "default",
        category: record.type,
        "mutable-content": 1,
      },
    },
  };
}

function buildPushEnvelope(
  token: string,
  record: PendingNotificationRecord
): PushDispatchEnvelope {
  return {
    token,
    apns: buildApnsConfig(record),
    notification: {
      title: record.title,
      body: record.body,
    },
    data: {
      schemaVersion: "3",
      notificationId: record.notificationGroupId,
      notificationGroupId: record.notificationGroupId,
      type: record.type,
      targetRouteType: record.targetRouteType,
      routePayload: JSON.stringify(record.routePayload),
      fallbackRouteType: record.fallbackRouteType ?? "",
      fallbackRoutePayload: JSON.stringify(record.fallbackRoutePayload ?? {}),
      openBehavior: record.openBehavior,
      safetyState: "clear",
    },
  };
}

function canonicalCategoryForType(type: AmenNotificationType): CanonicalCategory {
  switch (type) {
  case "prayer_supported":
  case "prayer_reply":
  case "prayer_update":
    return "prayer";
  case "verse_shared":
  case "selah_reflection":
    return "scripture";
  case "church_update":
  case "church_note_shared":
    return "church";
  case "berean_insight":
    return "berean";
  case "comment_on_post":
  case "reply_to_comment":
  case "mention":
    return "comments";
  case "follow":
  case "like_on_post":
  case "repost":
    return "community";
  case "system":
  default:
    return "system";
  }
}

function classifyEvent(event: ActivityEventRecord): ClassificationResult {
  const body = (event.body ?? "").toLowerCase();
  let result: ClassificationResult = {
    meaningIntent: "general_engagement",
    safetyClass: "normal",
    privacyLevel: event.privacyLevel ?? "public",
    classificationConfidence: 0.88,
    classificationSource: "rules",
    fallbackReason: null,
  };

  switch (event.type) {
  case "prayer_supported":
    result.meaningIntent = "prayer_support";
    result.privacyLevel = event.privacyLevel ?? "protected";
    result.safetyClass = "encouragement";
    break;
  case "prayer_reply":
    result.meaningIntent = "prayer_reply";
    result.privacyLevel = event.privacyLevel ?? "protected";
    result.safetyClass = body.includes("pastor") ? "pastoral_care" : "urgent_prayer";
    break;
  case "prayer_update":
    result.meaningIntent = "prayer_update";
    result.privacyLevel = event.privacyLevel ?? "protected";
    break;
  case "verse_shared":
    result.meaningIntent = "scripture_shared";
    result.privacyLevel = event.privacyLevel ?? "protected";
    result.safetyClass = "encouragement";
    break;
  case "selah_reflection":
    result.meaningIntent = "selah_reflection";
    result.privacyLevel = event.privacyLevel ?? "protected";
    break;
  case "berean_insight":
    result.meaningIntent = "berean_insight";
    result.privacyLevel = event.privacyLevel ?? "protected";
    break;
  case "church_update":
    result.meaningIntent = body.includes("announcement") ? "church_announcement" : "church_update";
    result.safetyClass = body.includes("urgent") ? "pastoral_care" : "normal";
    break;
  case "church_note_shared":
    result.meaningIntent = "church_note";
    break;
  case "comment_on_post":
    result.meaningIntent = "comment";
    break;
  case "reply_to_comment":
    result.meaningIntent = "reply";
    break;
  case "mention":
    result.meaningIntent = "mention";
    break;
  case "follow":
    result.meaningIntent = "follow";
    break;
  case "repost":
    result.meaningIntent = "repost";
    break;
  case "like_on_post":
    result.meaningIntent = "encouragement";
    break;
  case "system":
  default:
    result.meaningIntent = "system";
    result.classificationSource = "fallback";
    result.classificationConfidence = 0.4;
    result.fallbackReason = "unknown_or_system_type";
    break;
  }

  if (body.includes("crisis") || body.includes("suicide")) {
    result.safetyClass = "potential_crisis";
    result.privacyLevel = "sensitive";
  } else if (body.includes("private") || body.includes("sensitive")) {
    result.safetyClass = "sensitive";
    result.privacyLevel = "sensitive";
  }

  return result;
}

function computePriority(classification: ClassificationResult): { bucket: PriorityBucket; score: number } {
  switch (classification.meaningIntent) {
  case "prayer_reply":
    return { bucket: "P0", score: 100 };
  case "prayer_support":
  case "prayer_update":
  case "church_update":
  case "church_announcement":
  case "reply":
    return { bucket: "P1", score: 88 };
  case "comment":
  case "mention":
  case "scripture_shared":
  case "selah_reflection":
  case "berean_insight":
  case "church_note":
    return { bucket: "P2", score: 74 };
  case "follow":
  case "repost":
  case "encouragement":
    return { bucket: "P3", score: 52 };
  case "general_engagement":
  case "system":
  default:
    return { bucket: "P4", score: 24 };
  }
}

function buildGroupKey(event: ActivityEventRecord, classification: ClassificationResult): string {
  const targetType = event.targetType ?? "system";
  const targetId = event.targetId ?? event.id;
  return `${targetType}:${targetId}:${classification.meaningIntent}`;
}

function privacySafePreview(event: ActivityEventRecord, classification: ClassificationResult): string {
  if (classification.privacyLevel !== "public" || classification.classificationConfidence < 0.65) {
    switch (classification.meaningIntent) {
    case "prayer_support":
      return "Your private prayer request received support.";
    case "prayer_reply":
      return classification.safetyClass === "pastoral_care"
        ? "A church leader responded to your request."
        : "Someone responded with care.";
    default:
      return "You have a protected activity update.";
    }
  }

  return event.previewText ?? event.body ?? "Open AMEN to view this update.";
}

function selectActors(event: ActivityEventRecord): CanonicalNotificationRecord["actors"] {
  if (!event.actorId) {
    return [];
  }

  return [{
    userId: event.actorId,
    displayName: event.actorDisplayName ?? "Someone",
    photoURL: event.actorPhotoURL,
  }];
}

function buildRoute(event: ActivityEventRecord, classification: ClassificationResult): Pick<
CanonicalNotificationRecord,
"targetRouteType" | "routePayload" | "fallbackRouteType" | "fallbackRoutePayload" | "openBehavior"
> {
  if (event.routeType && event.routePayload) {
    return {
      targetRouteType: event.routeType,
      routePayload: event.routePayload,
      fallbackRouteType: "notifications_inbox",
      fallbackRoutePayload: {},
      openBehavior: event.openBehavior ?? "directOpen",
    };
  }

  const targetType = event.targetType ?? "system";
  const targetId = event.targetId ?? event.id;

  switch (targetType) {
  case "prayer_request":
    return {
      targetRouteType: "prayer",
      routePayload: { prayerId: targetId },
      fallbackRouteType: "notifications_inbox",
      fallbackRoutePayload: {},
      openBehavior: classification.meaningIntent === "prayer_reply" ? "guardedOpen" : "directOpen",
    };
  case "church_note":
    return {
      targetRouteType: "church_note",
      routePayload: { noteId: targetId },
      fallbackRouteType: "notifications_inbox",
      fallbackRoutePayload: {},
      openBehavior: "directOpen",
    };
  case "church":
    return {
      targetRouteType: classification.meaningIntent === "church_announcement" ? "church_announcement" : "church_page",
      routePayload: classification.meaningIntent === "church_announcement"
        ? { churchId: targetId, announcementId: event.metadata?.announcementId ?? targetId }
        : { churchId: targetId },
      fallbackRouteType: "notifications_inbox",
      fallbackRoutePayload: {},
      openBehavior: "directOpen",
    };
  case "berean":
    return {
      targetRouteType: "berean_insight",
      routePayload: { noteId: targetId },
      fallbackRouteType: "notifications_inbox",
      fallbackRoutePayload: {},
      openBehavior: "directOpen",
    };
  case "selah":
    return {
      targetRouteType: "selah",
      routePayload: { noteId: targetId },
      fallbackRouteType: "notifications_inbox",
      fallbackRoutePayload: {},
      openBehavior: "directOpen",
    };
  case "comment":
    return {
      targetRouteType: "post_reply",
      routePayload: {
        postId: event.metadata?.postId ?? targetId,
        commentId: targetId,
        parentCommentId: event.targetParentId ?? targetId,
      },
      fallbackRouteType: "post",
      fallbackRoutePayload: { postId: event.metadata?.postId ?? targetId },
      openBehavior: "directOpen",
    };
  case "post":
  default:
    return {
      targetRouteType: event.metadata?.commentId ? "post_comment" : "post",
      routePayload: event.metadata?.commentId
        ? { postId: targetId, commentId: event.metadata.commentId }
        : { postId: targetId },
      fallbackRouteType: "notifications_inbox",
      fallbackRoutePayload: {},
      openBehavior: event.openBehavior ?? "directOpen",
    };
  }
}

function buildGroupTitle(event: ActivityEventRecord, classification: ClassificationResult): string {
  const actor = event.actorDisplayName ?? "Someone";
  switch (classification.meaningIntent) {
  case "prayer_support":
    return `${actor} supported your prayer request.`;
  case "prayer_reply":
    return `${actor} replied to your prayer request.`;
  case "prayer_update":
    return `${actor} asked for an update on your prayer request.`;
  case "scripture_shared":
    return `${actor} shared Scripture with you.`;
  case "selah_reflection":
    return `${actor} responded to your Selah reflection.`;
  case "berean_insight":
    return "Berean found a new insight for you.";
  case "church_update":
  case "church_announcement":
    return event.title ?? "Your church posted an update.";
  case "church_note":
    return `${actor} shared a church note with you.`;
  case "comment":
    return `${actor} commented on your post.`;
  case "reply":
    return `${actor} replied to your comment.`;
  case "mention":
    return `${actor} mentioned you.`;
  case "follow":
    return `${actor} started following you.`;
  case "repost":
    return `${actor} reposted your post.`;
  case "encouragement":
    return `${actor} encouraged your post.`;
  default:
    return event.title ?? "You have a new AMEN activity update.";
  }
}

function buildGroupSubtitle(event: ActivityEventRecord, classification: ClassificationResult): string | undefined {
  const preview = privacySafePreview(event, classification);
  return preview === buildGroupTitle(event, classification) ? undefined : preview;
}

function buildCanonicalRecord(event: ActivityEventRecord): CanonicalNotificationRecord {
  const classification = classifyEvent(event);
  const priority = computePriority(classification);
  const route = buildRoute(event, classification);
  const now = admin.firestore.FieldValue.serverTimestamp();
  return {
    id: buildGroupKey(event, classification),
    recipientId: event.recipientId,
    category: event.category ?? canonicalCategoryForType(event.type),
    priority: priority.bucket,
    priorityScore: priority.score,
    groupKey: buildGroupKey(event, classification),
    title: buildGroupTitle(event, classification),
    subtitle: buildGroupSubtitle(event, classification),
    previewText: privacySafePreview(event, classification),
    privacyLevel: classification.privacyLevel,
    safetyClass: classification.safetyClass,
    meaningIntent: classification.meaningIntent,
    sourceEventIds: [event.id],
    actors: selectActors(event),
    target: {
      type: event.targetType ?? "system",
      id: event.targetId ?? event.id,
      parentId: event.targetParentId ?? null,
    },
    classificationConfidence: classification.classificationConfidence,
    classificationSource: classification.classificationSource,
    fallbackReason: classification.fallbackReason,
    version: "3",
    notificationId: buildGroupKey(event, classification),
    type: event.type,
    targetRouteType: route.targetRouteType,
    routePayload: route.routePayload,
    fallbackRouteType: route.fallbackRouteType,
    fallbackRoutePayload: route.fallbackRoutePayload,
    openBehavior: route.openBehavior,
    safetyState: classification.safetyClass === "potential_crisis" ? "guarded" : "clear",
    createdAt: now,
    updatedAt: now,
    lastEventAt: now,
  };
}

async function isSuppressed(event: ActivityEventRecord): Promise<boolean> {
  if (!event.actorId) {
    return false;
  }

  const [blockedDoc, mutedDoc] = await Promise.all([
    db.collection("users").doc(event.recipientId).collection("blockedUsers").doc(event.actorId).get(),
    db.collection("users").doc(event.recipientId).collection("mutedUsers").doc(event.actorId).get(),
  ]);

  return blockedDoc.exists || mutedDoc.exists;
}

async function computeBadgeCount(recipientId: string): Promise<number> {
  const snapshot = await db.collection(canonicalNotificationCollections.notificationGroups)
    .where("recipientId", "==", recipientId)
    .where("dismissedAt", "==", null)
    .where("readAt", "==", null)
    .get();
  return snapshot.size;
}

async function fetchPushTokens(recipientId: string): Promise<string[]> {
  const userDoc = await db.collection("users").doc(recipientId).get();
  const directTokens = userDoc.get("pushTokens");
  if (Array.isArray(directTokens) && directTokens.length > 0) {
    return directTokens.filter((token): token is string => typeof token === "string" && token.length > 0);
  }

  const tokenSnapshot = await db.collection("users").doc(recipientId).collection("deviceTokens").get();
  return tokenSnapshot.docs
    .map((doc) => doc.get("token"))
    .filter((token): token is string => typeof token === "string" && token.length > 0);
}

async function writeDeliveryLog(data: Record<string, unknown>): Promise<void> {
  await db.collection(canonicalNotificationCollections.deliveryLogs).add({
    ...data,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function deadLetter(pendingId: string, reason: string, payload: PendingNotificationRecord): Promise<void> {
  await db.collection(canonicalNotificationCollections.deadLetters).doc(pendingId).set({
    ...payload,
    deadLetteredAt: admin.firestore.FieldValue.serverTimestamp(),
    reason,
  }, { merge: true });
  await incrementMetric("dead_letter_count");
}

async function enqueuePushForGroup(record: CanonicalNotificationRecord): Promise<void> {
  const tokens = await fetchPushTokens(record.recipientId);
  if (tokens.length === 0) {
    await incrementMetric("push_failure_count");
    return;
  }

  const badgeCount = await computeBadgeCount(record.recipientId);
  const pendingCollection = db.collection(canonicalNotificationCollections.pendingNotifications);
  await Promise.all(tokens.map((token, index) => {
    const pendingId = `${record.id}_${index}`;
    const pendingRecord: PendingNotificationRecord = {
      id: pendingId,
      notificationGroupId: record.id,
      recipientId: record.recipientId,
      pushToken: token,
      routePayload: record.routePayload,
      targetRouteType: record.targetRouteType,
      fallbackRouteType: record.fallbackRouteType,
      fallbackRoutePayload: record.fallbackRoutePayload,
      openBehavior: record.openBehavior,
      type: record.type,
      title: record.title,
      body: record.previewText ?? "Open AMEN to view this update.",
      badgeCount,
      status: "pending",
      retryCount: 0,
      maxRetries: MAX_RETRIES,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    return pendingCollection.doc(pendingId).set(pendingRecord, { merge: true });
  }));
}

async function processPendingNotificationDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): Promise<void> {
  if (!doc.exists) {
    return;
  }

  const record = doc.data() as PendingNotificationRecord;
  if (!record.pushToken) {
    await deadLetter(doc.id, "missing_push_token", record);
    await doc.ref.set({ status: "dead_lettered", updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    return;
  }

  try {
    const envelope = buildPushEnvelope(record.pushToken, record);
    const response = await admin.messaging().send({
      token: envelope.token,
      apns: envelope.apns,
      notification: envelope.notification,
      data: envelope.data,
    });

    await doc.ref.set({
      status: "sent",
      providerMessageId: response,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await db.collection(canonicalNotificationCollections.notificationGroups)
      .doc(record.notificationGroupId)
      .set({
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

    await writeDeliveryLog({
      pendingNotificationId: doc.id,
      notificationGroupId: record.notificationGroupId,
      recipientId: record.recipientId,
      status: "sent",
      providerMessageId: response,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_push_error";
    const retryCount = (record.retryCount ?? 0) + 1;
    const transient = /timeout|unavailable|internal|429|500/i.test(message);

    await writeDeliveryLog({
      pendingNotificationId: doc.id,
      notificationGroupId: record.notificationGroupId,
      recipientId: record.recipientId,
      status: "failed",
      error: message,
      retryCount,
    });

    if (transient && retryCount < (record.maxRetries ?? MAX_RETRIES)) {
      const nextAttempt = admin.firestore.Timestamp.fromMillis(
        Date.now() + Math.pow(2, retryCount) * 60_000
      );
      await doc.ref.set({
        status: "retry_queued",
        retryCount,
        nextAttemptAt: nextAttempt,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      await incrementMetric("push_failure_count");
      return;
    }

    await deadLetter(doc.id, message, record);
    await doc.ref.set({
      status: "dead_lettered",
      retryCount,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }
}

export const composeNotificationPayload = onCall(async (request) => {
  // B-25: Auth guard — these callables must only be invoked by authenticated service accounts
  // or signed-in users with the internal_service custom claim.
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const isInternalService = (request.auth.token as Record<string, unknown>)?.internal_service === true;
  const isAdmin = (request.auth.token as Record<string, unknown>)?.admin === true;
  if (!isInternalService && !isAdmin) {
    throw new HttpsError("permission-denied", "Internal service access only.");
  }
  const record = request.data as PendingNotificationRecord;
  return buildPushEnvelope(record.pushToken ?? "dry-run-token", record);
});

export const dispatchPush = onCall(async (request) => {
  // B-25: Auth guard — only internal services may directly dispatch push messages.
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const isInternalService = (request.auth.token as Record<string, unknown>)?.internal_service === true;
  const isAdmin = (request.auth.token as Record<string, unknown>)?.admin === true;
  if (!isInternalService && !isAdmin) {
    throw new HttpsError("permission-denied", "Internal service access only.");
  }
  const envelope = request.data as PushDispatchEnvelope;
  return admin.messaging().send({
    token: envelope.token,
    apns: envelope.apns,
    notification: envelope.notification,
    data: envelope.data,
  });
});

export const processActivityEvent = onDocumentCreated(
  { document: `${canonicalNotificationCollections.activityEvents}/{eventId}`, region: "us-central1" },
  async (firestoreEvent) => {
    const snapshot = firestoreEvent.data!;
    const event = snapshot.data() as ActivityEventRecord;
    if (!event || !event.recipientId || !event.type) {
      await incrementMetric("schema_violation_count");
      logger.error("Invalid activity event", { id: snapshot.id, data: snapshot.data() });
      return;
    }

    if (await isSuppressed(event)) {
      await incrementMetric("suppressed_event_count");
      await snapshot.ref.set({ status: "suppressed", updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
      return;
    }

    const record = buildCanonicalRecord({ ...event, id: event.id ?? snapshot.id });
    const groupRef = db.collection(canonicalNotificationCollections.notificationGroups).doc(record.id);
    const linkRef = db.collection(canonicalNotificationCollections.notificationGroupEvents).doc(snapshot.id);

    await db.runTransaction(async (transaction) => {
      const [linkSnap, groupSnap] = await Promise.all([
        transaction.get(linkRef),
        transaction.get(groupRef),
      ]);

      if (linkSnap.exists) {
        throw new HttpsError("already-exists", "Duplicate activity event");
      }

      if (groupSnap.exists) {
        const existing = groupSnap.data() as CanonicalNotificationRecord;
        const existingEventIds = existing.sourceEventIds ?? [];
        transaction.set(groupRef, {
          sourceEventIds: Array.from(new Set([...existingEventIds, snapshot.id])),
          actors: record.actors.length > 0
            ? [...record.actors, ...(existing.actors ?? [])].slice(0, 3)
            : existing.actors ?? [],
          title: existing.title ?? record.title,
          subtitle: record.subtitle ?? existing.subtitle ?? null,
          previewText: record.previewText,
          priority: record.priority,
          priorityScore: Math.max(existing.priorityScore ?? 0, record.priorityScore),
          category: record.category,
          meaningIntent: record.meaningIntent,
          safetyClass: record.safetyClass,
          privacyLevel: record.privacyLevel,
          lastEventAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          readAt: null,
          dismissedAt: null,
        }, { merge: true });
      } else {
        transaction.set(groupRef, {
          ...record,
          id: record.id,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          lastEventAt: admin.firestore.FieldValue.serverTimestamp(),
          readAt: null,
          seenAt: null,
          openedAt: null,
          dismissedAt: null,
        });
      }

      transaction.set(linkRef, {
        eventId: snapshot.id,
        notificationGroupId: record.id,
        recipientId: record.recipientId,
        groupKey: record.groupKey,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }).catch(async (error) => {
      const message = error instanceof Error ? error.message : "unknown_grouping_error";
      if (message.includes("Duplicate activity event")) {
        await incrementMetric("duplicate_event_count");
        return;
      }
      throw error;
    });

    if (event.pushAllowed !== false && record.priority !== "P4") {
      await enqueuePushForGroup(record);
    }

    await snapshot.ref.set({
      status: "processed",
      notificationGroupId: record.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });

export const processPendingNotification = onDocumentCreated(
  { document: `${canonicalNotificationCollections.pendingNotifications}/{pendingId}`, region: "us-central1" },
  async (firestoreEvent) => {
    await processPendingNotificationDoc(firestoreEvent.data!);
  });

export const retryPendingNotifications = onSchedule(
  { schedule: "every 15 minutes", region: "us-central1" },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const snapshot = await db.collection(canonicalNotificationCollections.pendingNotifications)
      .where("status", "==", "retry_queued")
      .where("nextAttemptAt", "<=", now)
      .limit(50)
      .get();

    await Promise.all(snapshot.docs.map((doc) => processPendingNotificationDoc(doc)));
    return null;
  });

export const cleanupExpiredNotifications = onSchedule(
  { schedule: "every 24 hours", region: "us-central1" },
  async () => {
    const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const [dismissedGroups, oldLogs] = await Promise.all([
      db.collection(canonicalNotificationCollections.notificationGroups)
        .where("dismissedAt", "<=", cutoff)
        .limit(100)
        .get(),
      db.collection(canonicalNotificationCollections.deliveryLogs)
        .where("createdAt", "<=", cutoff)
        .limit(100)
        .get(),
    ]);

    const batch = db.batch();
    dismissedGroups.docs.forEach((doc) => {
      batch.set(doc.ref, { archivedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    });
    oldLogs.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    return null;
  });

export const recordNotificationOpen = onCall(async (request) => {
  // B-25: Auth guard — must be the notification recipient or an internal service.
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const { recipientUserId, notificationId, routeResult } = request.data as { recipientUserId: string; notificationId: string; routeResult: unknown };
  const isInternalService = (request.auth.token as Record<string, unknown>)?.internal_service === true;
  const isAdmin = (request.auth.token as Record<string, unknown>)?.admin === true;
  if (!isInternalService && !isAdmin && request.auth.uid !== recipientUserId) {
    throw new HttpsError("permission-denied", "Can only record opens for your own notifications.");
  }
  await db.collection(canonicalNotificationCollections.notificationGroups)
    .doc(notificationId)
    .set({
      openedAt: admin.firestore.FieldValue.serverTimestamp(),
      readAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  await writeDeliveryLog({
    recipientUserId,
    notificationId,
    routeResult,
    status: "opened",
  });
  return { ok: true };
});

export const markNotificationRead = onCall(async (request) => {
  // B-25: Auth guard — must be the notification recipient.
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const { recipientUserId, notificationId } = request.data as { recipientUserId: string; notificationId: string };
  const isInternalService = (request.auth.token as Record<string, unknown>)?.internal_service === true;
  const isAdmin = (request.auth.token as Record<string, unknown>)?.admin === true;
  if (!isInternalService && !isAdmin && request.auth.uid !== recipientUserId) {
    throw new HttpsError("permission-denied", "Can only mark your own notifications as read.");
  }
  await db.collection(canonicalNotificationCollections.notificationGroups)
    .doc(notificationId)
    .set(
      {
        recipientId: recipientUserId,
        readAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  return { ok: true };
});

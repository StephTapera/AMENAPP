import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import {
  BereanPulseCardRecord,
  BereanPulseEventRecord,
  BereanPulsePermissionDocument,
  BereanPulsePreferenceDocument,
  BereanPulseSignal,
  buildBereanPulseCards,
  normalizePermissions,
} from "./bereanPulseEngine";
import { requireAppCheck } from "./trustIntelligence";

const db = admin.firestore();

type FirestoreLikeTimestamp = admin.firestore.Timestamp;

export const bereanPulseFirestoreContract = {
  rootCollection: "bereanPulse",
  rootDocument: "main",
  daysCollection: "days",
  cardsCollection: "cards",
  preferencesCollection: "preferences",
  permissionsCollection: "permissions",
  singletonDocument: "main",
  eventsCollection: "events",
  savedCardsCollection: "savedCards",
} as const;

interface PulseRootRefs {
  userRef: FirebaseFirestore.DocumentReference;
  pulseCollection: FirebaseFirestore.CollectionReference;
}

function pulseRefs(userId: string): PulseRootRefs {
  const userRef = db.collection("users").doc(userId);
  return {
    userRef,
    pulseCollection: userRef.collection(bereanPulseFirestoreContract.rootCollection),
  };
}

function dayCardsCollection(userId: string, dateKey: string) {
  return pulseRefs(userId)
    .pulseCollection
    .doc(bereanPulseFirestoreContract.rootDocument)
    .collection(bereanPulseFirestoreContract.daysCollection)
    .doc(dateKey)
    .collection(bereanPulseFirestoreContract.cardsCollection);
}

function preferencesDoc(userId: string) {
  return pulseRefs(userId)
    .pulseCollection
    .doc(bereanPulseFirestoreContract.rootDocument)
    .collection(bereanPulseFirestoreContract.preferencesCollection)
    .doc(bereanPulseFirestoreContract.singletonDocument);
}

function permissionsDoc(userId: string) {
  return pulseRefs(userId)
    .pulseCollection
    .doc(bereanPulseFirestoreContract.rootDocument)
    .collection(bereanPulseFirestoreContract.permissionsCollection)
    .doc(bereanPulseFirestoreContract.singletonDocument);
}

function eventsCollection(userId: string) {
  return pulseRefs(userId)
    .pulseCollection
    .doc(bereanPulseFirestoreContract.rootDocument)
    .collection(bereanPulseFirestoreContract.eventsCollection);
}

function savedCardsCollection(userId: string) {
  return pulseRefs(userId)
    .pulseCollection
    .doc(bereanPulseFirestoreContract.rootDocument)
    .collection(bereanPulseFirestoreContract.savedCardsCollection);
}

function pulseRootDoc(userId: string) {
  return pulseRefs(userId)
    .pulseCollection
    .doc(bereanPulseFirestoreContract.rootDocument);
}

function dateKeyFor(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

async function loadPermissions(userId: string): Promise<BereanPulsePermissionDocument> {
  const snapshot = await permissionsDoc(userId).get();
  return (snapshot.data() ?? {}) as BereanPulsePermissionDocument;
}

async function loadPreferences(userId: string): Promise<BereanPulsePreferenceDocument> {
  const snapshot = await preferencesDoc(userId).get();
  return (snapshot.data() ?? { enabled: true }) as BereanPulsePreferenceDocument;
}

async function loadRecentFeedback(userId: string): Promise<BereanPulseEventRecord[]> {
  const snapshot = await eventsCollection(userId)
    .orderBy("timestamp", "desc")
    .limit(80)
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data() as Record<string, unknown>;
    return {
      id: doc.id,
      cardId: String(data.cardId ?? ""),
      eventType: String(data.eventType ?? "viewed") as BereanPulseEventRecord["eventType"],
      mode: typeof data.mode === "string" ? data.mode as BereanPulseEventRecord["mode"] : undefined,
      metadata: (data.metadata as Record<string, string> | undefined) ?? {},
      timestamp: (data.timestamp as FirestoreLikeTimestamp | undefined) ?? admin.firestore.Timestamp.now(),
    };
  });
}

async function collectBereanConversationSignals(
  userId: string,
  granted: boolean
): Promise<BereanPulseSignal[]> {
  if (!granted) return [];

  const conversations = await db.collection("berean_conversations")
    .where("userId", "==", userId)
    .limit(8)
    .get();

  const signals: BereanPulseSignal[] = [];

  for (const conversationDoc of conversations.docs) {
    const conversationData = conversationDoc.data() as Record<string, unknown>;
    const messagesSnapshot = await db.collection("berean_messages")
      .where("conversationId", "==", conversationDoc.id)
      .orderBy("createdAt", "desc")
      .limit(4)
      .get();

    const messages = messagesSnapshot.docs.map((doc) => ({
      id: doc.id,
      ...(doc.data() as Record<string, unknown>),
    })) as Array<{
      id: string;
      role?: string;
      content?: string;
      createdAt?: FirestoreLikeTimestamp;
    }>;
    const newest = messages[0];
    const newestTimestamp = (newest?.createdAt as FirestoreLikeTimestamp | undefined) ??
      (conversationData.lastUpdated as FirestoreLikeTimestamp | undefined) ??
      admin.firestore.Timestamp.now();
    const title = String(conversationData.title ?? "Berean conversation");
    const currentMode = String(conversationData.currentMode ?? "chat");
    const latestUserMessage = messages.find((message) => message.role === "user");
    const assistantAfterUser = latestUserMessage ?
      messages.some((message) =>
        message.role === "assistant" &&
        ((message.createdAt as FirestoreLikeTimestamp | undefined)?.toMillis() ?? 0) >
          ((latestUserMessage.createdAt as FirestoreLikeTimestamp | undefined)?.toMillis() ?? 0)
      ) :
      false;
    const unresolved = Boolean(latestUserMessage) && !assistantAfterUser;
    const summary = unresolved && latestUserMessage?.content
      ? `Your ${currentMode} thread "${title}" is waiting on a response to: ${String(latestUserMessage.content).slice(0, 140)}`
      : `Recent Berean activity in "${title}" was active enough to continue today.`;

    signals.push({
      id: `chat_${conversationDoc.id}`,
      source: "bereanChatHistory",
      sourceRecordId: conversationDoc.id,
      title: unresolved ? "Unfinished Berean thread" : "Recent Berean conversation",
      summary,
      timestamp: newestTimestamp,
      sensitivity: "personal",
      permissionRequired: true,
      permissionGranted: true,
      hashForDeduplication: `chat:${conversationDoc.id}:${unresolved ? "open" : "recent"}`,
      isUserVisible: true,
      entityType: "conversation",
      entityId: conversationDoc.id,
      metadata: {
        intent: unresolved ? "openLoopResolution" : "spiritualFormation",
        conversationId: conversationDoc.id,
        mode: currentMode,
        openLoop: unresolved ? "true" : "false",
      },
    });
  }

  return signals;
}

async function collectSavedPostSignals(
  userId: string,
  granted: boolean
): Promise<BereanPulseSignal[]> {
  if (!granted) return [];

  const snapshot = await db.collection("users")
    .doc(userId)
    .collection("savedPosts")
    .limit(10)
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data() as Record<string, unknown>;
    const savedAt = (data.savedAt as FirestoreLikeTimestamp | undefined) ?? admin.firestore.Timestamp.now();
    const postId = String(data.postId ?? doc.id);
    const title = String(data.postTitle ?? "Saved post");
    const revisitedAt = data.revisitedAt as FirestoreLikeTimestamp | undefined;
    const openLoop = !revisitedAt;

    return {
      id: `saved_${doc.id}`,
      source: "savedPosts",
      sourceRecordId: doc.id,
      title: openLoop ? "Saved post not revisited" : "Saved post activity",
      summary: openLoop
        ? `You saved "${title}" and have not gone back to it yet.`
        : `You returned to "${title}" recently, which makes it a good continuation candidate.`,
      timestamp: revisitedAt ?? savedAt,
      sensitivity: "low",
      permissionRequired: true,
      permissionGranted: true,
      hashForDeduplication: `saved:${postId}`,
      isUserVisible: true,
      entityType: "post",
      entityId: postId,
      metadata: {
        intent: openLoop ? "openLoopResolution" : "learningContinuation",
        postId,
        openLoop: openLoop ? "true" : "false",
      },
    };
  });
}

async function collectChurchSignals(
  userId: string,
  granted: boolean
): Promise<BereanPulseSignal[]> {
  if (!granted) return [];

  const snapshot = await db.collection("users")
    .doc(userId)
    .collection("churchInteractions")
    .limit(10)
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data() as Record<string, unknown>;
    const phase = String(data.phase ?? "discovered");
    const churchId = doc.id;
    const churchName = String(data.churchName ?? "church");
    const updatedAt = (data.updatedAt as FirestoreLikeTimestamp | undefined) ??
      (data.createdAt as FirestoreLikeTimestamp | undefined) ??
      admin.firestore.Timestamp.now();
    const unresolvedPhases = new Set(["discovered", "interested", "planning", "ready", "attended"]);
    const openLoop = unresolvedPhases.has(phase) && phase !== "reflected" && phase !== "returned";

    return {
      id: `church_${churchId}`,
      source: "churchActivity",
      sourceRecordId: churchId,
      title: openLoop ? "Church follow-through pending" : "Church activity",
      summary: openLoop
        ? `Your ${churchName} journey is still in ${phase} and has not been fully completed.`
        : `You recently interacted with ${churchName}.`,
      timestamp: updatedAt,
      sensitivity: "personal",
      permissionRequired: true,
      permissionGranted: true,
      hashForDeduplication: `church:${churchId}:${phase}`,
      isUserVisible: true,
      entityType: "church",
      entityId: churchId,
      metadata: {
        intent: openLoop ? "openLoopResolution" : "churchDiscovery",
        churchId,
        churchName,
        openLoop: openLoop ? "true" : "false",
      },
    };
  });
}

async function collectReflectionSignals(
  userId: string,
  granted: boolean
): Promise<BereanPulseSignal[]> {
  if (!granted) return [];

  const snapshot = await db.collection("users")
    .doc(userId)
    .collection("reflectionEntries")
    .orderBy("updatedAt", "desc")
    .limit(8)
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data() as Record<string, unknown>;
    const updatedAt = (data.updatedAt as FirestoreLikeTimestamp | undefined) ??
      (data.createdAt as FirestoreLikeTimestamp | undefined) ??
      admin.firestore.Timestamp.now();
    const title = String(data.title ?? data.passageReference ?? "Prayer reflection");
    const text = String(data.text ?? data.content ?? "").slice(0, 160);
    const openLoop = data.sourceType === "follow_up" || Boolean(text);

    return {
      id: `reflection_${doc.id}`,
      source: "prayerJournal",
      sourceRecordId: doc.id,
      title: "Private reflection you can continue",
      summary: text
        ? `You left a private reflection in "${title}": ${text}`
        : `You have a private reflection in "${title}" that can be continued.`,
      timestamp: updatedAt,
      sensitivity: "sensitive",
      permissionRequired: true,
      permissionGranted: true,
      hashForDeduplication: `reflection:${doc.id}`,
      isUserVisible: true,
      entityType: "reflection",
      entityId: doc.id,
      metadata: {
        intent: "prayerContinuation",
        entryId: doc.id,
        openLoop: openLoop ? "true" : "false",
      },
    };
  });
}

async function collectNotificationSignals(
  userId: string,
  granted: boolean
): Promise<BereanPulseSignal[]> {
  if (!granted) return [];

  const snapshot = await db.collection("users")
    .doc(userId)
    .collection("notifications")
    .where("read", "==", false)
    .limit(10)
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data() as Record<string, unknown>;
    const type = String(data.type ?? "notification");
    const createdAt = (data.createdAt as FirestoreLikeTimestamp | undefined) ?? admin.firestore.Timestamp.now();
    const conversationId = typeof data.conversationId === "string" ? data.conversationId : "";
    const recipientId = typeof data.actorId === "string" ? data.actorId : "";

    return {
      id: `notification_${doc.id}`,
      source: "notifications",
      sourceRecordId: doc.id,
      title: "Unread activity still needs attention",
      summary: `An unread ${type} notification still needs a follow-up.`,
      timestamp: createdAt,
      sensitivity: "personal",
      permissionRequired: true,
      permissionGranted: true,
      hashForDeduplication: `notification:${doc.id}`,
      isUserVisible: true,
      entityType: conversationId ? "messageThread" : "notification",
      entityId: conversationId || doc.id,
      metadata: {
        intent: "relationshipFollowUp",
        conversationId,
        recipientId,
        openLoop: "true",
      },
    };
  });
}

async function collectProjectSignals(
  userId: string,
  granted: boolean
): Promise<BereanPulseSignal[]> {
  if (!granted) return [];

  const snapshot = await db.collection("users")
    .doc(userId)
    .collection("creatorProjects")
    .limit(10)
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data() as Record<string, unknown>;
    const status = String(data.status ?? "draft");
    const title = String(data.title ?? "Untitled Project");
    const updatedAt = (data.lastEditedAt as FirestoreLikeTimestamp | undefined) ??
      (data.createdAt as FirestoreLikeTimestamp | undefined) ??
      admin.firestore.Timestamp.now();
    const openLoop = status === "draft" || status === "failed" || status === "processing";
    const intent =
      status === "draft" ? "creativeContinuation" :
      status === "processing" ? "workFollowUp" :
      status === "failed" ? "workFollowUp" :
      "founderBuilder";

    return {
      id: `project_${doc.id}`,
      source: "workProjectContext",
      sourceRecordId: doc.id,
      title: openLoop ? "Project still in motion" : "Recent project activity",
      summary: openLoop
        ? `${title} is still ${status} and has not been closed out.`
        : `${title} was updated recently.`,
      timestamp: updatedAt,
      sensitivity: "personal",
      permissionRequired: true,
      permissionGranted: true,
      hashForDeduplication: `project:${doc.id}:${status}`,
      isUserVisible: true,
      entityType: "project",
      entityId: doc.id,
      metadata: {
        intent,
        projectId: doc.id,
        projectTitle: title,
        openLoop: openLoop ? "true" : "false",
      },
    };
  });
}

async function collectSignals(userId: string, permissions: BereanPulsePermissionDocument): Promise<BereanPulseSignal[]> {
  const granted = normalizePermissions(permissions);
  const signalSets = await Promise.all([
    collectBereanConversationSignals(userId, granted.bereanChatHistory),
    collectSavedPostSignals(userId, granted.savedPosts),
    collectChurchSignals(userId, granted.churchActivity),
    collectReflectionSignals(userId, granted.prayerJournal),
    collectNotificationSignals(userId, granted.notifications),
    collectProjectSignals(userId, granted.workProjectContext),
  ]);

  return signalSets.flat();
}

export async function generatePulseForUser(userId: string, dateKey = dateKeyFor()) {
  const [permissions, preferences, feedback] = await Promise.all([
    loadPermissions(userId),
    loadPreferences(userId),
    loadRecentFeedback(userId),
  ]);

  if (preferences.enabled === false) {
    logger.info("Berean Pulse disabled for user", { userId });
    return [];
  }

  const signals = await collectSignals(userId, permissions);
  const cards = buildBereanPulseCards({
    userId,
    dateKey,
    permissions,
    preferences,
    signals,
    feedback,
  });

  const batch = db.batch();
  const cardCollection = dayCardsCollection(userId, dateKey);
  const previousSnapshot = await cardCollection.get();
  previousSnapshot.docs.forEach((doc) => batch.delete(doc.ref));
  cards.forEach((card) => batch.set(cardCollection.doc(card.id), card, { merge: false }));
  await batch.commit();
  logger.info("Berean Pulse generated", { userId, dateKey, cards: cards.length, signals: signals.length });
  return cards;
}

export async function refreshBereanPulseForCurrentUserHandler(request: {
  data?: { dateKey?: unknown };
  app?: unknown;
  auth?: { uid?: string };
}) {
  requireAppCheck(request);
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const pulseRoot = pulseRootDoc(uid);
  const rootSnapshot = await pulseRoot.get();
  const lastManualRefreshAt = rootSnapshot.data()?.lastManualRefreshAt as FirestoreLikeTimestamp | undefined;
  const now = admin.firestore.Timestamp.now();
  const secondsSinceRefresh = lastManualRefreshAt ?
    now.seconds - lastManualRefreshAt.seconds :
    Number.POSITIVE_INFINITY;

  if (secondsSinceRefresh < 300) {
    throw new HttpsError("resource-exhausted", "Berean Pulse can be refreshed every five minutes.");
  }

  const dateKey = typeof request.data?.dateKey === "string" ? request.data.dateKey : dateKeyFor();
  const cards = await generatePulseForUser(uid, dateKey);
  await pulseRoot.set({ lastManualRefreshAt: now }, { merge: true });
  return { ok: true, dateKey, cardCount: cards.length };
}

export const refreshBereanPulseForCurrentUser = onCall(
  { region: "us-central1", enforceAppCheck: true },
  refreshBereanPulseForCurrentUserHandler
);

export const generateBereanPulseDaily = onSchedule(
  { schedule: "every day 05:15", region: "us-central1", timeZone: "America/New_York" },
  async () => {
    const users = await db.collection("users").limit(100).get();
    for (const user of users.docs) {
      try {
        await generatePulseForUser(user.id, dateKeyFor());
      } catch (error) {
        logger.error("Berean Pulse generation failed", { userId: user.id, error });
      }
    }
  }
);

export async function writePulseFeedbackEvent(
  userId: string,
  event: BereanPulseEventRecord
) {
  await eventsCollection(userId).doc(event.id).set(event, { merge: true });
}

export async function savePulseCard(userId: string, cardId: string, payload: Record<string, unknown>) {
  await savedCardsCollection(userId).doc(cardId).set(payload, { merge: true });
}

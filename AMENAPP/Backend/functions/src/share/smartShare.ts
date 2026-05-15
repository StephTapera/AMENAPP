import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

const db = admin.firestore();

type ShareEntityVisibility =
  | "public"
  | "privateOnly"
  | "closeFriends"
  | "churchOnly"
  | "groupOnly"
  | "prayerCircleOnly"
  | "unavailable";

type ShareIntent =
  | "encourage_someone"
  | "start_conversation"
  | "share_with_group"
  | "share_with_church"
  | "add_to_notes"
  | "remind_me_later"
  | "reflect_privately"
  | "save_for_later"
  | "send_in_message"
  | "create_prayer_share"
  | "story_card"
  | "copy_link"
  | "create_discussion";

type ShareTargetType = "person" | "conversation" | "prayerCircle" | "group" | "church" | "external";

interface ShareEntityPayload {
  id: string;
  entityType: string;
  authorId: string;
  authorName: string;
  authorUsername?: string | null;
  authorInitials: string;
  authorPhotoURL?: string | null;
  visibility: ShareEntityVisibility;
  title: string;
  previewText: string;
  mediaPreviewURL?: string | null;
  route: {
    path: string;
    webFallbackPath: string;
    metadata?: Record<string, string>;
  };
  externallyShareable: boolean;
  attributionPolicy: "required" | "optional" | "strippedForPrivateShare";
  sourceSurface: string;
  linkedPostId?: string | null;
  linkedChurchNoteId?: string | null;
  churchId?: string | null;
  churchName?: string | null;
  groupId?: string | null;
  prayerCircleId?: string | null;
  verseReference?: string | null;
}

interface ShareOptionsPayload {
  includeCaption: boolean;
  includeVerseCard: boolean;
  includeAttribution: boolean;
  includeLinkPreview: boolean;
  sharePrivately: boolean;
  notifyRecipient: boolean;
  addNoteBeforeSending: boolean;
}

interface SmartShareTargetResponse {
  id: string;
  targetType: ShareTargetType;
  displayName: string;
  username?: string | null;
  photoURL?: string | null;
  subtitle: string;
  badgeReason?: string | null;
  score: number;
  reasons: string[];
  isOnline: boolean;
  isVerified: boolean;
  churchAffiliation?: string | null;
}

function requireAuth(authUid?: string): string {
  if (!authUid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return authUid;
}

function asEntity(data: unknown): ShareEntityPayload {
  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Missing share entity.");
  }
  return data as ShareEntityPayload;
}

function asOptions(data: unknown): ShareOptionsPayload {
  return {
    includeCaption: Boolean((data as ShareOptionsPayload | undefined)?.includeCaption),
    includeVerseCard: Boolean((data as ShareOptionsPayload | undefined)?.includeVerseCard),
    includeAttribution: Boolean((data as ShareOptionsPayload | undefined)?.includeAttribution),
    includeLinkPreview: Boolean((data as ShareOptionsPayload | undefined)?.includeLinkPreview),
    sharePrivately: Boolean((data as ShareOptionsPayload | undefined)?.sharePrivately),
    notifyRecipient: Boolean((data as ShareOptionsPayload | undefined)?.notifyRecipient),
    addNoteBeforeSending: Boolean((data as ShareOptionsPayload | undefined)?.addNoteBeforeSending),
  };
}

function canonicalDeepLink(entity: ShareEntityPayload): string {
  return `amen://${entity.route.path}`;
}

function canonicalWebFallback(entity: ShareEntityPayload): string {
  return `https://amenapp.com/${entity.route.webFallbackPath}`;
}

function sanitizeNote(text: string): string {
  const trimmed = text.trim();
  if (!trimmed) return "";
  const banned = /\b(?:damn|hell|idiot|stupid)\b/gi;
  return trimmed.replace(banned, "•••");
}

async function fetchBlockedUserIds(uid: string): Promise<Set<string>> {
  const blocked = new Set<string>();
  const [topLevel, nested] = await Promise.all([
    db.collection("blockedUsers").where("blockerId", "==", uid).limit(200).get().catch(() => null),
    db.collection("users").doc(uid).collection("blockedUsers").limit(200).get().catch(() => null),
  ]);

  topLevel?.docs.forEach((doc) => {
    const data = doc.data();
    if (typeof data.blockedId === "string") blocked.add(data.blockedId);
  });
  nested?.docs.forEach((doc) => blocked.add(doc.id));
  return blocked;
}

async function currentUserChurchContext(uid: string): Promise<{ churchId?: string; churchName?: string }> {
  const snapshot = await db.collection("users").doc(uid).get();
  const data = snapshot.data() ?? {};
  return {
    churchId: typeof data.churchId === "string" ? data.churchId : undefined,
    churchName: typeof data.churchName === "string" ? data.churchName : undefined,
  };
}

function visibilityDeniedReason(
  entity: ShareEntityPayload,
  targetType: ShareTargetType,
  targetId?: string | null
): string | null {
  if (entity.visibility === "unavailable") return "This content is no longer available.";
  if (entity.visibility === "privateOnly" && targetType !== "person" && targetType !== "conversation") {
    return "Private content can only be shared in direct conversations.";
  }
  if (entity.visibility === "churchOnly" && targetType !== "church" && targetType !== "person" && targetType !== "conversation") {
    return "Church-only content can't be shared to that destination.";
  }
  if (entity.visibility === "groupOnly" && targetType !== "group") {
    return "Group-only content must stay inside a group.";
  }
  if (entity.visibility === "prayerCircleOnly" && targetType !== "prayerCircle" && targetType !== "person" && targetType !== "conversation") {
    return "Prayer content stays within prayer-safe destinations.";
  }
  if (targetType === "external" && !entity.externallyShareable) {
    return "This content can't be shared externally.";
  }
  if (entity.visibility === "churchOnly" && entity.churchId && targetType === "church" && targetId && entity.churchId !== targetId) {
    return "This content belongs to a different church context.";
  }
  if (entity.visibility === "groupOnly" && entity.groupId && targetId && entity.groupId !== targetId) {
    return "This content belongs to a different group.";
  }
  return null;
}

function badgeReasonForSignals(signals: string[]): string | undefined {
  if (signals.includes("sameChurch")) return "Same church";
  if (signals.includes("sameGroup")) return "Shared group";
  if (signals.includes("prayerCircle")) return "Prayer circle";
  if (signals.includes("recentShare")) return "Recent share";
  if (signals.includes("frequentConversation")) return "Frequent conversation";
  if (signals.includes("favorite")) return "Favorite";
  return undefined;
}

async function recentTargetsForUser(uid: string): Promise<Map<string, number>> {
  const snapshot = await db
    .collection("users")
    .doc(uid)
    .collection("recentShareTargets")
    .orderBy("lastSharedAt", "desc")
    .limit(50)
    .get()
    .catch(() => null);

  const map = new Map<string, number>();
  snapshot?.docs.forEach((doc, index) => {
    map.set(doc.id, Math.max(0, 40 - index));
  });
  return map;
}

async function candidateUsers(uid: string, query: string, blockedIds: Set<string>): Promise<SmartShareTargetResponse[]> {
  const users = await db.collection("users").limit(query ? 30 : 18).get().catch(() => null);
  const recentTargetScores = await recentTargetsForUser(uid);
  const currentChurch = await currentUserChurchContext(uid);

  return (users?.docs ?? [])
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((data) => data.id !== uid && !blockedIds.has(data.id))
    .filter((data) => {
      if (!query) return true;
      const haystack = `${data.displayName ?? ""} ${data.username ?? ""}`.toLowerCase();
      return haystack.includes(query.toLowerCase());
    })
    .map((data) => {
      const signals: string[] = [];
      let score = 10;

      if (recentTargetScores.has(data.id)) {
        score += recentTargetScores.get(data.id) ?? 0;
        signals.push("recentShare");
      }
      if (data.churchId && currentChurch.churchId && data.churchId === currentChurch.churchId) {
        score += 18;
        signals.push("sameChurch");
      }
      if (data.isFavorite === true) {
        score += 16;
        signals.push("favorite");
      }
      if (typeof data.conversationScore === "number" && data.conversationScore > 0) {
        score += Math.min(18, data.conversationScore);
        signals.push("frequentConversation");
      }

      return {
        id: data.id,
        targetType: "person" as const,
        displayName: String(data.displayName ?? data.name ?? "AMEN User"),
        username: typeof data.username === "string" ? data.username : null,
        photoURL: typeof data.profileImageURL === "string" ? data.profileImageURL : (typeof data.photoURL === "string" ? data.photoURL : null),
        subtitle: currentChurch.churchName && data.churchName === currentChurch.churchName ? currentChurch.churchName : "Direct share",
        badgeReason: badgeReasonForSignals(signals),
        score,
        reasons: signals,
        isOnline: Boolean(data.isOnline),
        isVerified: Boolean(data.isVerified),
        churchAffiliation: typeof data.churchName === "string" ? data.churchName : null,
      };
    });
}

async function candidateGroups(uid: string, query: string): Promise<SmartShareTargetResponse[]> {
  const groups = await db.collection("groups").limit(query ? 20 : 12).get().catch(() => null);
  const recents = await recentTargetsForUser(uid);
  return (groups?.docs ?? [])
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((data) => {
      if (!query) return true;
      return String(data.name ?? "").toLowerCase().includes(query.toLowerCase());
    })
    .map((data) => {
      const signals: string[] = [];
      let score = 12;
      if (recents.has(data.id)) {
        score += recents.get(data.id) ?? 0;
        signals.push("recentShare");
      }
      if (Array.isArray(data.memberIds) && data.memberIds.includes(uid)) {
        score += 22;
        signals.push("sameGroup");
      }
      if (data.ministry === true) {
        score += 10;
      }
      return {
        id: data.id,
        targetType: "group" as const,
        displayName: String(data.name ?? "Group"),
        username: null,
        photoURL: typeof data.photoURL === "string" ? data.photoURL : null,
        subtitle: data.ministry === true ? "Ministry group" : "Group share",
        badgeReason: badgeReasonForSignals(signals) ?? (data.ministry === true ? "Ministry group" : "Recent group"),
        score,
        reasons: signals,
        isOnline: false,
        isVerified: false,
        churchAffiliation: typeof data.churchName === "string" ? data.churchName : null,
      };
    });
}

async function candidateChurches(uid: string, query: string): Promise<SmartShareTargetResponse[]> {
  const churches = await db.collection("churchProfiles").limit(query ? 20 : 12).get().catch(() => null);
  const currentChurch = await currentUserChurchContext(uid);
  const recents = await recentTargetsForUser(uid);
  return (churches?.docs ?? [])
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((data) => {
      if (!query) return true;
      return String(data.displayName ?? data.name ?? "").toLowerCase().includes(query.toLowerCase());
    })
    .map((data) => {
      const signals: string[] = [];
      let score = 10;
      if (recents.has(data.id)) {
        score += recents.get(data.id) ?? 0;
        signals.push("recentShare");
      }
      if (currentChurch.churchId && currentChurch.churchId === data.id) {
        score += 30;
        signals.push("sameChurch");
      }
      return {
        id: data.id,
        targetType: "church" as const,
        displayName: String(data.displayName ?? data.name ?? "Church"),
        username: typeof data.username === "string" ? data.username : null,
        photoURL: typeof data.logoURL === "string" ? data.logoURL : (typeof data.photoURL === "string" ? data.photoURL : null),
        subtitle: currentChurch.churchId === data.id ? "Your church" : "Church share",
        badgeReason: badgeReasonForSignals(signals) ?? (currentChurch.churchId === data.id ? "Your church" : "Church"),
        score,
        reasons: signals,
        isOnline: false,
        isVerified: Boolean(data.isVerified),
        churchAffiliation: String(data.displayName ?? data.name ?? ""),
      };
    });
}

async function candidatePrayerCircles(uid: string, query: string): Promise<SmartShareTargetResponse[]> {
  const circles = await db.collection("prayerCircles").limit(query ? 20 : 12).get().catch(() => null);
  const recents = await recentTargetsForUser(uid);
  return (circles?.docs ?? [])
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((data) => {
      if (!query) return true;
      return String(data.name ?? "").toLowerCase().includes(query.toLowerCase());
    })
    .map((data) => {
      const signals: string[] = ["prayerCircle"];
      let score = 12;
      if (recents.has(data.id)) {
        score += recents.get(data.id) ?? 0;
        signals.push("recentShare");
      }
      return {
        id: data.id,
        targetType: "prayerCircle" as const,
        displayName: String(data.name ?? "Prayer Circle"),
        username: null,
        photoURL: typeof data.photoURL === "string" ? data.photoURL : null,
        subtitle: "Prayer circle",
        badgeReason: "Prayer circle",
        score,
        reasons: signals,
        isOnline: false,
        isVerified: false,
        churchAffiliation: typeof data.churchName === "string" ? data.churchName : null,
      };
    });
}

function payloadText(entity: ShareEntityPayload, smartContextEnabled: boolean, noteText: string, options: ShareOptionsPayload): string {
  const segments: string[] = [];
  if (smartContextEnabled && options.includeCaption) {
    segments.push(entity.title);
  }
  segments.push(entity.previewText);
  if (smartContextEnabled && options.includeAttribution && entity.attributionPolicy !== "strippedForPrivateShare") {
    segments.push(`Shared from AMEN by ${entity.authorName}`);
  }
  if (noteText.trim().length > 0) {
    segments.push(noteText.trim());
  }
  segments.push(canonicalWebFallback(entity));
  return segments.filter(Boolean).join("\n\n");
}

export const getSmartShareTargets = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const entity = asEntity(request.data?.entity);
  const query = String(request.data?.query ?? "").trim();
  const filter = String(request.data?.filter ?? "Suggested");
  const blockedIds = await fetchBlockedUserIds(uid);

  const [users, groups, churches, prayerCircles] = await Promise.all([
    candidateUsers(uid, query, blockedIds),
    candidateGroups(uid, query),
    candidateChurches(uid, query),
    candidatePrayerCircles(uid, query),
  ]);

  let combined = [...users, ...groups, ...churches, ...prayerCircles];

  if (entity.visibility === "churchOnly") {
    combined = combined.filter((target) => target.targetType === "church" || target.targetType === "person" || target.targetType === "conversation");
  } else if (entity.visibility === "groupOnly") {
    combined = combined.filter((target) => target.targetType === "group");
  } else if (entity.visibility === "prayerCircleOnly") {
    combined = combined.filter((target) => target.targetType === "prayerCircle" || target.targetType === "person");
  }

  switch (filter) {
    case "People":
      combined = combined.filter((target) => target.targetType === "person" || target.targetType === "conversation");
      break;
    case "Groups":
      combined = combined.filter((target) => target.targetType === "group");
      break;
    case "Churches":
      combined = combined.filter((target) => target.targetType === "church");
      break;
    case "Ministry":
      combined = combined.filter((target) => target.targetType === "group" || target.targetType === "prayerCircle" || target.targetType === "church");
      break;
    default:
      break;
  }

  combined.sort((lhs, rhs) => rhs.score - lhs.score);
  return { targets: combined.slice(0, 24) };
});

export const enforceSharePermissions = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const entity = asEntity(request.data?.entity);
  const targetId = typeof request.data?.targetId === "string" ? request.data.targetId : null;
  const destinationType = typeof request.data?.destinationType === "string" ? request.data.destinationType : null;
  const targetType = (destinationType === "church" || destinationType === "group" || destinationType === "prayerCircle" || destinationType === "externalApp"
    ? destinationType === "externalApp" ? "external" : destinationType
    : "person") as ShareTargetType;

  const blockedIds = await fetchBlockedUserIds(uid);
  if (targetId && blockedIds.has(targetId)) {
    return {
      canShare: false,
      resolvedVisibility: entity.visibility,
      externalShareAllowed: false,
      failureReason: "You can't share to blocked recipients.",
    };
  }

  const failureReason = visibilityDeniedReason(entity, targetType, targetId);
  return {
    canShare: !failureReason,
    resolvedVisibility: entity.visibility,
    externalShareAllowed: entity.externallyShareable && entity.visibility === "public",
    failureReason,
  };
});

export const createSharePayload = onCall(async (request) => {
  requireAuth(request.auth?.uid);
  const entity = asEntity(request.data?.entity);
  const options = asOptions(request.data?.options);
  const smartContextEnabled = Boolean(request.data?.smartContextEnabled);
  const noteText = sanitizeNote(String(request.data?.noteText ?? ""));

  return {
    text: payloadText(entity, smartContextEnabled, noteText, options),
    deepLink: canonicalDeepLink(entity),
    webFallback: canonicalWebFallback(entity),
    previewTitle: entity.title,
    previewSubtitle: smartContextEnabled ? entity.previewText : `Shared from AMEN`,
  };
});

export const generateDeepLink = onCall(async (request) => {
  requireAuth(request.auth?.uid);
  const entity = asEntity(request.data?.entity);
  return { deepLink: canonicalDeepLink(entity) };
});

export const moderateShareNote = onCall(async (request) => {
  requireAuth(request.auth?.uid);
  return { sanitizedText: sanitizeNote(String(request.data?.noteText ?? "")) };
});

export const saveToNotes = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const entity = asEntity(request.data?.entity);
  await db.collection("users").doc(uid).collection("smartShareNotes").add({
    entityId: entity.id,
    entityType: entity.entityType,
    title: entity.title,
    previewText: entity.previewText,
    deepLink: canonicalDeepLink(entity),
    sourceSurface: String(request.data?.sourceSurface ?? entity.sourceSurface),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { success: true };
});

export const createReminderPayload = onCall(async (request) => {
  requireAuth(request.auth?.uid);
  const entity = asEntity(request.data?.entity);
  const fireDate = admin.firestore.Timestamp.fromDate(new Date(Date.now() + 8 * 60 * 60 * 1000));
  return {
    title: `Revisit ${entity.title}`,
    note: entity.previewText,
    fireDate,
    deepLink: canonicalDeepLink(entity),
  };
});

export const generateStoryCard = onCall(async (request) => {
  requireAuth(request.auth?.uid);
  const entity = asEntity(request.data?.entity);
  return {
    deepLink: canonicalDeepLink(entity),
    caption: `${entity.title}\n\nOpen in AMEN`,
  };
});

export const createChurchNotePreview = onCall(async (request) => {
  requireAuth(request.auth?.uid);
  const entity = asEntity(request.data?.entity);
  return {
    previewText: entity.previewText.slice(0, 220),
  };
});

export const notifyRecipients = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const entity = asEntity(request.data?.entity);
  const targetId = String(request.data?.targetId ?? "");
  const targetType = String(request.data?.targetType ?? "person") as ShareTargetType;
  const previewText = String(request.data?.previewText ?? entity.previewText).slice(0, 180);

  await db.collection("shareNotifications").add({
    actorId: uid,
    entityId: entity.id,
    entityType: entity.entityType,
    targetId,
    targetType,
    previewText,
    deepLink: canonicalDeepLink(entity),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true };
});

export const trackShareEvent = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  await db.collection("shareEvents").add({
    actorId: uid,
    actionType: String(request.data?.actionType ?? ""),
    destinationType: request.data?.destinationType ?? null,
    entityId: String(request.data?.entityId ?? ""),
    entityType: String(request.data?.entityType ?? ""),
    sourceSurface: String(request.data?.sourceSurface ?? ""),
    targetType: request.data?.targetType ?? null,
    targetId: request.data?.targetId ?? null,
    smartContextEnabled: Boolean(request.data?.smartContextEnabled),
    sessionId: String(request.data?.sessionId ?? ""),
    latencyMs: typeof request.data?.latencyMs === "number" ? request.data.latencyMs : null,
    failureReason: request.data?.failureReason ?? null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { success: true };
});

export const deliverSmartShare = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const entity = asEntity(request.data?.entity);
  const intent = String(request.data?.intent ?? "send_in_message") as ShareIntent;
  const targetId = String(request.data?.targetId ?? "");
  const targetType = String(request.data?.targetType ?? "person") as ShareTargetType;
  const options = asOptions(request.data?.options);
  const noteText = sanitizeNote(String(request.data?.noteText ?? ""));
  const smartContextEnabled = Boolean(request.data?.smartContextEnabled);

  const failureReason = visibilityDeniedReason(entity, targetType, targetId);
  if (failureReason) {
    throw new HttpsError("permission-denied", failureReason);
  }

  const payload = payloadText(entity, smartContextEnabled, noteText, options);
  const now = admin.firestore.FieldValue.serverTimestamp();
  const baseDelivery = {
    actorId: uid,
    entityId: entity.id,
    entityType: entity.entityType,
    intent,
    payload,
    deepLink: canonicalDeepLink(entity),
    targetId,
    targetType,
    createdAt: now,
  };

  if (targetType === "group") {
    await db.collection("groups").doc(targetId).collection("shareInbox").add(baseDelivery);
  } else if (targetType === "church") {
    await db.collection("churchProfiles").doc(targetId).collection("shareInbox").add(baseDelivery);
  } else if (targetType === "prayerCircle") {
    await db.collection("prayerCircles").doc(targetId).collection("shareInbox").add(baseDelivery);
  } else {
    await db.collection("smartShareDeliveries").add(baseDelivery);
  }

  await db.collection("users").doc(uid).collection("recentShareTargets").doc(targetId).set({
    targetType,
    lastSharedAt: now,
    entityType: entity.entityType,
  }, { merge: true });

  return { success: true };
});

export const saveToCollection = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const entity = asEntity(request.data?.entity);
  await db.collection("users").doc(uid).collection("savedShareCollection").doc(entity.id).set({
    entityId: entity.id,
    entityType: entity.entityType,
    title: entity.title,
    previewText: entity.previewText,
    deepLink: canonicalDeepLink(entity),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { success: true };
});

export const reflectPrivately = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const entity = asEntity(request.data?.entity);
  const noteText = sanitizeNote(String(request.data?.noteText ?? ""));
  await db.collection("users").doc(uid).collection("privateReflections").add({
    entityId: entity.id,
    entityType: entity.entityType,
    title: entity.title,
    noteText,
    deepLink: canonicalDeepLink(entity),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { success: true };
});

export const createDiscussionThread = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const entity = asEntity(request.data?.entity);
  const doc = await db.collection("discussionThreads").add({
    entityId: entity.id,
    entityType: entity.entityType,
    title: entity.title,
    previewText: entity.previewText,
    createdBy: uid,
    sourceSurface: String(request.data?.sourceSurface ?? entity.sourceSurface),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { success: true, threadId: doc.id };
});

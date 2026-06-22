import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

const db = admin.firestore();

type ShareFilter =
  | "Suggested"
  | "Recent"
  | "People"
  | "Groups"
  | "Churches"
  | "Close Friends"
  | "Ministry"
  | "External";

type ShareDestination =
  | "directMessage"
  | "conversation"
  | "group"
  | "church"
  | "externalApp"
  | "story"
  | "copyLink"
  | "saved";

interface TargetResult {
  id: string;
  type: "person" | "conversation" | "group" | "church" | "external";
  title: string;
  subtitle: string;
  imageURL?: string | null;
  badge?: string | null;
  score: number;
  reasons: string[];
  isOnline: boolean;
}

function requireAuth(request: { auth?: { uid?: string } | null }) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  return uid;
}

function asString(value: unknown, field: string): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value.trim();
}

function normalized(input: unknown): string {
  return typeof input === "string" ? input.trim().toLowerCase() : "";
}

function buildDeepLink(contentType: string, contentId: string) {
  const routeMap: Record<string, string> = {
    regularPost: "post",
    versePost: "post",
    churchNote: "notes",
    prayerRequest: "post",
    testimony: "post",
    sermonClip: "resources",
    event: "event",
    profile: "user",
    churchProfile: "church",
    resource: "resources",
    mediaPost: "post",
  };

  const route = routeMap[contentType] ?? "post";
  return {
    deepLink: `amen://` + `${route}/${contentId}`,
    webFallback: `https://amenapp.com/${route}/${contentId}`,
    route,
    contentId,
  };
}

async function loadPost(contentId: string) {
  const snapshot = await db.collection("posts").doc(contentId).get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Shared content was not found.");
  }
  return snapshot;
}

function permissionResult(
  actorId: string,
  content: FirebaseFirestore.DocumentData,
  destinationType?: ShareDestination
) {
  const visibility = (content.visibility as string | undefined) ?? "everyone";
  const authorId = (content.authorId as string | undefined) ?? "";
  const isPrayer = content.contentType === "prayer" || content.category === "prayer";
  const churchOnly = visibility === "churchOnly";
  const closeFriends = visibility === "closeFriends";
  const privateOnly = visibility === "private" || visibility === "followers";

  if (destinationType === "externalApp" || destinationType === "story" || destinationType === "copyLink") {
    if (churchOnly || closeFriends || privateOnly) {
      return {
        allowed: false,
        visibilityMode: "externalPreviewOnly",
        reason: "This post cannot be shared publicly.",
        allowedDestinations: ["directMessage", "conversation", "group", "church"],
      };
    }
  }

  if (isPrayer) {
    return {
      allowed: true,
      visibilityMode: "privateShare",
      reason: null,
      allowedDestinations: ["directMessage", "conversation", "group", "church", "copyLink"],
      defaultPrivate: true,
    };
  }

  return {
    allowed: true,
    visibilityMode: actorId === authorId ? "defaultAudience" : "defaultAudience",
    reason: null,
    allowedDestinations: [
      "directMessage",
      "conversation",
      "group",
      "church",
      "externalApp",
      "story",
      "copyLink",
      "saved",
    ],
    defaultPrivate: false,
  };
}

function scoreReasonLabel(kind: "recent" | "church" | "prayer" | "similar" | "close") {
  switch (kind) {
    case "recent":
      return "Recent conversation";
    case "church":
      return "Same church";
    case "prayer":
      return "Prayer circle";
    case "close":
      return "Likely to engage";
    case "similar":
    default:
      return "Shared similar posts before";
  }
}

export const getSmartShareTargets = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  const actorId = requireAuth(request);
  const contentId = asString(request.data?.contentId, "contentId");
  const contentType = asString(request.data?.contentType, "contentType");
  const query = normalized(request.data?.query);
  const filter = ((request.data?.filter as ShareFilter | undefined) ?? "Suggested");

  const contentSnap = await loadPost(contentId);
  const content = contentSnap.data() ?? {};
  const viewerDoc = await db.collection("users").doc(actorId).get();
  const viewerChurchId = (viewerDoc.data()?.churchId as string | undefined) ?? "";

  const recentTargetsSnap = await db
    .collection("users")
    .doc(actorId)
    .collection("recentShareTargets")
    .orderBy("lastSharedAt", "desc")
    .limit(10)
    .get();

  const recentTargets = recentTargetsSnap.docs.map((doc, index) => ({
    id: `recent-${doc.id}`,
    type: (doc.data().targetType as TargetResult["type"]) ?? "person",
    title: (doc.data().title as string | undefined) ?? "Recent share",
    subtitle: (doc.data().subtitle as string | undefined) ?? "Recent target",
    imageURL: (doc.data().photoURL as string | undefined) ?? null,
    badge: "Recent",
    score: 100 - index * 4,
    reasons: [scoreReasonLabel("recent")],
    isOnline: false,
  })) as TargetResult[];

  const userTargets = query
    ? await db
        .collection("users")
        .where("displayNameLowercase", ">=", query)
        .where("displayNameLowercase", "<", `${query}\uf8ff`)
        .limit(10)
        .get()
    : await db
        .collection("follows")
        .where("followerId", "==", actorId)
        .limit(10)
        .get();

  const people: TargetResult[] = [];

  if (query) {
    for (const doc of userTargets.docs) {
      const data = doc.data();
      people.push({
        id: `user-${doc.id}`,
        type: "person",
        title: (data.displayName as string | undefined) ?? (data.username as string | undefined) ?? "User",
        subtitle: data.username ? `@${String(data.username)}` : "AMEN member",
        imageURL: (data.profileImageURL as string | undefined) ?? (data.photoURL as string | undefined) ?? null,
        badge: "Suggested",
        score: 76,
        reasons: [scoreReasonLabel(contentType === "prayerRequest" ? "prayer" : "close")],
        isOnline: false,
      });
    }
  } else {
    const followedIds = userTargets.docs.map((doc) => doc.data().followingId as string).filter(Boolean);
    if (followedIds.length) {
      const chunks = followedIds.slice(0, 10);
      const userDocs = await Promise.all(chunks.map((uid) => db.collection("users").doc(uid).get()));
      userDocs.forEach((doc, index) => {
        if (!doc.exists) return;
        const data = doc.data() ?? {};
        const sameChurch = viewerChurchId && data.churchId === viewerChurchId;
        people.push({
          id: `user-${doc.id}`,
          type: "person",
          title: (data.displayName as string | undefined) ?? (data.username as string | undefined) ?? "User",
          subtitle: data.username ? `@${String(data.username)}` : "AMEN member",
          imageURL: (data.profileImageURL as string | undefined) ?? (data.photoURL as string | undefined) ?? null,
          badge: sameChurch ? "Your church" : "Likely to engage",
          score: 88 - index * 3 + (sameChurch ? 6 : 0),
          reasons: [scoreReasonLabel(sameChurch ? "church" : contentType === "prayerRequest" ? "prayer" : "close")],
          isOnline: false,
        });
      });
    }
  }

  const groupsSnap = query
    ? await db
        .collection("groups")
        .where("nameLowercase", ">=", query)
        .where("nameLowercase", "<", `${query}\uf8ff`)
        .limit(6)
        .get()
    : await db.collection("groups").where("memberIds", "array-contains", actorId).limit(6).get();

  const churchesSnap = query
    ? await db
        .collection("churches")
        .where("nameLowercase", ">=", query)
        .where("nameLowercase", "<", `${query}\uf8ff`)
        .limit(6)
        .get()
    : viewerChurchId
    ? await db.collection("churches").where(admin.firestore.FieldPath.documentId(), "==", viewerChurchId).limit(1).get()
    : { docs: [] as FirebaseFirestore.QueryDocumentSnapshot[] };

  const groups: TargetResult[] = groupsSnap.docs.map((doc, index) => ({
    id: `group-${doc.id}`,
    type: "group",
    title: (doc.data().name as string | undefined) ?? "Group",
    subtitle: (doc.data().type as string | undefined) ?? "Group",
    imageURL: (doc.data().imageURL as string | undefined) ?? null,
    badge: "Small group",
    score: 70 - index * 4,
    reasons: [scoreReasonLabel(contentType === "prayerRequest" ? "prayer" : "similar")],
    isOnline: false,
  }));

  const churches: TargetResult[] = churchesSnap.docs.map((doc, index) => ({
    id: `church-${doc.id}`,
    type: "church",
    title: (doc.data().name as string | undefined) ?? "Church",
    subtitle: (doc.data().handle as string | undefined) ?? (doc.data().denomination as string | undefined) ?? "Church",
    imageURL: (doc.data().imageURL as string | undefined) ?? null,
    badge: "Your church",
    score: 74 - index * 5,
    reasons: [scoreReasonLabel("church")],
    isOnline: false,
  }));

  const merged = [...recentTargets, ...people, ...groups, ...churches];
  const deduped = Array.from(new Map(merged.map((target) => [target.id, target])).values());

  const filtered = deduped.filter((target) => {
    switch (filter) {
      case "People":
      case "Close Friends":
        return target.type === "person" || target.type === "conversation";
      case "Groups":
        return target.type === "group";
      case "Churches":
      case "Ministry":
        return target.type === "church";
      case "Recent":
        return target.badge === "Recent";
      case "External":
        return target.type === "external";
      default:
        return true;
    }
  });

  return {
    contentId,
    contentType,
    targets: filtered.sort((a, b) => b.score - a.score).slice(0, 20),
  };
});

export const enforceSharePermissions = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  const actorId = requireAuth(request);
  const contentId = asString(request.data?.contentId, "contentId");
  const destinationType = request.data?.destinationType as ShareDestination | undefined;
  const snap = await loadPost(contentId);
  return permissionResult(actorId, snap.data() ?? {}, destinationType);
});

export const generateDeepLink = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request);
  const contentId = asString(request.data?.contentId, "contentId");
  const contentType = asString(request.data?.contentType, "contentType");
  return buildDeepLink(contentType, contentId);
});

export const createSharePayload = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  const actorId = requireAuth(request);
  const contentId = asString(request.data?.contentId, "contentId");
  const contentType = asString(request.data?.contentType, "contentType");
  const destinationType = asString(request.data?.destinationType, "destinationType") as ShareDestination;
  const snap = await loadPost(contentId);
  const content = snap.data() ?? {};
  const permissions = permissionResult(actorId, content, destinationType);

  if (!permissions.allowed) {
    throw new HttpsError("permission-denied", permissions.reason ?? "Sharing is not allowed.");
  }

  const links = buildDeepLink(contentType, contentId);
  const payload = {
    contentId,
    contentType,
    destinationType,
    visibilityMode: permissions.visibilityMode,
    deepLink: links.deepLink,
    webFallback: links.webFallback,
    includeAttribution: true,
    includeLinkPreview: destinationType !== "copyLink",
    includeCaption: true,
    defaultPrivate: permissions.defaultPrivate ?? false,
    previewTitle: (content.caption as string | undefined) ?? (content.content as string | undefined) ?? "AMEN share",
  };

  await db.collection("postShares").add({
    actorId,
    postId: contentId,
    contentType,
    destinationType,
    status: "prepared",
    includedCaption: true,
    includedAttribution: true,
    includedDeepLink: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return payload;
});

export const moderateShareText = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request);
  const text = normalized(request.data?.text);
  if (!text) {
    return { allowed: true, severity: "none", flags: [] };
  }

  const blockedFragments = ["kill yourself", "i hate you", "spam link", "scam now"];
  const flags = blockedFragments.filter((fragment) => text.includes(fragment));
  return {
    allowed: flags.length === 0,
    severity: flags.length === 0 ? "none" : "high",
    flags,
  };
});

export const trackShareEvent = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  const actorId = requireAuth(request);
  const contentId = asString(request.data?.contentId, "contentId");
  const actionType = asString(request.data?.actionType, "actionType");

  const doc = await db.collection("shareEvents").add({
    actorId,
    contentId,
    contentType: request.data?.contentType ?? "regularPost",
    actionType,
    destinationType: request.data?.destinationType ?? null,
    targetId: request.data?.targetId ?? null,
    sessionId: request.data?.sessionId ?? null,
    latencyMs: request.data?.latencyMs ?? null,
    result: request.data?.result ?? "success",
    sourceSurface: request.data?.sourceSurface ?? "feed",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { id: doc.id };
});

export const notifyRecipientOnShare = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  const actorId = requireAuth(request);
  const targetId = asString(request.data?.targetId, "targetId");
  const contentId = asString(request.data?.contentId, "contentId");
  const contentType = asString(request.data?.contentType, "contentType");
  const links = buildDeepLink(contentType, contentId);

  const actorDoc = await db.collection("users").doc(actorId).get();
  const actorName = (actorDoc.data()?.displayName as string | undefined) ?? "Someone";

  const titleMap: Record<string, string> = {
    versePost: `${actorName} shared a verse with you`,
    churchNote: `${actorName} sent a church note`,
    prayerRequest: `${actorName} shared a prayer request`,
  };

  const notification = {
    actorId,
    recipientId: targetId,
    type: "share",
    title: titleMap[contentType] ?? `${actorName} shared a post with you`,
    body: "Tap to open in AMEN",
    deepLink: links.deepLink,
    webFallback: links.webFallback,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    status: "queued",
  };

  const doc = await db.collection("notificationQueue").add(notification);
  return { queued: true, id: doc.id };
});

export const createVerseCardAsset = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  const actorId = requireAuth(request);
  const contentId = asString(request.data?.contentId, "contentId");
  const doc = await db.collection("shareRenderJobs").add({
    actorId,
    contentId,
    renderType: "verseCard",
    status: "queued",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return {
    jobId: doc.id,
    status: "queued",
    storagePath: `share-renders/${contentId}/verse-card.png`,
  };
});

export const createChurchNotePreview = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  const actorId = requireAuth(request);
  const contentId = asString(request.data?.contentId, "contentId");
  const doc = await db.collection("shareRenderJobs").add({
    actorId,
    contentId,
    renderType: "churchNotePreview",
    status: "queued",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return {
    jobId: doc.id,
    status: "queued",
    storagePath: `share-renders/${contentId}/church-note-preview.png`,
  };
});

import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {
  ContentBlock,
  ContentNode,
  ContentType,
  ContentVisibility,
  MediaRef,
  validContentTypes,
  validContentVisibilities,
} from "./contentTypes";

const db = admin.firestore();
function requireUser(request: { auth?: { uid: string }; app?: unknown }): string {
  if (!request.auth) throw new HttpsError("unauthenticated", "Authentication required.");
  if (!request.app) throw new HttpsError("unauthenticated", "App Check required.");
  return request.auth.uid;
}

function asString(value: unknown, maxLength: number, field: string, required = false): string | undefined {
  if (value === undefined || value === null) {
    if (required) throw new HttpsError("invalid-argument", `${field} is required.`);
    return undefined;
  }
  if (typeof value !== "string") throw new HttpsError("invalid-argument", `${field} must be a string.`);
  const trimmed = value.trim();
  if (required && !trimmed) throw new HttpsError("invalid-argument", `${field} is required.`);
  if (trimmed.length > maxLength) throw new HttpsError("invalid-argument", `${field} is too long.`);
  return trimmed;
}

function requiredString(value: unknown, maxLength: number, field: string): string {
  const result = asString(value, maxLength, field, true);
  if (!result) throw new HttpsError("invalid-argument", `${field} is required.`);
  return result;
}

function parseType(value: unknown): ContentType {
  const type = requiredString(value, 40, "contentType") as ContentType;
  if (!validContentTypes.includes(type)) throw new HttpsError("invalid-argument", "Invalid content type.");
  return type;
}

function parseVisibility(value: unknown): ContentVisibility {
  const visibility = (asString(value, 40, "visibility") ?? "private") as ContentVisibility;
  if (!validContentVisibilities.includes(visibility)) throw new HttpsError("invalid-argument", "Invalid visibility.");
  return visibility;
}

function parseBlocks(value: unknown): ContentBlock[] {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 100).map((block, index) => {
    const item = block as Record<string, unknown>;
    return {
      id: asString(item.id, 120, "block.id") ?? db.collection("_").doc().id,
      type: (asString(item.type, 40, "block.type") ?? "text") as ContentBlock["type"],
      text: asString(item.text, 8000, "block.text"),
      mediaRefId: asString(item.mediaRefId, 120, "block.mediaRefId"),
      order: typeof item.order === "number" ? item.order : index,
      metadata: typeof item.metadata === "object" && item.metadata !== null ? item.metadata as Record<string, string> : undefined,
    };
  });
}

function parseMediaRefs(value: unknown): MediaRef[] {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 24).map((media) => {
    const item = media as Record<string, unknown>;
    return {
      id: asString(item.id, 120, "media.id") ?? db.collection("_").doc().id,
      mediaId: asString(item.mediaId, 120, "media.mediaId"),
      type: (asString(item.type, 40, "media.type") ?? "unknown") as MediaRef["type"],
      url: asString(item.url, 2048, "media.url"),
      thumbnailURL: asString(item.thumbnailURL, 2048, "media.thumbnailURL"),
      storagePath: asString(item.storagePath, 1024, "media.storagePath"),
      width: typeof item.width === "number" ? item.width : undefined,
      height: typeof item.height === "number" ? item.height : undefined,
      duration: typeof item.duration === "number" ? item.duration : undefined,
      caption: asString(item.caption, 2200, "media.caption"),
      altText: asString(item.altText, 2200, "media.altText"),
      processingState: asString(item.processingState, 40, "media.processingState") as MediaRef["processingState"],
    };
  });
}

function userDraftRef(uid: string, draftId: string) {
  return db.collection("users").doc(uid).collection("drafts").doc(draftId);
}

function contentRef(contentId: string) {
  return db.collection("content").doc(contentId);
}

function requireModerator(request: { auth?: { uid: string; token?: Record<string, unknown> }; app?: unknown }): string {
  const uid = requireUser(request);
  const token = request.auth?.token ?? {};
  if (token.admin === true || token.moderator === true) return uid;
  throw new HttpsError("permission-denied", "Moderator access required.");
}

function publicApprovedQuery() {
  return db.collection("content")
    .where("publishState", "==", "published")
    .where("visibility", "==", "public")
    .where("moderationState.status", "==", "approved");
}

function serializeContentNode(doc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot): Record<string, unknown> {
  const data = doc.data() ?? {};
  return {
    ...data,
    id: data.id ?? doc.id,
    createdAt: timestampToISO(data.createdAt),
    updatedAt: timestampToISO(data.updatedAt),
    deletedAt: data.deletedAt ? timestampToISO(data.deletedAt) : null,
  };
}

function timestampToISO(value: unknown): string {
  if (value && typeof (value as { toDate?: unknown }).toDate === "function") {
    return ((value as FirebaseFirestore.Timestamp).toDate()).toISOString();
  }
  if (value instanceof Date) return value.toISOString();
  return new Date().toISOString();
}

function serializeDraft(data: FirebaseFirestore.DocumentData): Record<string, unknown> {
  return {
    id: data.id,
    ownerId: data.ownerId,
    intent: data.intent ?? data.draftType ?? "textPost",
    title: data.title ?? null,
    text: data.text ?? "",
    blocks: Array.isArray(data.blocks) ? data.blocks : [],
    mediaRefs: Array.isArray(data.mediaRefs) ? data.mediaRefs : [],
    intendedVisibility: data.intendedVisibility ?? "private",
    publishTarget: data.publishTarget ?? null,
    syncState: data.syncState ?? "synced",
    createdAt: timestampToISO(data.createdAt),
    updatedAt: timestampToISO(data.updatedAt),
  };
}

async function buildNode(uid: string, data: Record<string, unknown>): Promise<ContentNode> {
  const now = admin.firestore.Timestamp.now();
  const authorSnapshot = await db.collection("users").doc(uid).get();
  const author = authorSnapshot.data() ?? {};
  const id = db.collection("content").doc().id;

  return {
    id,
    ownerId: uid,
    author: {
      displayName: typeof author.displayName === "string" ? author.displayName : "Amen user",
      username: typeof author.username === "string" ? author.username : undefined,
      avatarURL: typeof author.profileImageURL === "string" ? author.profileImageURL : undefined,
    },
    type: parseType(data.contentType ?? data.type),
    visibility: parseVisibility(data.visibility ?? data.intendedVisibility),
    title: asString(data.title, 180, "title"),
    text: asString(data.text, 30000, "text"),
    blocks: parseBlocks(data.blocks),
    mediaRefs: parseMediaRefs(data.mediaRefs),
    collaborators: Array.isArray(data.collaborators) ? data.collaborators.filter((id) => typeof id === "string").slice(0, 50) as string[] : [],
    moderationState: { status: "pending" },
    aiMetadata: { usedAI: false },
    createdAt: now,
    updatedAt: now,
    sourceReferences: [],
    parentContentId: asString(data.parentContentId, 120, "parentContentId"),
    remixSourceId: asString(data.remixSourceId, 120, "remixSourceId"),
    saveEligible: data.saveEligible !== false,
    shareEligible: data.shareEligible !== false,
    publishState: "draft",
  };
}

export const saveContentDraft = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const draftId = asString(data.draftId, 120, "draftId") ?? db.collection("_").doc().id;
  const now = admin.firestore.Timestamp.now();

  parseType(data.contentType ?? data.draftType);
  parseVisibility(data.intendedVisibility ?? "private");

  await userDraftRef(uid, draftId).set({
    id: draftId,
    ownerId: uid,
    draftType: asString(data.draftType, 80, "draftType") ?? "textPost",
    intent: asString(data.draftType, 80, "draftType") ?? "textPost",
    contentType: data.contentType,
    title: asString(data.title, 180, "title"),
    text: asString(data.text, 30000, "text") ?? "",
    blocks: parseBlocks(data.blocks),
    mediaRefs: parseMediaRefs(data.mediaRefs),
    intendedVisibility: data.intendedVisibility ?? "private",
    publishTarget: typeof data.publishTarget === "string" ? data.publishTarget : null,
    syncState: "synced",
    updatedAt: now,
    createdAt: now,
  }, { merge: true });

  return { success: true, draftId };
});

export const getContentDraft = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const draftId = asString(data.draftId, 120, "draftId");
  const draftType = asString(data.draftType, 80, "draftType");

  let snapshot: FirebaseFirestore.DocumentSnapshot | undefined;
  if (draftId) {
    snapshot = await userDraftRef(uid, draftId).get();
  } else if (draftType) {
    const query = await db.collection("users").doc(uid).collection("drafts")
      .where("draftType", "==", draftType)
      .orderBy("updatedAt", "desc")
      .limit(1)
      .get();
    snapshot = query.docs[0];
  }

  if (!snapshot?.exists) return { success: true, draft: null };
  return { success: true, draft: serializeDraft(snapshot.data() ?? {}) };
});

export const deleteContentDraft = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const draftId = requiredString((request.data as Record<string, unknown>).draftId, 120, "draftId");
  await userDraftRef(uid, draftId).delete();
  return { success: true, draftId };
});

export const createContentNode = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const node = await buildNode(uid, request.data as Record<string, unknown>);
  await contentRef(node.id).set(node);
  return { success: true, contentId: node.id, moderationStatus: node.moderationState.status };
});

export const updateContentNode = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const contentId = requiredString(data.contentId, 120, "contentId");
  const ref = contentRef(contentId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Content not found.");
  if (snapshot.get("ownerId") !== uid) throw new HttpsError("permission-denied", "Only the owner can update content.");

  const update: Record<string, unknown> = {
    updatedAt: admin.firestore.Timestamp.now(),
    moderationState: { status: "pending" },
  };
  if ("title" in data) update.title = asString(data.title, 180, "title");
  if ("text" in data) update.text = asString(data.text, 30000, "text") ?? "";
  if ("blocks" in data) update.blocks = parseBlocks(data.blocks);
  if ("mediaRefs" in data) update.mediaRefs = parseMediaRefs(data.mediaRefs);
  if ("visibility" in data) update.visibility = parseVisibility(data.visibility);

  await ref.update(update);
  return { success: true, contentId, moderationStatus: "pending" };
});

export const publishContentNode = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const contentId = requiredString((request.data as Record<string, unknown>).contentId, 120, "contentId");
  const ref = contentRef(contentId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Content not found.");
  if (snapshot.get("ownerId") !== uid) throw new HttpsError("permission-denied", "Only the owner can publish content.");

  await ref.update({
    publishState: "published",
    updatedAt: admin.firestore.Timestamp.now(),
    "moderationState.status": "pending",
  });
  return { success: true, contentId, moderationStatus: "pending" };
});

export const deleteContentNode = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const contentId = requiredString((request.data as Record<string, unknown>).contentId, 120, "contentId");
  const ref = contentRef(contentId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Content not found.");
  if (snapshot.get("ownerId") !== uid) throw new HttpsError("permission-denied", "Only the owner can delete content.");

  await ref.update({
    deletedAt: admin.firestore.Timestamp.now(),
    publishState: "archived",
    updatedAt: admin.firestore.Timestamp.now(),
  });
  return { success: true, contentId };
});

export const getContentNode = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const contentId = requiredString((request.data as Record<string, unknown>).contentId, 120, "contentId");
  const snapshot = await contentRef(contentId).get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Content not found.");
  const node = snapshot.data() as ContentNode;
  const canRead =
    node.ownerId === uid ||
    node.collaborators.includes(uid) ||
    (node.visibility === "public" && node.publishState === "published" && node.moderationState.status === "approved");
  if (!canRead) throw new HttpsError("permission-denied", "You do not have access to this content.");
  return { success: true, content: serializeContentNode(snapshot) };
});

export const publishDraftToContentNode = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const draftId = requiredString(data.draftId, 120, "draftId");
  const draftSnapshot = await userDraftRef(uid, draftId).get();
  if (!draftSnapshot.exists) throw new HttpsError("not-found", "Draft not found.");

  const draft = draftSnapshot.data() ?? {};
  const node = await buildNode(uid, {
    ...draft,
    contentType: draft.contentType ?? data.contentType,
    visibility: draft.intendedVisibility ?? data.intendedVisibility ?? "private",
  });
  node.publishState = "published";
  node.moderationState = { status: "pending" };

  const batch = db.batch();
  batch.set(contentRef(node.id), node);
  batch.delete(userDraftRef(uid, draftId));
  await batch.commit();

  return { success: true, contentId: node.id, moderationStatus: "pending" };
});

export const reviewContentNodeModeration = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const reviewerId = requireModerator(request);
  const data = request.data as Record<string, unknown>;
  const contentId = requiredString(data.contentId, 120, "contentId");
  const decision = requiredString(data.decision, 40, "decision");
  const allowed = ["approved", "limited", "rejected", "removed", "escalated"];
  if (!allowed.includes(decision)) throw new HttpsError("invalid-argument", "Invalid moderation decision.");

  await contentRef(contentId).update({
    moderationState: {
      status: decision,
      reason: asString(data.reason, 500, "reason"),
      reviewedAt: admin.firestore.Timestamp.now(),
      reviewedBy: reviewerId,
    },
    updatedAt: admin.firestore.Timestamp.now(),
  });

  return { success: true, contentId, moderationStatus: decision };
});

export const getUniversalContentFeed = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  requireUser(request);
  const limit = Math.min(Math.max(Number((request.data as Record<string, unknown>)?.limit ?? 20), 1), 50);
  const snapshot = await publicApprovedQuery()
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get();

  return {
    success: true,
    items: snapshot.docs
      .filter((doc) => !doc.get("deletedAt"))
      .map(serializeContentNode),
  };
});

export const getProfileContent = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  const uid = requireUser(request);
  const data = request.data as Record<string, unknown>;
  const ownerId = requiredString(data.ownerId, 120, "ownerId");
  const limit = Math.min(Math.max(Number(data.limit ?? 20), 1), 50);
  let query: FirebaseFirestore.Query = db.collection("content")
    .where("ownerId", "==", ownerId)
    .where("publishState", "==", "published");

  if (ownerId !== uid) {
    query = query
      .where("visibility", "==", "public")
      .where("moderationState.status", "==", "approved");
  }

  const snapshot = await query.orderBy("createdAt", "desc").limit(limit).get();
  return {
    success: true,
    items: snapshot.docs
      .filter((doc) => !doc.get("deletedAt"))
      .map(serializeContentNode),
  };
});

export const keywordSearchContent = onCall({ region: "us-central1", timeoutSeconds: 20, enforceAppCheck: true }, async (request) => {
  requireUser(request);
  const data = request.data as Record<string, unknown>;
  const queryText = requiredString(data.query, 120, "query").toLowerCase();
  const limit = Math.min(Math.max(Number(data.limit ?? 20), 1), 50);
  const snapshot = await publicApprovedQuery()
    .orderBy("createdAt", "desc")
    .limit(100)
    .get();

  const items = snapshot.docs
    .filter((doc) => !doc.get("deletedAt"))
    .map(serializeContentNode)
    .filter((item) => {
      const haystack = `${item.title ?? ""} ${item.text ?? ""}`.toLowerCase();
      return haystack.includes(queryText);
    })
    .slice(0, limit);

  return { success: true, items };
});

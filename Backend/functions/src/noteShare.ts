import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { randomBytes } from "crypto";

const REGION = "us-central1";
const db = admin.firestore();
const now = () => admin.firestore.FieldValue.serverTimestamp();

type NoteShareVisibility = "public" | "church" | "followers" | "link" | "space";
type NoteShareCommentScope = "everyone" | "church" | "off";
type NoteShareAttribution = "full" | "firstName" | "anonymous";
type NoteShareRenderMode = "selah" | "postcard";
type NoteShareStatus = "active" | "revoked";
type ReflectionStatus = "published" | "pending" | "removed";

interface NoteShareConfig {
  visibility: NoteShareVisibility;
  spaceId?: string | null;
  churchId?: string | null;
  allowAmens: boolean;
  allowComments: NoteShareCommentScope;
  allowReshare: boolean;
  showCounts: boolean;
  authorPrivateAmenList: boolean;
  attribution: NoteShareAttribution;
  watermarkOnExport: boolean;
}

interface NoteShareDocument {
  noteId: string;
  authorUid: string;
  createdAt?: admin.firestore.Timestamp;
  updatedAt?: admin.firestore.Timestamp;
  status: NoteShareStatus;
  shareConfig: NoteShareConfig;
  renderMode: NoteShareRenderMode;
  linkToken?: string | null;
  title?: string | null;
  subtitle?: string | null;
  scriptureRefs?: string[];
  churchName?: string | null;
  renderBlocks?: Array<Record<string, unknown>>;
}

const DEFAULT_CONFIG: NoteShareConfig = {
  visibility: "public",
  spaceId: null,
  churchId: null,
  allowAmens: true,
  allowComments: "everyone",
  allowReshare: true,
  showCounts: false,
  authorPrivateAmenList: false,
  attribution: "full",
  watermarkOnExport: false,
};

function requireAuth(request: { auth?: { uid?: string } }): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  return uid;
}

function requireApp(request: { app?: unknown }): void {
  if (!request.app) throw new HttpsError("unauthenticated", "App Check required.");
}

function cleanString(value: unknown, field: string, max = 4000, required = true): string {
  if (typeof value !== "string") {
    if (!required) return "";
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  const trimmed = value.trim();
  if (required && !trimmed) throw new HttpsError("invalid-argument", `${field} is required.`);
  if (trimmed.length > max) throw new HttpsError("invalid-argument", `${field} is too long.`);
  return trimmed;
}

function cleanConfig(raw: unknown): NoteShareConfig {
  const data = (raw ?? {}) as Partial<NoteShareConfig>;
  const visibility = ["public", "church", "followers", "link", "space"].includes(String(data.visibility))
    ? data.visibility as NoteShareVisibility
    : DEFAULT_CONFIG.visibility;
  const allowComments = ["everyone", "church", "off"].includes(String(data.allowComments))
    ? data.allowComments as NoteShareCommentScope
    : DEFAULT_CONFIG.allowComments;
  const attribution = ["full", "firstName", "anonymous"].includes(String(data.attribution))
    ? data.attribution as NoteShareAttribution
    : DEFAULT_CONFIG.attribution;

  return {
    visibility,
    spaceId: typeof data.spaceId === "string" ? data.spaceId : null,
    churchId: typeof data.churchId === "string" ? data.churchId : null,
    allowAmens: data.allowAmens !== false,
    allowComments,
    allowReshare: data.allowReshare !== false,
    showCounts: data.showCounts === true,
    authorPrivateAmenList: data.authorPrivateAmenList === true,
    attribution,
    watermarkOnExport: data.watermarkOnExport === true,
  };
}

function cleanRenderMode(value: unknown): NoteShareRenderMode {
  return value === "postcard" ? "postcard" : "selah";
}

function linkToken(): string {
  return randomBytes(18).toString("base64url");
}

async function enforceRateLimit(uid: string, key: string, maxRequests: number): Promise<void> {
  const windowMs = 60_000;
  const bucket = Math.floor(Date.now() / windowMs);
  const ref = db.collection("rateLimits").doc(`${key}:${uid}:${bucket}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = Number(snap.data()?.count ?? 0);
    if (count >= maxRequests) throw new HttpsError("resource-exhausted", "Please slow down and try again.");
    tx.set(ref, {
      uid,
      key,
      bucket,
      count: count + 1,
      updatedAt: now(),
      expiresAt: admin.firestore.Timestamp.fromMillis((bucket + 2) * windowMs),
    }, { merge: true });
  });
}

async function noteAuthor(noteId: string): Promise<{ uid: string; data: admin.firestore.DocumentData }> {
  const snap = await db.collection("churchNotes").doc(noteId).get();
  if (!snap.exists) throw new HttpsError("not-found", "Church Note not found.");
  const data = snap.data() ?? {};
  const uid = String(data.userId ?? data.authorUid ?? data.ownerUid ?? "");
  if (!uid) throw new HttpsError("failed-precondition", "Church Note is missing an owner.");
  return { uid, data };
}

async function canManageNote(noteId: string, uid: string): Promise<boolean> {
  const owner = await noteAuthor(noteId);
  if (owner.uid === uid) return true;
  const collaborator = await db.collection("churchNotes").doc(noteId).collection("collaborators").doc(uid).get();
  const role = collaborator.data()?.role;
  return collaborator.exists && ["owner", "editor"].includes(String(role));
}

async function userChurchId(uid: string): Promise<string | null> {
  const snap = await db.collection("users").doc(uid).get();
  const data = snap.data() ?? {};
  return typeof data.churchId === "string" ? data.churchId : null;
}

async function isFollower(viewerUid: string, authorUid: string): Promise<boolean> {
  const candidates = [
    db.collection("follows_index").doc(`${viewerUid}_${authorUid}`),
    db.collection("users").doc(authorUid).collection("followers").doc(viewerUid),
    db.collection("users").doc(viewerUid).collection("following").doc(authorUid),
  ];
  const snaps = await Promise.all(candidates.map((ref) => ref.get().catch(() => null)));
  return snaps.some((snap) => snap?.exists === true);
}

async function canReadShare(share: NoteShareDocument, viewerUid: string): Promise<boolean> {
  if (share.status !== "active") return false;
  if (viewerUid === share.authorUid) return true;
  switch (share.shareConfig.visibility) {
    case "public":
    case "link":
      return true;
    case "followers":
      return isFollower(viewerUid, share.authorUid);
    case "church": {
      const viewerChurchId = await userChurchId(viewerUid);
      return Boolean(viewerChurchId && share.shareConfig.churchId && viewerChurchId === share.shareConfig.churchId);
    }
    case "space":
      if (!share.shareConfig.spaceId) return false;
      return (await db.collection("spaces").doc(share.shareConfig.spaceId).collection("members").doc(viewerUid).get()).exists;
    default:
      return false;
  }
}

async function loadShare(shareId: string, uid: string): Promise<{ ref: admin.firestore.DocumentReference; share: NoteShareDocument }> {
  const ref = db.collection("noteShares").doc(shareId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Shared note not found.");
  const share = snap.data() as NoteShareDocument;
  if (!(await canReadShare(share, uid))) throw new HttpsError("permission-denied", "You do not have access to this shared note.");
  return { ref, share };
}

function notePreview(data: admin.firestore.DocumentData): { title: string; subtitle: string | null; scriptureRefs: string[]; churchName: string | null; renderBlocks: Array<Record<string, unknown>> } {
  const title = String(data.title ?? data.sermonTitle ?? "Church Note").slice(0, 160);
  const subtitle = typeof data.summaryDraft === "string" ? data.summaryDraft.slice(0, 240) : (typeof data.subtitle === "string" ? data.subtitle.slice(0, 240) : null);
  const rawRefs = Array.isArray(data.scriptureRefs) ? data.scriptureRefs : (Array.isArray(data.scriptureReferences) ? data.scriptureReferences : []);
  const scriptureRefs = rawRefs.map((ref) => String(ref)).filter(Boolean).slice(0, 24);
  const churchName = typeof data.churchName === "string" ? data.churchName : null;
  const body = String(data.approvedBody ?? data.body ?? data.content ?? data.summaryDraft ?? "").slice(0, 6000);
  const renderBlocks = body
    ? [{ id: "body", kind: "paragraph", text: body, payload: null }]
    : [];
  return { title, subtitle, scriptureRefs, churchName, renderBlocks };
}

function publicConfig(config: NoteShareConfig): Record<string, unknown> {
  return {
    visibility: config.visibility,
    allowAmens: config.allowAmens,
    allowComments: config.allowComments,
    allowReshare: config.allowReshare,
    attribution: config.attribution,
    watermarkOnExport: config.watermarkOnExport,
  };
}

function moderationVerdict(body: string): { status: ReflectionStatus; guardianVerdict: Record<string, unknown> } {
  const sensitivePattern = /\b(?:\d{3}[-.\s]?\d{3}[-.\s]?\d{4}|[\w.+-]+@[\w-]+\.[\w.-]+|address|school|medical|diagnosis|bank|ssn)\b/i;
  const needsReview = sensitivePattern.test(body);
  return {
    status: needsReview ? "pending" : "published",
    guardianVerdict: {
      provider: "noteSharePrePublish",
      status: needsReview ? "review" : "safe",
    },
  };
}

export const noteShareCreate = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
  requireApp(request);
  const uid = requireAuth(request);
  const noteId = cleanString(request.data?.noteId, "noteId", 160);
  if (!(await canManageNote(noteId, uid))) throw new HttpsError("permission-denied", "You cannot share this note.");
  const source = await noteAuthor(noteId);
  const config = cleanConfig(request.data?.shareConfig);
  if (config.visibility === "church" && !config.churchId) config.churchId = source.data.churchId ?? await userChurchId(uid);
  const preview = notePreview(source.data);
  if (!preview.title && preview.renderBlocks.length === 0) throw new HttpsError("failed-precondition", "This note has no shareable content.");
  const ref = db.collection("noteShares").doc();
  const token = config.visibility === "link" ? linkToken() : null;
  await ref.set({
    noteId,
    authorUid: source.uid,
    createdAt: now(),
    updatedAt: now(),
    status: "active",
    shareConfig: config,
    renderMode: cleanRenderMode(request.data?.renderMode),
    linkToken: token,
    ...preview,
  });
  await db.collection("noteShareAudit").add({ shareId: ref.id, actorUid: uid, action: "create", createdAt: now() });
  return { shareId: ref.id, linkToken: token };
});

export const noteShareUpdateConfig = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
  requireApp(request);
  const uid = requireAuth(request);
  const shareId = cleanString(request.data?.shareId, "shareId", 160);
  const ref = db.collection("noteShares").doc(shareId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Shared note not found.");
  const share = snap.data() as NoteShareDocument;
  if (share.authorUid !== uid) throw new HttpsError("permission-denied", "Only the author can update sharing.");
  const shareConfig = { ...share.shareConfig, ...cleanConfig(request.data?.partialConfig) };
  if (shareConfig.visibility === "church" && !shareConfig.churchId) shareConfig.churchId = await userChurchId(uid);
  const patch: Record<string, unknown> = { shareConfig, updatedAt: now() };
  if (shareConfig.visibility !== "link") patch.linkToken = null;
  if (shareConfig.visibility === "link" && !share.linkToken) patch.linkToken = linkToken();
  await ref.update(patch);
  await db.collection("noteShareAudit").add({ shareId, actorUid: uid, action: "updateConfig", createdAt: now() });
  return { shareId, shareConfig };
});

export const noteShareRevoke = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
  requireApp(request);
  const uid = requireAuth(request);
  const shareId = cleanString(request.data?.shareId, "shareId", 160);
  const ref = db.collection("noteShares").doc(shareId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Shared note not found.");
  const share = snap.data() as NoteShareDocument;
  if (share.authorUid !== uid) throw new HttpsError("permission-denied", "Only the author can revoke sharing.");
  await ref.update({ status: "revoked", linkToken: null, updatedAt: now(), revokedAt: now() });
  await db.collection("noteShareAudit").add({ shareId, actorUid: uid, action: "revoke", createdAt: now() });
  return { shareId, status: "revoked" };
});

export const noteShareToggleAmen = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
  requireApp(request);
  const uid = requireAuth(request);
  await enforceRateLimit(uid, "noteShareToggleAmen", 30);
  const shareId = cleanString(request.data?.shareId, "shareId", 160);
  const { ref, share } = await loadShare(shareId, uid);
  if (!share.shareConfig.allowAmens) throw new HttpsError("failed-precondition", "Amens are off for this note.");
  const amenRef = ref.collection("amens").doc(uid);
  const amened = await db.runTransaction(async (tx) => {
    const snap = await tx.get(amenRef);
    if (snap.exists) {
      tx.delete(amenRef);
      return false;
    }
    tx.set(amenRef, { createdAt: now() });
    return true;
  });
  return { amened };
});

export const noteShareGetViewerPayload = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
  requireApp(request);
  const uid = requireAuth(request);
  const link = typeof request.data?.linkToken === "string" ? request.data.linkToken : "";
  let shareId = typeof request.data?.shareId === "string" ? request.data.shareId : "";
  if (!shareId && link) {
    const tokenSnap = await db.collection("noteShares").where("linkToken", "==", link).limit(1).get();
    shareId = tokenSnap.docs[0]?.id ?? "";
  }
  if (!shareId) throw new HttpsError("invalid-argument", "shareId or linkToken is required.");
  const { ref, share } = await loadShare(shareId, uid);
  const amen = await ref.collection("amens").doc(uid).get();
  const reflections = await ref.collection("reflections").where("status", "==", "published").orderBy("createdAt", "asc").limit(25).get();
  return {
    shareId,
    noteId: share.noteId,
    title: share.title ?? "Church Note",
    subtitle: share.subtitle ?? null,
    eyebrow: share.churchName ? `FROM SUNDAY · ${share.churchName}` : "CHURCH NOTE",
    scriptureRefs: share.scriptureRefs ?? [],
    renderMode: share.renderMode,
    renderBlocks: share.renderBlocks ?? [],
    shareConfig: publicConfig(share.shareConfig),
    myAmenState: amen.exists,
    reflectionsPage: {
      reflections: reflections.docs.map((doc) => ({ id: doc.id, ...doc.data(), body: doc.data().body ?? "" })),
      nextCursor: reflections.docs.length === 25 ? reflections.docs[24].id : null,
    },
    authorPanel: share.authorUid === uid ? {
      shareConfig: share.shareConfig,
      mayViewPrivateAmenList: share.shareConfig.authorPrivateAmenList === true,
      privateAmenUserIds: [],
    } : null,
  };
});

export const noteShareListReflections = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
  requireApp(request);
  const uid = requireAuth(request);
  const shareId = cleanString(request.data?.shareId, "shareId", 160);
  const { ref } = await loadShare(shareId, uid);
  const snap = await ref.collection("reflections").where("status", "==", "published").orderBy("createdAt", "asc").limit(25).get();
  return {
    reflections: snap.docs.map((doc) => ({ id: doc.id, ...doc.data(), body: doc.data().body ?? "" })),
    nextCursor: snap.docs.length === 25 ? snap.docs[24].id : null,
  };
});

export const noteShareAddReflection = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
  requireApp(request);
  const uid = requireAuth(request);
  await enforceRateLimit(uid, "noteShareAddReflection", 10);
  const shareId = cleanString(request.data?.shareId, "shareId", 160);
  const body = cleanString(request.data?.body, "body", 2000);
  const parentId = typeof request.data?.parentId === "string" ? request.data.parentId : null;
  const { ref, share } = await loadShare(shareId, uid);
  if (share.shareConfig.allowComments === "off") throw new HttpsError("failed-precondition", "Reflections are off for this note.");
  if (share.shareConfig.allowComments === "church") {
    const viewerChurchId = await userChurchId(uid);
    if (!viewerChurchId || viewerChurchId !== share.shareConfig.churchId) {
      throw new HttpsError("permission-denied", "Reflections are limited to this church.");
    }
  }
  if (parentId) {
    const parent = await ref.collection("reflections").doc(parentId).get();
    if (!parent.exists || parent.data()?.parentId) throw new HttpsError("failed-precondition", "Reflections support one reply level.");
  }
  const verdict = moderationVerdict(body);
  const commentRef = ref.collection("reflections").doc();
  await commentRef.set({
    authorUid: uid,
    body,
    parentId,
    status: verdict.status,
    guardianVerdict: verdict.guardianVerdict,
    createdAt: now(),
    updatedAt: now(),
  });
  return { reflection: { id: commentRef.id, authorUid: uid, body, parentId, status: verdict.status, guardianVerdict: verdict.guardianVerdict } };
});

import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { randomBytes } from "crypto";
import { validateThinkFirst } from "./thinkFirst/validator";

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
  smartActions?: Array<Record<string, string>>;
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
    churchId: null,
    allowAmens: data.allowAmens !== false,
    allowComments,
    allowReshare: data.allowReshare !== false,
    showCounts: data.showCounts === true,
    authorPrivateAmenList: data.authorPrivateAmenList === true,
    attribution,
    watermarkOnExport: data.watermarkOnExport === true,
  };
}

function cleanPartialConfig(raw: unknown, current: NoteShareConfig): NoteShareConfig {
  const data = (raw ?? {}) as Partial<NoteShareConfig>;
  const next = { ...current };
  if (data.visibility !== undefined) {
    if (!["public", "church", "followers", "link", "space"].includes(String(data.visibility))) {
      throw new HttpsError("invalid-argument", "visibility is invalid.");
    }
    next.visibility = data.visibility as NoteShareVisibility;
  }
  if (data.allowComments !== undefined) {
    if (!["everyone", "church", "off"].includes(String(data.allowComments))) {
      throw new HttpsError("invalid-argument", "allowComments is invalid.");
    }
    next.allowComments = data.allowComments as NoteShareCommentScope;
  }
  if (data.attribution !== undefined) {
    if (!["full", "firstName", "anonymous"].includes(String(data.attribution))) {
      throw new HttpsError("invalid-argument", "attribution is invalid.");
    }
    next.attribution = data.attribution as NoteShareAttribution;
  }
  if (data.spaceId !== undefined) next.spaceId = typeof data.spaceId === "string" ? data.spaceId : null;
  if (data.churchId !== undefined) next.churchId = null;
  if (data.allowAmens !== undefined) next.allowAmens = data.allowAmens !== false;
  if (data.allowReshare !== undefined) next.allowReshare = data.allowReshare === true;
  if (data.showCounts !== undefined) next.showCounts = data.showCounts === true;
  if (data.authorPrivateAmenList !== undefined) next.authorPrivateAmenList = data.authorPrivateAmenList === true;
  if (data.watermarkOnExport !== undefined) next.watermarkOnExport = data.watermarkOnExport === true;
  if (next.visibility !== "space") next.spaceId = null;
  if (next.visibility !== "church") next.churchId = null;
  return next;
}

function cleanRenderMode(value: unknown): NoteShareRenderMode {
  return value === "postcard" ? "postcard" : "selah";
}

function smartActionsFor(
  scriptureRefs: string[],
  renderBlocks: Array<Record<string, unknown>>
): Array<Record<string, string>> {
  const joined = renderBlocks.map((block) => String(block.text ?? "")).join("\n").toLowerCase();
  const actions: Array<Record<string, string>> = [];
  if (scriptureRefs.length > 0) {
    actions.push({ id: "study_passage", label: "Study the passage", systemIcon: "book.closed", intent: "berean_context" });
  }
  if (/(pray|prayer|intercede|burden)/i.test(joined)) {
    actions.push({ id: "pray_through", label: "Pray through this", systemIcon: "hands.sparkles", intent: "prayer" });
  }
  if (/(action|this week|practice|serve|follow up|call|text)/i.test(joined)) {
    actions.push({ id: "save_next_step", label: "Save next step", systemIcon: "checkmark.circle", intent: "action" });
  }
  if (actions.length === 0) {
    actions.push({ id: "reflect_quietly", label: "Reflect quietly", systemIcon: "text.bubble", intent: "reflection" });
  }
  return actions.slice(0, 3);
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
  const uid = String(data.userId ?? data.authorId ?? data.authorUid ?? data.ownerUid ?? "");
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

async function serverResolvedOrgId(uid: string): Promise<string | null> {
  const userSnap = await db.collection("users").doc(uid).get();
  const user = userSnap.data() ?? {};
  const directOrg = typeof user.orgId === "string" ? user.orgId : (typeof user.churchId === "string" ? user.churchId : null);
  if (directOrg) return directOrg;

  const membershipSnaps = await Promise.all([
    db.collection("organizationMemberships").where("uid", "==", uid).where("status", "in", ["active", "member"]).limit(1).get().catch(() => null),
    db.collection("orgMemberships").where("uid", "==", uid).where("status", "in", ["active", "member"]).limit(1).get().catch(() => null),
  ]);
  for (const snap of membershipSnaps) {
    const doc = snap?.docs[0];
    const data = doc?.data() ?? {};
    const orgId = typeof data.orgId === "string" ? data.orgId : (typeof data.churchId === "string" ? data.churchId : null);
    if (orgId) return orgId;
  }
  return null;
}

async function hasMutualConnection(viewerUid: string, authorUid: string): Promise<boolean> {
  const forwardRefs = [
    db.collection("follows_index").doc(`${viewerUid}_${authorUid}`),
    db.collection("users").doc(authorUid).collection("followers").doc(viewerUid),
    db.collection("users").doc(viewerUid).collection("following").doc(authorUid),
  ];
  const reverseRefs = [
    db.collection("follows_index").doc(`${authorUid}_${viewerUid}`),
    db.collection("users").doc(viewerUid).collection("followers").doc(authorUid),
    db.collection("users").doc(authorUid).collection("following").doc(viewerUid),
  ];
  const [forwardSnaps, reverseSnaps] = await Promise.all([
    Promise.all(forwardRefs.map((ref) => ref.get().catch(() => null))),
    Promise.all(reverseRefs.map((ref) => ref.get().catch(() => null))),
  ]);
  return forwardSnaps.some((snap) => snap?.exists === true) && reverseSnaps.some((snap) => snap?.exists === true);
}

async function hasOrganizationMemberRole(uid: string, orgId: string): Promise<boolean> {
  const memberRoles = new Set(["member", "leader", "owner", "admin", "executive_admin", "pastor", "moderator", "content_manager", "volunteer_lead"]);
  const refs = [
    db.collection("organizations").doc(orgId).collection("members").doc(uid),
    db.collection("orgs").doc(orgId).collection("members").doc(uid),
    db.collection("churches").doc(orgId).collection("members").doc(uid),
    db.collection("users").doc(uid).collection("organizationMemberships").doc(orgId),
  ];
  const snaps = await Promise.all(refs.map((ref) => ref.get().catch(() => null)));
  for (const snap of snaps) {
    if (!snap?.exists) continue;
    const data = snap.data() ?? {};
    const status = String(data.status ?? data.membershipStatus ?? "active");
    const role = String(data.role ?? data.rbacRole ?? "member");
    if (!["removed", "revoked", "blocked", "inactive"].includes(status) && memberRoles.has(role)) return true;
  }
  const querySnaps = await Promise.all([
    db.collection("organizationMemberships").where("uid", "==", uid).where("orgId", "==", orgId).limit(1).get().catch(() => null),
    db.collection("orgMemberships").where("uid", "==", uid).where("orgId", "==", orgId).limit(1).get().catch(() => null),
  ]);
  return querySnaps.some((snap) => {
    const data = snap?.docs[0]?.data() ?? {};
    const status = String(data.status ?? data.membershipStatus ?? "active");
    const role = String(data.role ?? data.rbacRole ?? "member");
    return snap !== null && !snap.empty && !["removed", "revoked", "blocked", "inactive"].includes(status) && memberRoles.has(role);
  });
}

export function noteShareAccessDecisionForTest(params: {
  status: NoteShareStatus;
  viewerUid: string | null;
  authorUid: string;
  visibility: NoteShareVisibility;
  linkToken?: string | null;
  providedLinkToken?: string | null;
  hasMutualConnection?: boolean;
  hasOrganizationMemberRole?: boolean;
}): boolean {
  if (params.status !== "active") return false;
  if (!params.viewerUid) return false;
  if (params.viewerUid === params.authorUid) return true;
  switch (params.visibility) {
    case "public":
      return true;
    case "link":
      return Boolean(params.providedLinkToken && params.linkToken && params.providedLinkToken === params.linkToken);
    case "followers":
      return params.hasMutualConnection === true;
    case "church":
      return params.hasOrganizationMemberRole === true;
    case "space":
      return false;
    default:
      return false;
  }
}

async function canReadShare(share: NoteShareDocument, viewerUid: string, providedLinkToken = ""): Promise<boolean> {
  if (share.status !== "active") return false;
  if (viewerUid === share.authorUid) return true;
  switch (share.shareConfig.visibility) {
    case "public":
      return true;
    case "link":
      return Boolean(providedLinkToken && share.linkToken && providedLinkToken === share.linkToken);
    case "followers":
      return hasMutualConnection(viewerUid, share.authorUid);
    case "church": {
      return Boolean(share.shareConfig.churchId && await hasOrganizationMemberRole(viewerUid, share.shareConfig.churchId));
    }
    case "space":
      if (!share.shareConfig.spaceId) return false;
      return (await db.collection("spaces").doc(share.shareConfig.spaceId).collection("members").doc(viewerUid).get()).exists;
    default:
      return false;
  }
}

async function loadShare(shareId: string, uid: string, providedLinkToken = ""): Promise<{ ref: admin.firestore.DocumentReference; share: NoteShareDocument }> {
  const ref = db.collection("noteShares").doc(shareId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Shared note not found.");
  const share = snap.data() as NoteShareDocument;
  if (!(await canReadShare(share, uid, providedLinkToken))) throw new HttpsError("permission-denied", "You do not have access to this shared note.");
  return { ref, share };
}

async function notePreview(
  noteId: string,
  data: admin.firestore.DocumentData,
  selectedBlockIds: string[]
): Promise<{ title: string; subtitle: string | null; scriptureRefs: string[]; churchName: string | null; renderBlocks: Array<Record<string, unknown>>; smartActions: Array<Record<string, string>> }> {
  const title = String(data.title ?? data.sermonTitle ?? "Church Note").slice(0, 160);
  const subtitle = typeof data.summaryDraft === "string" ? data.summaryDraft.slice(0, 240) : (typeof data.subtitle === "string" ? data.subtitle.slice(0, 240) : null);
  const rawRefs = Array.isArray(data.scriptureRefs) ? data.scriptureRefs : (Array.isArray(data.scriptureReferences) ? data.scriptureReferences : []);
  const scriptureRefs = rawRefs.map((ref) => String(ref)).filter(Boolean).slice(0, 24);
  const churchName = typeof data.churchName === "string" ? data.churchName : null;
  const selected = new Set(selectedBlockIds);
  const blocksSnap = await db.collection("churchNotes").doc(noteId).collection("blocks").orderBy("sortOrder").limit(100).get();
  const renderBlocks = blocksSnap.docs
    .filter((doc) => {
      const block = doc.data();
      const visibility = String(block.visibility ?? "");
      const shareable = ["shareable", "selectedForPostPreview", "selectedForSelahEmphasis"].includes(visibility);
      return shareable && (selected.size === 0 || selected.has(doc.id));
    })
    .map((doc) => {
      const block = doc.data();
      return {
        id: doc.id,
        kind: String(block.type ?? block.blockType ?? "paragraph"),
        semanticType: String(block.semanticType ?? "general"),
        visibility: String(block.visibility ?? ""),
        text: String(block.text ?? "").trim().slice(0, 4000),
        payload: null,
      };
    })
    .filter((block) => block.text.length > 0)
    .slice(0, 30);
  return { title, subtitle, scriptureRefs, churchName, renderBlocks, smartActions: smartActionsFor(scriptureRefs, renderBlocks) };
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
  const verdict = validateThinkFirst(body);
  const needsReview = verdict.action === "block" || verdict.action === "requireEdit";
  return {
    status: needsReview ? "pending" : "published",
    guardianVerdict: {
      provider: "noteSharePrePublish",
      status: needsReview ? "review" : "safe",
      action: verdict.action,
      maxSeverity: verdict.maxSeverity,
      categories: verdict.categories,
    },
  };
}

export const noteShareCreate = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
  requireApp(request);
  const uid = requireAuth(request);
  await enforceRateLimit(uid, "noteShareCreate", 8);
  const noteId = cleanString(request.data?.noteId, "noteId", 160);
  if (!(await canManageNote(noteId, uid))) throw new HttpsError("permission-denied", "You cannot share this note.");
  const source = await noteAuthor(noteId);
  const config = cleanConfig(request.data?.shareConfig);
  if (config.visibility === "church") {
    const sourceOrgId = typeof source.data.orgId === "string"
      ? source.data.orgId
      : (typeof source.data.churchId === "string" ? source.data.churchId : null);
    config.churchId = sourceOrgId ?? await serverResolvedOrgId(uid);
  }
  if (config.visibility === "church" && !config.churchId) throw new HttpsError("failed-precondition", "Church visibility requires an organization membership.");
  if (config.visibility === "space" && !config.spaceId) throw new HttpsError("invalid-argument", "Space visibility requires spaceId.");
  const selectedBlockIds = Array.isArray(request.data?.selectedBlockIds)
    ? request.data.selectedBlockIds.map((value: unknown) => String(value).trim()).filter(Boolean).slice(0, 30)
    : [];
  const preview = await notePreview(noteId, source.data, selectedBlockIds);
  if (preview.renderBlocks.length === 0) throw new HttpsError("failed-precondition", "This note has no shareable blocks.");
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
  await enforceRateLimit(uid, "noteShareUpdateConfig", 20);
  const shareId = cleanString(request.data?.shareId, "shareId", 160);
  const ref = db.collection("noteShares").doc(shareId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Shared note not found.");
  const share = snap.data() as NoteShareDocument;
  if (share.authorUid !== uid) throw new HttpsError("permission-denied", "Only the author can update sharing.");
  const shareConfig = cleanPartialConfig(request.data?.partialConfig, share.shareConfig);
  if (shareConfig.visibility === "church") {
    shareConfig.churchId = share.shareConfig.churchId ?? await serverResolvedOrgId(uid);
  }
  if (shareConfig.visibility === "church" && !shareConfig.churchId) throw new HttpsError("failed-precondition", "Church visibility requires an organization membership.");
  if (shareConfig.visibility === "space" && !shareConfig.spaceId) throw new HttpsError("invalid-argument", "Space visibility requires spaceId.");
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
  await enforceRateLimit(uid, "noteShareRevoke", 20);
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
  const link = typeof request.data?.linkToken === "string" ? request.data.linkToken : "";
  const { ref, share } = await loadShare(shareId, uid, link);
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
  await enforceRateLimit(uid, "noteShareGetViewerPayload", 60);
  const link = typeof request.data?.linkToken === "string" ? request.data.linkToken : "";
  let shareId = typeof request.data?.shareId === "string" ? request.data.shareId : "";
  if (!shareId && link) {
    const tokenSnap = await db.collection("noteShares").where("linkToken", "==", link).limit(1).get();
    shareId = tokenSnap.docs[0]?.id ?? "";
  }
  if (!shareId) throw new HttpsError("invalid-argument", "shareId or linkToken is required.");
  const { ref, share } = await loadShare(shareId, uid, link);
  const amen = await ref.collection("amens").doc(uid).get();
  const reflections = share.shareConfig.allowComments === "off"
    ? null
    : await ref.collection("reflections").where("status", "==", "published").orderBy("createdAt", "asc").limit(25).get();
  return {
    shareId,
    noteId: share.noteId,
    title: share.title ?? "Church Note",
    subtitle: share.subtitle ?? null,
    eyebrow: share.churchName ? `FROM SUNDAY · ${share.churchName}` : "CHURCH NOTE",
    scriptureRefs: share.scriptureRefs ?? [],
    renderMode: share.renderMode,
    renderBlocks: share.renderBlocks ?? [],
    smartActions: share.smartActions ?? smartActionsFor(share.scriptureRefs ?? [], share.renderBlocks ?? []),
    shareConfig: publicConfig(share.shareConfig),
    myAmenState: amen.exists,
    reflectionsPage: {
      reflections: reflections?.docs.map((doc) => ({ id: doc.id, ...doc.data(), body: doc.data().body ?? "" })) ?? [],
      nextCursor: reflections && reflections.docs.length === 25 ? reflections.docs[24].id : null,
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
  await enforceRateLimit(uid, "noteShareListReflections", 60);
  const shareId = cleanString(request.data?.shareId, "shareId", 160);
  const link = typeof request.data?.linkToken === "string" ? request.data.linkToken : "";
  const { ref, share } = await loadShare(shareId, uid, link);
  if (share.shareConfig.allowComments === "off" && share.authorUid !== uid) {
    return { reflections: [], nextCursor: null };
  }
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
  const link = typeof request.data?.linkToken === "string" ? request.data.linkToken : "";
  const { ref, share } = await loadShare(shareId, uid, link);
  if (share.shareConfig.allowComments === "off") throw new HttpsError("failed-precondition", "Reflections are off for this note.");
  if (share.shareConfig.allowComments === "church") {
    if (!share.shareConfig.churchId || !await hasOrganizationMemberRole(uid, share.shareConfig.churchId)) {
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

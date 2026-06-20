// communities/communitiesCallables.ts
// AMEN — Amen Communities · Wave 1 · Cloud Functions (us-east1). Source of shapes: contracts/communities.ts.
// Pure logic: communitiesLogic.ts. All callables enforce App Check + auth and are FAIL-CLOSED on the
// server flag (communities_enabled defaults OFF — a new feature is unavailable unless explicitly turned on).
//
// FOUNDER RULING (hybrid): membership/role writes here ARE the tier-free machinery. Covenant's paid join
// wraps Stripe checkout around an equivalent membership write; we deliberately do not couple to it.
//
// Firestore model (matches Contracts/communities.firestore.rules.scaffold):
//   communities/{communityId}                         Community
//   communities/{communityId}/members/{userId}        CommunityMembership
//   users/{userId}/communityMemberships/{communityId} mirror index (profile + getUserCommunities)
//
// SAFETY: ageRating gate (CI5) via request.auth.token.ageTier; memberCount is a display count (CI2);
// no exact location is ever written (CI3); moderation/reports route into GUARDIAN in Wave 2 (CI4).

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {
  Community,
  CommunityMembership,
  CreateCommunityResult,
  GetCommunityResult,
  JoinCommunityResult,
  LeaveCommunityResult,
  PatchCommunityResult,
  RequestJoinCommunityResult,
} from "../contracts/communities";
import {
  ageAllowed,
  buildSafeJoinPreview,
  evaluateJoin,
  roleCanManage,
  slugify,
  slugWithSuffix,
} from "./communitiesLogic";

const REGION = "us-east1";
const callableOpts = { region: REGION, enforceAppCheck: true, timeoutSeconds: 20 } as const;

type Db = FirebaseFirestore.Firestore;

// ─── Server feature gate (fail-closed; new feature defaults OFF) ──────────────
// Reads system/serverFeatureFlags (admin-only). Unlike safety flags (default ON), a new product
// feature defaults OFF: a missing doc/field or any read error → feature UNAVAILABLE.
let gateCache: { enabled: boolean; at: number } | null = null;
const GATE_TTL_MS = 5 * 60 * 1000;

async function communitiesEnabled(db: Db): Promise<boolean> {
  const now = Date.now();
  if (gateCache && now - gateCache.at < GATE_TTL_MS) return gateCache.enabled;
  try {
    const snap = await db.collection("system").doc("serverFeatureFlags").get();
    const v = snap.exists ? snap.data()?.communitiesEnabled : undefined;
    const enabled = v === true; // fail-closed: only an explicit true enables
    gateCache = { enabled, at: now };
    return enabled;
  } catch (err) {
    functions.logger.error("[Communities] server flag read failed — treating as OFF.", err);
    return false; // fail-closed
  }
}

async function assertEnabled(db: Db): Promise<void> {
  if (!(await communitiesEnabled(db))) {
    throw new HttpsError("failed-precondition", "Communities is not available.");
  }
}

// ─── Small helpers ───────────────────────────────────────────────────────────

interface CallableAuth { uid: string; token?: Record<string, unknown> }

function requireAuth(request: { auth?: CallableAuth | null }): CallableAuth {
  if (!request.auth) throw new HttpsError("unauthenticated", "Auth required");
  return request.auth;
}

function readString(value: unknown, field: string): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value.trim();
}

function optString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function ageTierOf(auth: CallableAuth): string | null {
  const t = auth.token?.ageTier;
  return typeof t === "string" ? t : null;
}

async function loadCommunity(db: Db, id: string): Promise<Community> {
  const snap = await db.collection("communities").doc(id).get();
  if (!snap.exists) throw new HttpsError("not-found", "No such community.");
  return snap.data() as Community;
}

async function loadMembership(db: Db, id: string, uid: string): Promise<CommunityMembership | null> {
  const snap = await db.collection("communities").doc(id).collection("members").doc(uid).get();
  return snap.exists ? (snap.data() as CommunityMembership) : null;
}

/** Write both the membership doc and the user-side mirror index in one batch. */
function writeMembership(db: Db, m: CommunityMembership): FirebaseFirestore.WriteBatch {
  const batch = db.batch();
  batch.set(db.collection("communities").doc(m.communityId).collection("members").doc(m.userId), m);
  batch.set(
    db.collection("users").doc(m.userId).collection("communityMemberships").doc(m.communityId),
    { communityId: m.communityId, role: m.role, status: m.status, joinedAt: m.joinedAt },
  );
  return batch;
}

// ════════════════════════════════════════════════════════════════════
// Callables — CRUD
// ════════════════════════════════════════════════════════════════════

/** POST /communities — create a community; caller becomes owner (active member). */
export const createCommunity = onCall(callableOpts, async (request) => {
  const auth = requireAuth(request);
  const db = admin.firestore();
  await assertEnabled(db);

  const d = (request.data ?? {}) as Record<string, unknown>;
  const name = readString(d.name, "name");
  const description = typeof d.description === "string" ? d.description : "";
  const category = readString(d.category, "category");
  const ageRating = (d.ageRating === "teen" || d.ageRating === "adult") ? d.ageRating : "everyone";

  // CI5: a minor cannot create an adult-only community.
  if (!ageAllowed(ageRating, ageTierOf(auth))) {
    throw new HttpsError("permission-denied", "Your account can't create this community.");
  }

  // Unique slug: try base, else append the new doc id's tail.
  const ref = db.collection("communities").doc();
  const base = slugify(optString(d.slug) ?? name);
  const existing = await db.collection("communities").where("slug", "==", base).limit(1).get();
  const slug = existing.empty ? base : slugWithSuffix(base, ref.id.slice(0, 6).toLowerCase());

  const now = Date.now();
  const community: Community = {
    id: ref.id,
    name,
    slug,
    iconUrl: optString(d.iconUrl),
    bannerUrl: optString(d.bannerUrl),
    description,
    category,
    tags: Array.isArray(d.tags) ? (d.tags as unknown[]).filter((t): t is string => typeof t === "string").slice(0, 20) : [],
    visibility: (["public", "private", "local", "unlisted"].includes(d.visibility as string) ? d.visibility : "public") as Community["visibility"],
    joinPolicy: (["open", "requestToJoin", "inviteOnly", "closed"].includes(d.joinPolicy as string) ? d.joinPolicy : "open") as Community["joinPolicy"],
    postPolicy: (["allMembers", "trustedAndAbove", "moderatorsOnly", "leadersOnly"].includes(d.postPolicy as string) ? d.postPolicy : "allMembers") as Community["postPolicy"],
    commentPolicy: (["allMembers", "membersOnly", "moderatorsOnly", "off"].includes(d.commentPolicy as string) ? d.commentPolicy : "allMembers") as Community["commentPolicy"],
    governance: (["none", "orgManaged", "schoolManaged", "churchManaged", "creatorLed"].includes(d.governance as string) ? d.governance : "none") as Community["governance"],
    ageRating,
    locationMode: (d.locationMode === "fuzzyRegion" ? "fuzzyRegion" : "none"),
    approximateRegion: optString(d.approximateRegion), // CI3: coarse label only — caller must never send coordinates
    sensitive: d.sensitive === true,
    anonymousPostingAllowed: d.anonymousPostingAllowed === true,
    ownerId: auth.uid,
    verifiedStatus: "none",
    healthScore: 0,
    memberCount: 1,
    onlineCount: 0,
    recentPostCount: 0,
    flairRequired: d.flairRequired === true,
    createdAt: now,
    updatedAt: now,
  };

  const ownerMembership: CommunityMembership = {
    id: auth.uid,
    communityId: ref.id,
    userId: auth.uid,
    role: "owner",
    status: "active",
    notificationLevel: "all",
    profileVisibility: "showPublicly",
    joinedAt: now,
    lastActiveAt: now,
  };

  const batch = writeMembership(db, ownerMembership);
  batch.set(ref, community);
  await batch.commit();

  const result: CreateCommunityResult = { community };
  return result;
});

/** GET /communities/:id — community + caller membership + safe-join preview. */
export const getCommunity = onCall(callableOpts, async (request) => {
  const auth = requireAuth(request);
  const db = admin.firestore();
  await assertEnabled(db);

  const id = readString(request.data?.id, "id");
  const community = await loadCommunity(db, id);
  const membership = await loadMembership(db, id, auth.uid);

  const result: GetCommunityResult = {
    community,
    membership,
    safeJoinPreview: buildSafeJoinPreview(community),
  };
  return result;
});

/** PATCH /communities/:id — owner/admin edits settings. */
export const patchCommunity = onCall(callableOpts, async (request) => {
  const auth = requireAuth(request);
  const db = admin.firestore();
  await assertEnabled(db);

  const id = readString(request.data?.id, "id");
  const patch = (request.data?.patch ?? {}) as Record<string, unknown>;

  const membership = await loadMembership(db, id, auth.uid);
  if (!membership || !roleCanManage(membership.role)) {
    throw new HttpsError("permission-denied", "Admin role required to edit this community.");
  }

  const allowed: Array<keyof Community> = [
    "name", "description", "category", "tags", "visibility", "joinPolicy", "postPolicy",
    "commentPolicy", "governance", "ageRating", "locationMode", "approximateRegion",
    "sensitive", "anonymousPostingAllowed", "flairRequired", "iconUrl", "bannerUrl",
  ];
  const update: Record<string, unknown> = { updatedAt: Date.now() };
  for (const key of allowed) {
    if (key in patch) update[key] = patch[key];
  }
  await db.collection("communities").doc(id).set(update, { merge: true });

  const community = await loadCommunity(db, id);
  const result: PatchCommunityResult = { community };
  return result;
});

/** DELETE /communities/:id — owner only. Recursively removes the community + members. */
export const deleteCommunity = onCall(callableOpts, async (request) => {
  const auth = requireAuth(request);
  const db = admin.firestore();
  await assertEnabled(db);

  const id = readString(request.data?.id, "id");
  const community = await loadCommunity(db, id);
  if (community.ownerId !== auth.uid) {
    throw new HttpsError("permission-denied", "Only the owner can delete this community.");
  }
  await admin.firestore().recursiveDelete(db.collection("communities").doc(id));
  return { ok: true as const };
});

// ════════════════════════════════════════════════════════════════════
// Callables — membership lifecycle (tier-free machinery)
// ════════════════════════════════════════════════════════════════════

/** POST /communities/:id/join — join under the community's join policy. */
export const joinCommunity = onCall(callableOpts, async (request) => {
  const auth = requireAuth(request);
  const db = admin.firestore();
  await assertEnabled(db);

  const id = readString(request.data?.id, "id");
  const flair = optString(request.data?.flair);
  const community = await loadCommunity(db, id);

  if (!ageAllowed(community.ageRating, ageTierOf(auth))) {
    throw new HttpsError("permission-denied", "Your account can't join this community.");
  }

  const existing = await loadMembership(db, id, auth.uid);
  if (existing && existing.status === "active") {
    const already: JoinCommunityResult = { membership: existing };
    return already;
  }
  if (existing && existing.status === "banned") {
    throw new HttpsError("permission-denied", "You can't join this community.");
  }

  const evalResult = evaluateJoin(community.joinPolicy);
  let status: CommunityMembership["status"];
  switch (evalResult.decision) {
    case "active":
      status = "active";
      break;
    case "pending":
      status = "pending";
      break;
    case "invite": {
      const inv = await db.collection("communities").doc(id).collection("invites")
        .where("inviteeId", "==", auth.uid).where("status", "==", "pending").limit(1).get();
      if (inv.empty) throw new HttpsError("permission-denied", "This community is invite-only.");
      status = "active";
      break;
    }
    case "reject":
      throw new HttpsError("failed-precondition", "This community isn't accepting new members.");
  }

  const now = Date.now();
  const membership: CommunityMembership = {
    id: auth.uid,
    communityId: id,
    userId: auth.uid,
    role: "member",
    status,
    flair,
    notificationLevel: "highlights",
    profileVisibility: "showPublicly",
    joinedAt: now,
    lastActiveAt: now,
  };

  // Increment the display member count only for active joins (CI2 — display, not status).
  await db.runTransaction(async (tx) => {
    const cRef = db.collection("communities").doc(id);
    tx.set(cRef.collection("members").doc(auth.uid), membership);
    tx.set(
      db.collection("users").doc(auth.uid).collection("communityMemberships").doc(id),
      { communityId: id, role: membership.role, status: membership.status, joinedAt: now },
    );
    if (status === "active") {
      tx.update(cRef, { memberCount: admin.firestore.FieldValue.increment(1) });
    }
  });

  const result: JoinCommunityResult = { membership };
  return result;
});

/** POST /communities/:id/request-join — record a pending join request. */
export const requestJoinCommunity = onCall(callableOpts, async (request) => {
  const auth = requireAuth(request);
  const db = admin.firestore();
  await assertEnabled(db);

  const id = readString(request.data?.id, "id");
  const community = await loadCommunity(db, id);
  if (!ageAllowed(community.ageRating, ageTierOf(auth))) {
    throw new HttpsError("permission-denied", "Your account can't join this community.");
  }

  const now = Date.now();
  const membership: CommunityMembership = {
    id: auth.uid,
    communityId: id,
    userId: auth.uid,
    role: "member",
    status: "pending",
    notificationLevel: "highlights",
    profileVisibility: "showPublicly",
    joinedAt: now,
    lastActiveAt: now,
  };
  await writeMembership(db, membership).commit();

  const result: RequestJoinCommunityResult = { membership };
  return result;
});

/** POST /communities/:id/leave — leave; the owner must transfer ownership first. */
export const leaveCommunity = onCall(callableOpts, async (request) => {
  const auth = requireAuth(request);
  const db = admin.firestore();
  await assertEnabled(db);

  const id = readString(request.data?.id, "id");
  const membership = await loadMembership(db, id, auth.uid);
  if (!membership) {
    const noop: LeaveCommunityResult = { ok: true };
    return noop;
  }
  if (membership.role === "owner") {
    throw new HttpsError("failed-precondition", "Transfer ownership before leaving this community.");
  }

  const wasActive = membership.status === "active";
  await db.runTransaction(async (tx) => {
    const cRef = db.collection("communities").doc(id);
    tx.delete(cRef.collection("members").doc(auth.uid));
    tx.delete(db.collection("users").doc(auth.uid).collection("communityMemberships").doc(id));
    if (wasActive) {
      tx.update(cRef, { memberCount: admin.firestore.FieldValue.increment(-1) });
    }
  });

  const result: LeaveCommunityResult = { ok: true };
  return result;
});

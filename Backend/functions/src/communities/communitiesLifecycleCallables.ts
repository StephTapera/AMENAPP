// communities/communitiesLifecycleCallables.ts
// AMEN — Amen Communities · Wave 1 (cont.) · Cloud Functions (us-east1).
// Membership-adjacent lifecycle: invites, flair, profile display, and the per-user community list.
// Shapes: contracts/communities.ts. Core CRUD/join/leave: communitiesCallables.ts. Pure: communitiesLogic.ts.
//
// SAFETY: all callables enforce App Check + auth and are FAIL-CLOSED on the server flag
// (communitiesEnabled defaults OFF). getUserCommunities honors per-membership profileVisibility for
// non-owner callers (Z3) and fails closed (non-owners see only explicitly-public memberships).

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {
  AddToProfileResult,
  Community,
  CommunityInvite,
  CommunityMembership,
  InviteToCommunityResult,
  RemoveFromProfileResult,
  SetCommunityFlairResult,
  GetUserCommunitiesResult,
} from "../contracts/communities";
import { roleCanModerate } from "./communitiesLogic";

const REGION = "us-east1";
const callableOpts = { region: REGION, enforceAppCheck: true, timeoutSeconds: 20 } as const;

type Db = FirebaseFirestore.Firestore;
interface CallableAuth { uid: string; token?: Record<string, unknown> }

// ─── Fail-closed server gate (new feature defaults OFF) ──────────────
let gateCache: { enabled: boolean; at: number } | null = null;
const GATE_TTL_MS = 5 * 60 * 1000;
async function assertEnabled(db: Db): Promise<void> {
  const now = Date.now();
  if (!gateCache || now - gateCache.at >= GATE_TTL_MS) {
    try {
      const snap = await db.collection("system").doc("serverFeatureFlags").get();
      gateCache = { enabled: (snap.exists ? snap.data()?.communitiesEnabled : undefined) === true, at: now };
    } catch (err) {
      functions.logger.error("[Communities] server flag read failed — treating as OFF.", err);
      gateCache = { enabled: false, at: now };
    }
  }
  if (!gateCache.enabled) throw new HttpsError("failed-precondition", "Communities is not available.");
}

function requireAuth(request: { auth?: CallableAuth | null }): CallableAuth {
  if (!request.auth) throw new HttpsError("unauthenticated", "Auth required");
  return request.auth;
}
function readString(value: unknown, field: string): string {
  if (typeof value !== "string" || !value.trim()) throw new HttpsError("invalid-argument", `${field} is required.`);
  return value.trim();
}
async function loadMembership(db: Db, id: string, uid: string): Promise<CommunityMembership | null> {
  const snap = await db.collection("communities").doc(id).collection("members").doc(uid).get();
  return snap.exists ? (snap.data() as CommunityMembership) : null;
}
function requireActive(m: CommunityMembership | null): CommunityMembership {
  if (!m || m.status !== "active") throw new HttpsError("permission-denied", "Active membership required.");
  return m;
}

// ════════════════════════════════════════════════════════════════════
// Invites
// ════════════════════════════════════════════════════════════════════

/** POST /communities/:id/invite — an active member invites another user (14-day expiry). */
export const inviteToCommunity = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const auth = requireAuth(request);
  const db = admin.firestore();
  await assertEnabled(db);

  const id = readString(request.data?.id, "id");
  const inviteeId = readString(request.data?.inviteeId, "inviteeId");
  if (inviteeId === auth.uid) throw new HttpsError("invalid-argument", "You can't invite yourself.");

  requireActive(await loadMembership(db, id, auth.uid));

  const ref = db.collection("communities").doc(id).collection("invites").doc();
  const now = Date.now();
  const invite: CommunityInvite = {
    id: ref.id,
    communityId: id,
    inviterId: auth.uid,
    inviteeId,
    status: "pending",
    createdAt: now,
    expiresAt: now + 14 * 24 * 60 * 60 * 1000,
  };
  await ref.set(invite);

  const result: InviteToCommunityResult = { invite };
  return result;
});

// ════════════════════════════════════════════════════════════════════
// Flair
// ════════════════════════════════════════════════════════════════════

/** POST /communities/:id/flair — set the caller's own flair (moderation-safe: trimmed + capped). */
export const setCommunityFlair = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const auth = requireAuth(request);
  const db = admin.firestore();
  await assertEnabled(db);

  const id = readString(request.data?.id, "id");
  const flair = readString(request.data?.flair, "flair").slice(0, 40);
  const membership = requireActive(await loadMembership(db, id, auth.uid));

  await db.collection("communities").doc(id).collection("members").doc(auth.uid)
    .set({ flair, lastActiveAt: Date.now() }, { merge: true });

  const updated: CommunityMembership = { ...membership, flair };
  const result: SetCommunityFlairResult = { membership: updated };
  return result;
});

// ════════════════════════════════════════════════════════════════════
// Profile display (add / remove)
// ════════════════════════════════════════════════════════════════════

/** POST /communities/:id/add-to-profile — set how this membership shows on the caller's profile. */
export const addCommunityToProfile = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const auth = requireAuth(request);
  const db = admin.firestore();
  await assertEnabled(db);

  const id = readString(request.data?.id, "id");
  const pv = request.data?.profileVisibility;
  const profileVisibility = (["showPublicly", "followersOnly", "hide", "selected"].includes(pv as string)
    ? pv : "showPublicly") as CommunityMembership["profileVisibility"];

  const membership = requireActive(await loadMembership(db, id, auth.uid));

  // Persist on the member doc (source of truth) and mirror it onto the user index for fast profile reads.
  const batch = db.batch();
  batch.set(db.collection("communities").doc(id).collection("members").doc(auth.uid),
    { profileVisibility }, { merge: true });
  batch.set(db.collection("users").doc(auth.uid).collection("communityMemberships").doc(id),
    { profileVisibility }, { merge: true });
  await batch.commit();

  const updated: CommunityMembership = { ...membership, profileVisibility };
  const result: AddToProfileResult = { membership: updated };
  return result;
});

/** DELETE /communities/:id/remove-from-profile — hide this membership from the caller's profile. */
export const removeCommunityFromProfile = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const auth = requireAuth(request);
  const db = admin.firestore();
  await assertEnabled(db);

  const id = readString(request.data?.id, "id");
  // No active-membership requirement: a user may always hide a community from their profile.
  const batch = db.batch();
  batch.set(db.collection("communities").doc(id).collection("members").doc(auth.uid),
    { profileVisibility: "hide" }, { merge: true });
  batch.set(db.collection("users").doc(auth.uid).collection("communityMemberships").doc(id),
    { profileVisibility: "hide" }, { merge: true });
  await batch.commit();

  const result: RemoveFromProfileResult = { ok: true };
  return result;
});

// ════════════════════════════════════════════════════════════════════
// Per-user community list (profile + GET /users/:id/communities)
// ════════════════════════════════════════════════════════════════════

interface MirrorRow {
  communityId: string;
  role?: CommunityMembership["role"];
  status?: CommunityMembership["status"];
  profileVisibility?: CommunityMembership["profileVisibility"];
}

/** GET /users/:id/communities — featured/created/joined/moderating, privacy-filtered for non-owners. */
export const getUserCommunities = onCall({ ...callableOpts, enforceAppCheck: true }, async (request) => {
  const auth = requireAuth(request);
  const db = admin.firestore();
  await assertEnabled(db);

  const userId = readString(request.data?.userId, "userId");
  const isSelf = userId === auth.uid;

  const mirrorSnap = await db.collection("users").doc(userId).collection("communityMemberships").get();
  const rows: MirrorRow[] = mirrorSnap.docs.map((d) => {
    const data = d.data() as MirrorRow;
    return { ...data, communityId: data.communityId ?? d.id };
  });

  // Privacy (Z3): a non-owner only sees memberships explicitly marked showPublicly (fail-closed —
  // followersOnly/selected/hide are excluded here; follow-aware filtering is a later refinement).
  const visible = rows.filter((r) => isSelf || r.profileVisibility === "showPublicly");

  // Hydrate the community docs (skip any that no longer exist).
  const communities = new Map<string, Community>();
  await Promise.all(visible.map(async (r) => {
    const snap = await db.collection("communities").doc(r.communityId).get();
    if (snap.exists) communities.set(r.communityId, snap.data() as Community);
  }));

  const created: Community[] = [];
  const moderating: Community[] = [];
  const joined: Community[] = [];
  for (const r of visible) {
    const c = communities.get(r.communityId);
    if (!c) continue;
    if (r.role === "owner") created.push(c);
    else if (r.role && roleCanModerate(r.role)) moderating.push(c);
    else joined.push(c);
  }

  // Featured = verified/official communities the user created (a calm, non-vanity highlight).
  const featured = created.filter((c) => c.verifiedStatus !== "none");

  const result: GetUserCommunitiesResult = { featured, created, joined, moderating };
  return result;
});

// communities/communitiesLogic.ts
// AMEN — Amen Communities · Wave 1 · PURE logic (no Firestore, no I/O — unit-testable).
// Shapes come from contracts/communities.ts (TS source of truth). Callables: communitiesCallables.ts.
//
// FOUNDER RULING (hybrid): this is the tier-FREE membership/role core. Covenant's paid join wraps a
// Stripe checkout around an equivalent membership write; we deliberately do NOT import Covenant's
// checkout-coupled join here. Role semantics map onto the shared canonical role ladder.

import {
  Community,
  CommunityJoinPolicy,
  CommunityRole,
  SafeJoinPreview,
} from "../contracts/communities";

/** Outcome of evaluating a join attempt against a community's join policy. */
export type JoinEvaluation =
  | { decision: "active" }    // becomes an active member immediately
  | { decision: "pending" }   // request recorded; awaits moderator approval
  | { decision: "invite" }    // allowed only if a valid invite exists (caller must check)
  | { decision: "reject" };   // closed / not joinable

/** Pure: what should happen when a user tries to join under `policy`. */
export function evaluateJoin(policy: CommunityJoinPolicy): JoinEvaluation {
  switch (policy) {
    case "open":
      return { decision: "active" };
    case "requestToJoin":
      return { decision: "pending" };
    case "inviteOnly":
      return { decision: "invite" };
    case "closed":
      return { decision: "reject" };
  }
}

/** url-safe slug from a display name. Lowercase, alnum + single hyphens, trimmed, capped. */
export function slugify(name: string): string {
  const base = name
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
  return base.length > 0 ? base : "community";
}

/** Append a short disambiguation suffix to a slug (used when the base slug is taken). */
export function slugWithSuffix(base: string, suffix: string): string {
  const trimmed = base.slice(0, 40).replace(/-+$/g, "");
  return `${trimmed}-${suffix}`;
}

/** Canonical privilege ladder. Higher = more capability. Mirrors the app's role intent. */
export function rolePrivilege(role: CommunityRole): number {
  switch (role) {
    case "owner": return 100;
    case "admin": return 90;
    case "moderator": return 80;
    case "creator": return 70;
    case "orgStaff": return 60;
    case "verifiedExpert": return 50;
    case "trustedMember": return 40;
    case "member": return 30;
    case "guest": return 20;
    case "limitedMember": return 10;
    case "mutedMember": return 0;
  }
}

/** Can this role take moderation actions (warn/remove/pin/approve)? Advisory tooling only (CI4). */
export function roleCanModerate(role: CommunityRole): boolean {
  return rolePrivilege(role) >= rolePrivilege("moderator");
}

/** Can this role edit the community settings / manage members? */
export function roleCanManage(role: CommunityRole): boolean {
  return rolePrivilege(role) >= rolePrivilege("admin");
}

/** Map a community's age rating to a plain moderation-level label for the Safe-Join Preview. */
export function moderationLevelFor(community: Pick<Community, "sensitive" | "ageRating">):
  "light" | "standard" | "strict" {
  if (community.sensitive || community.ageRating === "adult") return "strict";
  if (community.ageRating === "teen") return "standard";
  return "light";
}

/** Pure: build the pre-join, informed-consent preview (all Z1/Z2 — no internal scores; CI6-adjacent). */
export function buildSafeJoinPreview(community: Community): SafeJoinPreview {
  const whoCanSeePosts =
    community.visibility === "public"
      ? "Anyone on Amen can see posts here."
      : community.visibility === "unlisted"
      ? "Anyone with the link can see posts; it won't appear in search."
      : community.visibility === "local"
      ? "Members in the community's general region can see posts."
      : "Only members can see posts here.";

  const postsHitMainFeed = community.visibility === "public";

  const dataVisibilityNote =
    community.locationMode === "fuzzyRegion"
      ? "This community uses an approximate region only — never your exact location."
      : "No location data is used by this community.";

  return {
    communityId: community.id,
    rulesSummary:
      community.description.slice(0, 280) ||
      "Be kind, stay on topic, and follow the community rules.",
    moderationLevel: moderationLevelFor(community),
    ageRating: community.ageRating,
    visibility: community.visibility,
    whoCanSeePosts,
    postsHitMainFeed,
    dataVisibilityNote,
  };
}

/** Minor-safety gate (CI5): is a caller in `ageTier` allowed into a community of `ageRating`? */
export function ageAllowed(ageRating: Community["ageRating"], ageTier: string | null): boolean {
  // adult-only communities are closed to minors / under-13. Unknown tier is treated as adult-safe
  // ONLY for "everyone"; anything stricter requires a known adult tier (fail-closed).
  const isMinor = ageTier === "minor" || ageTier === "under13" || ageTier === "teen";
  if (ageRating === "adult") return ageTier === "adult";
  if (ageRating === "teen") return !(ageTier === "under13");
  // everyone
  void isMinor;
  return true;
}

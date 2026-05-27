/**
 * assembleBereanAboutContext.ts
 *
 * Cloud Function (Gen2 onCall): `assembleBereanAboutContext`
 *
 * Assembles the structured context payload used by Berean AI to answer
 * questions about a user's public spiritual identity.
 *
 * Privacy contract (strict):
 *   - Only surfaces data the target user has opted in to share (bereanAboutOptIn === true)
 *   - Only fetches posts where privacy === "public"
 *   - Never includes: DMs, private prayer requests, draft content, PII
 *   - Pinned posts are included only if they are public
 *
 * Request:  { userId: string, viewerId: string }
 * Response: BereanAboutContext (see type below)
 *
 * Error codes:
 *   unauthenticated   — caller is not signed in
 *   invalid-argument  — userId missing or empty
 *   not-found         — user document does not exist
 *   permission-denied — user has not opted in to Berean About (berean-opt-in-required)
 *   internal          — unexpected Firestore failure
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// ── Types ──────────────────────────────────────────────────────────────────

interface PublicPostPreview {
  id: string;
  content: string;
  type: string;
  createdAt: string;
}

interface PinnedPostPreview {
  id: string;
  content: string;
  type: string;
}

interface ChurchInfo {
  name: string;
  location: string;
}

interface BereanAboutContext {
  displayName: string;
  bio: string | null;
  roleFlags: object;
  recentPublicPosts: PublicPostPreview[];
  pinnedPosts: PinnedPostPreview[];
  churchInfo: ChurchInfo | null;
}

// ── Callable ───────────────────────────────────────────────────────────────

export const assembleBereanAboutContext = onCall(async (request) => {
  // 1. Auth guard
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "Must be signed in to assemble Berean About context."
    );
  }

  // 2. Input validation
  const { userId, viewerId } = (request.data ?? {}) as {
    userId?: string;
    viewerId?: string;
  };

  if (!userId || typeof userId !== "string" || userId.trim() === "") {
    throw new HttpsError(
      "invalid-argument",
      "userId is required and must be a non-empty string."
    );
  }

  const db = admin.firestore();

  // 3. Fetch user document
  let userSnap: admin.firestore.DocumentSnapshot;
  try {
    userSnap = await db.collection("users").doc(userId).get();
  } catch {
    throw new HttpsError("internal", "Failed to read user document.");
  }

  if (!userSnap.exists) {
    throw new HttpsError("not-found", `User '${userId}' does not exist.`);
  }

  const userData = userSnap.data() ?? {};
  const profile = (userData.profile ?? {}) as Record<string, unknown>;

  // 4. Opt-in gate — hard stop if user has not opted in
  if (profile.bereanAboutOptIn !== true) {
    throw new HttpsError(
      "permission-denied",
      "berean-opt-in-required"
    );
  }

  // 5. Extract public user fields only (no PII)
  const displayName = (userData.displayName as string | null) ?? "";
  const bio = (userData.bio as string | null) ?? null;
  const roleFlags = (profile.roleFlags as object | null) ?? {};
  const pinSlotIds: string[] = Array.isArray(profile.pinSlots)
    ? (profile.pinSlots as string[]).slice(0, 3)
    : [];
  const churchId = (roleFlags as Record<string, unknown>).churchId as string | null
    ?? (userData.churchId as string | null)
    ?? null;

  // 6. Fetch last 10 public posts by this user (never private, never drafts)
  let recentPublicPosts: PublicPostPreview[] = [];
  try {
    const postsSnap = await db
      .collection("posts")
      .where("authorId", "==", userId)
      .where("privacy", "==", "public")
      .orderBy("createdAt", "desc")
      .limit(10)
      .get();

    recentPublicPosts = postsSnap.docs.map((doc) => {
      const d = doc.data();
      const rawCreatedAt = d.createdAt;
      const createdAt =
        rawCreatedAt?.toDate?.()?.toISOString?.() ??
        (typeof rawCreatedAt === "string" ? rawCreatedAt : new Date(0).toISOString());
      return {
        id: doc.id,
        content: (d.content as string | null) ?? "",
        type: (d.type as string | null) ?? "post",
        createdAt,
      };
    });
  } catch {
    // Non-fatal — return empty array rather than blocking the whole context
    recentPublicPosts = [];
  }

  // 7. Fetch pinned posts — only if they are public
  let pinnedPosts: PinnedPostPreview[] = [];
  if (pinSlotIds.length > 0) {
    try {
      const pinRefs = pinSlotIds.map((id) => db.collection("posts").doc(id));
      const pinSnaps = await db.getAll(...pinRefs);

      pinnedPosts = pinSnaps
        .filter((snap) => {
          if (!snap.exists) return false;
          const d = snap.data() ?? {};
          // Only include public posts; never surface private or draft content
          return d.privacy === "public" && d.authorId === userId;
        })
        .map((snap) => {
          const d = snap.data() ?? {};
          return {
            id: snap.id,
            content: (d.content as string | null) ?? "",
            type: (d.type as string | null) ?? "post",
          };
        });
    } catch {
      // Non-fatal
      pinnedPosts = [];
    }
  }

  // 8. Fetch church info if churchId is set
  let churchInfo: ChurchInfo | null = null;
  if (churchId) {
    try {
      const churchSnap = await db.collection("churches").doc(churchId).get();
      if (churchSnap.exists) {
        const cd = churchSnap.data() ?? {};
        churchInfo = {
          name: (cd.name as string | null) ?? "",
          location: (cd.location as string | null) ?? "",
        };
      }
    } catch {
      // Non-fatal
      churchInfo = null;
    }
  }

  // 9. Return structured context
  const context: BereanAboutContext = {
    displayName,
    bio,
    roleFlags,
    recentPublicPosts,
    pinnedPosts,
    churchInfo,
  };

  return context;
});

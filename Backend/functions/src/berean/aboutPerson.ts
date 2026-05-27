/**
 * aboutPerson.ts
 *
 * Cloud Function: `bereanAboutPersonContext`
 *
 * Fetches the public "About This Person" context payload that powers the
 * Berean "About this person" chat mode.  The user MUST have opted in via
 * `users/{userId}.profile.bereanAboutOptIn`; the server enforces this check
 * unconditionally — the client is never trusted on this gate.
 *
 * Returns only explicitly-listed public fields.  No DMs, no private prayer
 * requests, no private posts are ever included.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface AboutPersonRequest {
  userId: string;
  viewerId: string;
}

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

interface AboutPersonResponse {
  displayName: string;
  bio: string | null;
  roleFlags: Record<string, unknown>;
  recentPublicPosts: PublicPostPreview[];
  pinnedPosts: PinnedPostPreview[];
  churchInfo: ChurchInfo | null;
}

// ---------------------------------------------------------------------------
// Callable
// ---------------------------------------------------------------------------

export const bereanAboutPersonContext = onCall(
  {
    timeoutSeconds: 30,
    memory: "256MiB",
    enforceAppCheck: true,
  },
  async (request): Promise<AboutPersonResponse> => {
    // ── Auth guard ───────────────────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const { userId } = request.data as AboutPersonRequest;
    if (!userId || typeof userId !== "string" || userId.trim() === "") {
      throw new HttpsError("invalid-argument", "userId is required");
    }

    const db = admin.firestore();

    // ── Step 1: Opt-in gate ──────────────────────────────────────────────────
    // Read from users/{userId}.profile.bereanAboutOptIn only.
    // If the field is absent or explicitly false, reject immediately.
    const userSnap = await db.collection("users").doc(userId).get();

    if (!userSnap.exists) {
      throw new HttpsError("not-found", "user-not-found");
    }

    const userData = userSnap.data() ?? {};
    const profile = userData.profile ?? {};
    const optIn: boolean = profile.bereanAboutOptIn === true;

    if (!optIn) {
      throw new HttpsError("permission-denied", "berean-opt-in-required");
    }

    // ── Step 2: Public user fields ───────────────────────────────────────────
    // Only the explicitly-listed fields are forwarded to the caller.
    const displayName: string = userData.displayName ?? userData.username ?? "Unknown";
    const bio: string | null = profile.bio ?? null;
    const roleFlags: Record<string, unknown> = profile.roleFlags ?? {};
    const links: unknown[] = profile.links ?? [];
    const pinSlots: string[] = Array.isArray(profile.pinSlots) ? profile.pinSlots : [];

    // Suppress links from the returned payload (not in the contract), but read
    // churchId from roleFlags for the church lookup below.
    void links; // acknowledged — not returned per contract

    // ── Step 3: Recent public posts ──────────────────────────────────────────
    // Query posts where authorId == userId AND privacy == "public".
    // A missing privacy field is treated as NOT public (safe default).
    let recentPublicPosts: PublicPostPreview[] = [];
    try {
      const postsSnap = await db
        .collection("posts")
        .where("authorId", "==", userId)
        .where("privacy", "==", "public")
        .orderBy("createdAt", "desc")
        .limit(10)
        .get();

      recentPublicPosts = postsSnap.docs
        .filter((doc) => {
          // Double-check: exclude any doc that has isPrivate: true as an extra
          // guard in case the privacy field is inconsistently set.
          const d = doc.data();
          return d.isPrivate !== true && d.privacy === "public";
        })
        .map((doc) => {
          const d = doc.data();
          const raw: string = typeof d.content === "string" ? d.content : "";
          return {
            id: doc.id,
            content: raw.slice(0, 500),
            type: typeof d.type === "string" ? d.type : "post",
            createdAt:
              d.createdAt?.toDate?.()?.toISOString?.() ??
              new Date().toISOString(),
          };
        });
    } catch {
      // Non-fatal — return empty array if posts query fails (e.g., index not ready)
      recentPublicPosts = [];
    }

    // ── Step 4: Pinned post previews ─────────────────────────────────────────
    // Fetch each pin slot doc. Skip any that are missing or not public.
    let pinnedPosts: PinnedPostPreview[] = [];
    if (pinSlots.length > 0) {
      const pinnedFetches = pinSlots.slice(0, 6).map(async (postId) => {
        try {
          const snap = await db.collection("posts").doc(postId).get();
          if (!snap.exists) return null;
          const d = snap.data() ?? {};
          // Only return the post if it is publicly readable.
          if (d.privacy !== "public" || d.isPrivate === true) return null;
          const raw: string = typeof d.content === "string" ? d.content : "";
          return {
            id: snap.id,
            content: raw.slice(0, 500),
            type: typeof d.type === "string" ? d.type : "post",
          } satisfies PinnedPostPreview;
        } catch {
          return null;
        }
      });

      const results = await Promise.all(pinnedFetches);
      pinnedPosts = results.filter((r): r is PinnedPostPreview => r !== null);
    }

    // ── Step 5: Church info ──────────────────────────────────────────────────
    let churchInfo: ChurchInfo | null = null;
    const churchId =
      typeof roleFlags.churchId === "string" ? roleFlags.churchId : undefined;

    if (churchId) {
      try {
        const churchSnap = await db.collection("churches").doc(churchId).get();
        if (churchSnap.exists) {
          const c = churchSnap.data() ?? {};
          churchInfo = {
            name: typeof c.name === "string" ? c.name : "",
            location: typeof c.location === "string"
              ? c.location
              : typeof c.city === "string"
                ? c.city
                : "",
          };
        }
      } catch {
        // Non-fatal — church info is supplementary
        churchInfo = null;
      }
    }

    // ── Return ───────────────────────────────────────────────────────────────
    return {
      displayName,
      bio,
      roleFlags,
      recentPublicPosts,
      pinnedPosts,
      churchInfo,
    };
  }
);

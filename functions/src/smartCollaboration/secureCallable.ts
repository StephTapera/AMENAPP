// secureCallable.ts
// AMEN Smart Collaboration Layer — Secure Callable Wrapper
//
// Every Phase 1 smart collaboration callable MUST use withSecureSmartCallable().
// This wrapper enforces:
//   1. Firebase Auth (unauthenticated → rejected)
//   2. App Check (absent/invalid → rejected)
//   3. Server-side membership verification — never trusts client-supplied member lists
//   4. Rate limiting — max 20 calls per minute per user
//
// Error codes returned:
//   "unauthenticated"  — no auth token
//   "permission-denied" — not a member of the requested thread
//   "resource-exhausted" — rate limit exceeded (maps to rate-limited UX)
//   "not-found"        — thread or space/channel document does not exist

import { HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import type { SmartCallableRequest } from "./contracts";

// MARK: - Rate Limit Constants

const RATE_LIMIT_MAX_CALLS = 20;
const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
const RATE_LIMIT_DOC_PATH = (uid: string) =>
  `users/${uid}/rateLimits/smartCollab`;

// MARK: - withSecureSmartCallable

/**
 * Wraps a smart collaboration handler with full security enforcement.
 *
 * Usage:
 *   export const myCallable = onCall(
 *     { enforceAppCheck: true },
 *     async (request) => withSecureSmartCallable(request, async (uid, data, db) => { ... })
 *   );
 *
 * The handler receives:
 *   uid  — verified Firebase Auth UID of the caller
 *   data — validated request payload
 *   db   — Firestore instance (passed in to keep the handler testable)
 */
export async function withSecureSmartCallable<
  TReq extends SmartCallableRequest,
  TRes
>(
  request: CallableRequest<TReq>,
  handler: (
    uid: string,
    data: TReq,
    db: FirebaseFirestore.Firestore
  ) => Promise<TRes>
): Promise<TRes> {
  const db = getFirestore();

  // 1. Authentication check
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError(
      "unauthenticated",
      "You must be signed in to use smart collaboration features."
    );
  }

  // 2. App Check enforcement
  // Note: when enforceAppCheck: true is set on the callable declaration,
  // Firebase rejects the request before the handler runs. This secondary
  // check guards against wrappers that forget the declaration-level flag.
  if (request.app == null) {
    throw new HttpsError(
      "unauthenticated",
      "App Check is required for smart collaboration features."
    );
  }

  const data = request.data;

  // 3. Input validation
  if (!data.threadId || !data.threadType) {
    throw new HttpsError(
      "invalid-argument",
      "threadId and threadType are required."
    );
  }
  if (data.threadType === "channel") {
    if (!data.spaceId || !data.channelId) {
      throw new HttpsError(
        "invalid-argument",
        "spaceId and channelId are required for channel thread type."
      );
    }
  }

  // 4. Server-side membership verification
  // NEVER trust a client-supplied member list — always read from Firestore.
  await verifyMembership(uid, data, db);

  // 5. Rate limiting — max RATE_LIMIT_MAX_CALLS per RATE_LIMIT_WINDOW_MS per user
  await enforceRateLimit(uid, db);

  // 6. Delegate to the feature handler
  return handler(uid, data, db);
}

// MARK: - Membership Verification

async function verifyMembership(
  uid: string,
  data: SmartCallableRequest,
  db: FirebaseFirestore.Firestore
): Promise<void> {
  try {
    if (data.threadType === "dm") {
      // DM: check conversations/{threadId}.participants array
      const convRef = db.collection("conversations").doc(data.threadId);
      const convSnap = await convRef.get();

      if (!convSnap.exists) {
        throw new HttpsError(
          "not-found",
          "Conversation not found."
        );
      }

      const convData = convSnap.data();
      const participants: string[] = convData?.participants ?? [];
      if (!participants.includes(uid)) {
        throw new HttpsError(
          "permission-denied",
          "You are not a participant in this conversation."
        );
      }
    } else if (data.threadType === "channel") {
      // Channel: check spaces/{spaceId}/channels/{channelId}.members
      // and spaces/{spaceId}/members/{uid} as fallback
      const spaceId = data.spaceId!;
      const channelId = data.channelId!;

      const channelRef = db
        .collection("spaces")
        .doc(spaceId)
        .collection("channels")
        .doc(channelId);
      const channelSnap = await channelRef.get();

      if (!channelSnap.exists) {
        throw new HttpsError(
          "not-found",
          "Channel not found."
        );
      }

      // Primary check: space-level membership document
      const spaceMemberRef = db
        .collection("spaces")
        .doc(spaceId)
        .collection("members")
        .doc(uid);
      const spaceMemberSnap = await spaceMemberRef.get();

      if (!spaceMemberSnap.exists) {
        // Secondary check: channel-level participants list
        const channelData = channelSnap.data();
        const participants: string[] = channelData?.participants ?? [];
        if (!participants.includes(uid)) {
          throw new HttpsError(
            "permission-denied",
            "You are not a member of this space or channel."
          );
        }
      }
    } else if (data.threadType === "discussion") {
      // Discussion: check discussions/{threadId}.participantIds
      const discussionRef = db
        .collection("discussions")
        .doc(data.threadId);
      const discussionSnap = await discussionRef.get();

      if (!discussionSnap.exists) {
        throw new HttpsError(
          "not-found",
          "Discussion not found."
        );
      }

      const discussionData = discussionSnap.data();
      const participantIds: string[] = discussionData?.participantIds ?? [];
      if (!participantIds.includes(uid)) {
        throw new HttpsError(
          "permission-denied",
          "You are not a participant in this discussion."
        );
      }
    } else {
      throw new HttpsError(
        "invalid-argument",
        "Unknown threadType."
      );
    }
  } catch (err) {
    // Re-throw HttpsErrors directly; wrap unexpected Firestore errors.
    if (err instanceof HttpsError) throw err;
    throw new HttpsError(
      "internal",
      "Membership verification failed."
    );
  }
}

// MARK: - Rate Limiting

async function enforceRateLimit(
  uid: string,
  db: FirebaseFirestore.Firestore
): Promise<void> {
  const rateLimitRef = db.doc(RATE_LIMIT_DOC_PATH(uid));
  const now = Date.now();

  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(rateLimitRef);

      if (!snap.exists) {
        // First call — initialize the window.
        tx.set(rateLimitRef, {
          callCount: 1,
          windowStartMs: now,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return;
      }

      const existing = snap.data()!;
      const windowStartMs: number = existing.windowStartMs ?? now;
      const callCount: number = existing.callCount ?? 0;
      const windowAgeMs = now - windowStartMs;

      if (windowAgeMs > RATE_LIMIT_WINDOW_MS) {
        // Window has expired — reset the counter.
        tx.set(rateLimitRef, {
          callCount: 1,
          windowStartMs: now,
          updatedAt: FieldValue.serverTimestamp(),
        });
      } else if (callCount >= RATE_LIMIT_MAX_CALLS) {
        // Within the window and over the limit.
        throw new HttpsError(
          "resource-exhausted",
          "Smart collaboration rate limit reached. Please wait before retrying."
        );
      } else {
        // Within window and under the limit — increment.
        tx.update(rateLimitRef, {
          callCount: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    // If the rate-limit write fails (e.g. Firestore outage), fail open
    // rather than blocking all users — log and continue.
    console.error("[SmartCollab] Rate limit Firestore write failed:", err);
  }
}

// callables.ts — Context Engine callable Cloud Functions (Wave 1: Lane A)
//
// Three callables:
//   contextEngine_getGrants   — Auth required (no App Check — must work in settings UI)
//   contextEngine_setGrant    — Auth required + App Check enforced
//   contextEngine_getAuditLog — Auth required (no App Check — must work in settings UI)

import * as functions from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import {
  ContextSource,
  ContextPolicy,
  ContextGrantWire,
  GetGrantsResponse,
  SetGrantRequest,
  SetGrantResponse,
  GetAuditLogRequest,
  GetAuditLogResponse,
  ContextAuditEntry,
} from "../capabilities/types";

// All valid ContextSource values
const VALID_SOURCES: ContextSource[] = [
  "calendar",
  "location",
  "contacts",
  "prayerHistory",
  "readingHistory",
  "notesContent",
  "messagesMeta",
  "churchProfile",
];

// All valid ContextPolicy values
const VALID_POLICIES: ContextPolicy[] = ["never", "askEveryTime", "whileUsing", "always"];

function isValidSource(s: unknown): s is ContextSource {
  return VALID_SOURCES.includes(s as ContextSource);
}

function isValidPolicy(p: unknown): p is ContextPolicy {
  return VALID_POLICIES.includes(p as ContextPolicy);
}

// ── contextEngine_getGrants ───────────────────────────────────────────────────
// Returns all 8 current grant states for the authenticated user.
// Missing sources are returned with policy "never" and version 0.
// App Check is required for authenticated context grants.

export const contextEngine_getGrants = functions.onCall(
  { enforceAppCheck: true },
  async (request): Promise<GetGrantsResponse> => {
    if (!request.auth) {
      throw new functions.HttpsError("unauthenticated", "Authentication required");
    }

    const uid = request.auth.uid;
    const db = getFirestore();

    logger.info("[contextEngine] getGrants", { uid });

    // Fetch all docs from the contextGrants subcollection
    const grantsSnap = await db
      .collection(`users/${uid}/contextGrants`)
      .get();

    // Build a map of source → doc data
    const grantMap = new Map<ContextSource, ContextGrantWire>();
    for (const doc of grantsSnap.docs) {
      const data = doc.data();
      const source = doc.id as ContextSource;
      if (!isValidSource(source)) continue;
      grantMap.set(source, {
        source,
        policy: data.policy ?? "never",
        grantedAt: data.grantedAt?.toDate?.()?.toISOString?.() ?? new Date(0).toISOString(),
        updatedAt: data.updatedAt?.toDate?.()?.toISOString?.() ?? new Date(0).toISOString(),
        version: data.version ?? 0,
      });
    }

    // Fill in all 8 sources — missing ones default to "never", version 0
    const epoch = new Date(0).toISOString();
    const grants: ContextGrantWire[] = VALID_SOURCES.map((source) => {
      return grantMap.get(source) ?? {
        source,
        policy: "never",
        grantedAt: epoch,
        updatedAt: epoch,
        version: 0,
      };
    });

    return { grants };
  }
);

// ── contextEngine_setGrant ────────────────────────────────────────────────────
// Upserts a context grant. Increments version atomically.
// App Check enforced.

export const contextEngine_setGrant = functions.onCall(
  { enforceAppCheck: true },
  async (request): Promise<SetGrantResponse> => {
    if (!request.auth) {
      throw new functions.HttpsError("unauthenticated", "Authentication required");
    }

    const uid = request.auth.uid;
    const body = request.data as Partial<SetGrantRequest>;

    if (!isValidSource(body.source)) {
      throw new functions.HttpsError(
        "invalid-argument",
        `source must be one of: ${VALID_SOURCES.join(", ")}`
      );
    }
    if (!isValidPolicy(body.policy)) {
      throw new functions.HttpsError(
        "invalid-argument",
        `policy must be one of: ${VALID_POLICIES.join(", ")}`
      );
    }

    const source: ContextSource = body.source;
    const policy: ContextPolicy = body.policy;
    const db = getFirestore();
    const grantRef = db.doc(`users/${uid}/contextGrants/${source}`);
    const now = new Date();

    logger.info("[contextEngine] setGrant", { uid, source, policy });

    await grantRef.set(
      {
        source,
        policy,
        updatedAt: now,
        version: FieldValue.increment(1),
        // Only set grantedAt on first write; merge preserves existing value
        grantedAt: now,
      },
      { merge: true }
    );

    // Read back to get the final version number
    const snap = await grantRef.get();
    const data = snap.data()!;

    return {
      source,
      policy,
      version: data.version as number,
      updatedAt: now.toISOString(),
    };
  }
);

// ── contextEngine_getAuditLog ─────────────────────────────────────────────────
// Paginated audit log for the authenticated user only.
// App Check is required for authenticated settings audit reads.

export const contextEngine_getAuditLog = functions.onCall(
  { enforceAppCheck: true },
  async (request): Promise<GetAuditLogResponse> => {
    if (!request.auth) {
      throw new functions.HttpsError("unauthenticated", "Authentication required");
    }

    const uid = request.auth.uid;
    const body = (request.data ?? {}) as GetAuditLogRequest;
    const db = getFirestore();

    // Clamp pageSize: default 20, max 50
    const rawPageSize = typeof body.pageSize === "number" ? body.pageSize : 20;
    const pageSize = Math.min(Math.max(1, rawPageSize), 50);
    const startAfter = typeof body.startAfter === "string" ? body.startAfter : undefined;

    logger.info("[contextEngine] getAuditLog", { uid, pageSize, startAfter });

    let query = db
      .collection(`users/${uid}/contextAuditLog`)
      .orderBy("at", "desc")
      .limit(pageSize);

    if (startAfter) {
      const cursorSnap = await db
        .doc(`users/${uid}/contextAuditLog/${startAfter}`)
        .get();
      if (cursorSnap.exists) {
        query = query.startAfter(cursorSnap);
      }
    }

    const snap = await query.get();

    const entries: ContextAuditEntry[] = snap.docs.map((doc) => {
      const d = doc.data();
      return {
        source: d.source as ContextSource,
        capabilityId: d.capabilityId as string,
        decision: d.decision as "allowed" | "denied" | "promptRequired",
        requestId: d.requestId as string,
        at: d.at as string,
      };
    });

    // nextCursor is the last doc's ID only if the page is full
    const nextCursor =
      snap.docs.length === pageSize
        ? snap.docs[snap.docs.length - 1].id
        : undefined;

    return { entries, nextCursor };
  }
);

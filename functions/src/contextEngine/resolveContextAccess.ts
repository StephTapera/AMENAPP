// resolveContextAccess.ts — Context Engine internal policy resolver (Wave 1: Lane A)
//
// Non-callable module. Called by other server-side functions to gate Capability access.
// Writes one contextAuditLog entry per source per call. Never throws on audit failure.

import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { randomUUID } from "crypto";
import {
  ContextSource,
  ContextPolicy,
  ContextDecision,
  ResolveAccessInput,
  ResolveAccessOutput,
} from "../capabilities/types";

// Device-level sources that are not yet supported server-side
const DEVICE_LEVEL_SOURCES: ReadonlySet<ContextSource> = new Set(["calendar", "location"]);

// All valid ContextSource values for default-filling missing grants
const ALL_SOURCES: ContextSource[] = [
  "calendar",
  "location",
  "contacts",
  "prayerHistory",
  "readingHistory",
  "notesContent",
  "messagesMeta",
  "churchProfile",
];

interface GrantDoc {
  source: ContextSource;
  policy: ContextPolicy;
  grantedAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
  version: number;
}

function resolveDecision(
  source: ContextSource,
  policy: ContextPolicy,
  invocationType: "foreground" | "background",
  requestId: string
): ContextDecision {
  // Device-level sources: always denied regardless of stored policy
  if (DEVICE_LEVEL_SOURCES.has(source)) {
    return { source, decision: "denied", reason: "notYetSupported", requestId };
  }

  switch (policy) {
    case "always":
      return { source, decision: "allowed", requestId };

    case "whileUsing":
      if (invocationType === "foreground") {
        return { source, decision: "allowed", requestId };
      }
      return { source, decision: "denied", reason: "backgroundDenied", requestId };

    case "askEveryTime":
      return { source, decision: "promptRequired", requestId };

    case "never":
    default:
      return { source, decision: "denied", reason: "notGranted", requestId };
  }
}

export async function resolveContextAccess(
  input: ResolveAccessInput
): Promise<ResolveAccessOutput> {
  const { uid, capabilityId, sources, invocationType } = input;
  const db = getFirestore();
  const requestId = randomUUID();

  // Fetch all grant docs in parallel
  const grantRefs = sources.map((source) =>
    db.doc(`users/${uid}/contextGrants/${source}`)
  );

  const grantSnaps = await Promise.all(grantRefs.map((ref) => ref.get()));

  const decisions: ContextDecision[] = grantSnaps.map((snap, i) => {
    const source = sources[i];
    // Missing grant → policy defaults to "never"
    const policy: ContextPolicy = snap.exists
      ? (snap.data() as GrantDoc).policy
      : "never";
    return resolveDecision(source, policy, invocationType, requestId);
  });

  const allAllowed = decisions.every((d) => d.decision === "allowed");

  // Write audit log entries — one per source — using a batch write.
  // Failures are caught and logged; never re-thrown.
  try {
    const now = new Date();
    const batch = db.batch();
    for (const decision of decisions) {
      const logRef = db
        .collection(`users/${uid}/contextAuditLog`)
        .doc(); // auto-ID
      batch.set(logRef, {
        source: decision.source,
        capabilityId,
        decision: decision.decision,
        requestId,
        at: now.toISOString(),
      });
    }
    await batch.commit();
  } catch (auditErr) {
    logger.error("[contextEngine] audit log write failed — non-fatal", {
      uid,
      capabilityId,
      requestId,
      error: String(auditErr),
    });
  }

  return { decisions, allAllowed };
}

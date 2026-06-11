/**
 * one_relayMoment — Stage-3 CF deploy item (FLAG-FLIP PREREQUISITE)
 *
 * Enforces forwardAllowed=false rejection server-side as the second defense
 * layer for sticky-consent (SECURITY.md §8.3). Client-side enforcement is live
 * (audit H-1, 2026-06-10) but advisory only; this CF is the authoritative gate
 * and MUST deploy before any one_* feature flag is flipped on.
 *
 * Contract: CONTRACTS.md §15 + §5 + §8
 * Deploy: firebase deploy --only functions:one_relayMoment --project amen-5e359
 */

import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = () => admin.firestore();

interface RelayMomentData {
  momentID: string;
  toUIDs?: string[];
}

export const one_relayMoment = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError("unauthenticated", "Auth required");
    }
    const uid = request.auth.uid;
    const data = request.data as RelayMomentData;
    if (!data?.momentID || typeof data.momentID !== "string") {
      throw new functions.HttpsError("invalid-argument", "momentID required");
    }

    // Authoritative consent gate — enforces forwardAllowed server-side
    // (the client-side guard in ONEFeedModeService.relay is the first layer;
    // this CF is the second, non-bypassable layer per SECURITY.md §8.3).
    const momentRef = db().collection("one_moments").doc(data.momentID);
    const snap = await momentRef.get();
    if (!snap.exists) {
      throw new functions.HttpsError("not-found", "Moment not found");
    }
    const moment = snap.data() as Record<string, unknown>;

    const consentDNA = moment["consentDNA"] as Record<string, unknown> | undefined;
    const perms = consentDNA?.["permissions"] as Record<string, unknown> | undefined;
    if (perms?.["forwardAllowed"] === false) {
      throw new functions.HttpsError(
        "permission-denied",
        "The author disabled forwarding for this moment."
      );
    }

    // Reach budget gate (CONTRACTS.md §8; hard cap default 5)
    const budget = moment["reachBudget"] as Record<string, unknown> | undefined;
    const chainDepth = (budget?.["chainDepth"] as number) ?? 0;
    const maxDepth = (budget?.["maxChainDepth"] as number) ?? 5;
    const shares = (budget?.["sharesRemaining"] as number) ?? 0;
    if (chainDepth >= maxDepth) {
      throw new functions.HttpsError("resource-exhausted", "Maximum relay depth reached.");
    }
    if (shares <= 0) {
      throw new functions.HttpsError("resource-exhausted", "No relay shares remaining.");
    }

    // TODO(Stage-3): apply mergedConsentDNA (stricter-of-source/relay) before writing
    // the forwarded copy — see SECURITY.md §8.3 full logic spec.

    // Atomic relay write. /one_reach/ is CF-only per CONTRACTS.md §17 rule 5.
    await momentRef.update({
      "reachBudget.sharesRemaining": shares - 1,
      "reachBudget.totalRelays": admin.firestore.FieldValue.increment(1),
      "reachBudget.chainDepth": chainDepth + 1,
      relayedBy: admin.firestore.FieldValue.arrayUnion(uid),
      lastRelayedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { sharesRemaining: shares - 1 };
  }
);

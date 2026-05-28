// integrations/integrationCallableGuards.ts
// Shared guards for callable function entry points

import * as admin from "firebase-admin";
import { AmenIntegrationError } from "./integrationErrors";
import type { AmenIntegrationProvider } from "./types";

const db = admin.firestore();

// Validate feature flag from Firestore-backed Remote Config cache
// In production, use Firebase Remote Config SDK. This guard reads a Firestore
// mirror updated by a scheduled function — avoids SDK overhead per-call.
export async function assertFeatureEnabled(flagName: string): Promise<void> {
  try {
    const snap = await db.collection("remoteConfigCache").doc(flagName).get();
    if (snap.exists && snap.data()?.["value"] === false) {
      throw new AmenIntegrationError("feature-disabled");
    }
  } catch (e) {
    if (e instanceof AmenIntegrationError) throw e;
    // If flag lookup fails, fail open (feature enabled) to avoid false blocks
    // This matches AMEN's existing flag strategy
  }
}

// Fetch a connected integration account for the given user + provider.
// Throws if not connected or expired.
export async function assertProviderConnected(
  uid: string,
  provider: AmenIntegrationProvider
): Promise<admin.firestore.DocumentSnapshot> {
  const accountId = `${uid}_${provider}`;
  const snap = await db.collection("integrationAccounts").doc(accountId).get();
  if (!snap.exists) throw new AmenIntegrationError("provider-not-connected");
  const status = snap.data()?.["status"] as string;
  if (status === "expired") throw new AmenIntegrationError("provider-expired");
  if (status === "revoked") throw new AmenIntegrationError("provider-not-connected");
  if (status !== "connected") throw new AmenIntegrationError("provider-not-connected");
  return snap;
}

// Fetch the encrypted token record for a connected account.
// Never returns this to the client.
export async function fetchTokenRecord(accountId: string) {
  const snap = await db.collection("integrationTokens").doc(accountId).get();
  if (!snap.exists) throw new AmenIntegrationError("provider-not-connected");
  return snap.data() as import("./types").AmenIntegrationTokenRecord;
}

// Validate that a gathering exists and the caller is the host
export async function assertGatheringHost(uid: string, gatheringId: string) {
  const snap = await db.collection("gatherings").doc(gatheringId).get();
  if (!snap.exists) throw new AmenIntegrationError("gathering-not-found");
  if (snap.data()?.["createdByUid"] !== uid) throw new AmenIntegrationError("permission-denied");
  return snap;
}

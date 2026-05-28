// integrations/oauth/oauthState.ts
// OAuth state document management — one-time-use, 10-minute TTL
// CSRF protection: state token is cryptographically random, bound to uid

import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { AmenIntegrationError } from "../integrationErrors";
import type { AmenOAuthState, AmenIntegrationProvider } from "../types";

const db = admin.firestore();
const STATE_TTL_MS = 10 * 60 * 1000; // 10 minutes

export function generateStateToken(): string {
  return crypto.randomBytes(32).toString("hex");
}

export function generateCodeVerifier(): string {
  return crypto.randomBytes(32).toString("base64url");
}

export function computeCodeChallenge(verifier: string): string {
  return crypto.createHash("sha256").update(verifier).digest("base64url");
}

export async function createOAuthState(
  uid: string,
  provider: AmenIntegrationProvider,
  redirectUri: string,
  usePKCE = false
): Promise<{ stateToken: string; codeVerifier?: string; codeChallenge?: string }> {
  const stateToken = generateStateToken();
  const now = Date.now();

  const state: AmenOAuthState = {
    stateToken,
    uid,
    provider,
    redirectUri,
    createdAt: admin.firestore.Timestamp.fromMillis(now),
    expiresAt: admin.firestore.Timestamp.fromMillis(now + STATE_TTL_MS),
    consumed: false,
  };

  let codeVerifier: string | undefined;
  let codeChallenge: string | undefined;

  if (usePKCE) {
    codeVerifier = generateCodeVerifier();
    codeChallenge = computeCodeChallenge(codeVerifier);
    state.codeVerifier = codeVerifier;
  }

  await db.collection("oauthStates").doc(stateToken).set(state);
  return { stateToken, codeVerifier, codeChallenge };
}

// Validates and atomically consumes the state. Throws on expired, consumed, or user mismatch.
export async function consumeOAuthState(
  stateToken: string,
  expectedUid: string
): Promise<AmenOAuthState> {
  const ref = db.collection("oauthStates").doc(stateToken);
  let stateData: AmenOAuthState | undefined;

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new AmenIntegrationError("oauth-state-invalid");

    const s = snap.data() as AmenOAuthState;
    if (s.consumed) throw new AmenIntegrationError("oauth-state-consumed");
    if (s.expiresAt.toMillis() < Date.now()) throw new AmenIntegrationError("oauth-state-expired");
    if (s.uid !== expectedUid) throw new AmenIntegrationError("oauth-state-invalid");

    tx.update(ref, { consumed: true });
    stateData = s;
  });

  if (!stateData) throw new AmenIntegrationError("oauth-state-invalid");
  return stateData;
}

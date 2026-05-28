// accessPassToken.ts — Cryptographic token generation and verification
//
// Raw token lives only in QR/NFC/share URL.
// Only tokenHash is stored in Firestore.
// Token version prevents replay after rotation.

import * as crypto from "crypto";

const HASH_ALGORITHM = "sha256";
const TOKEN_BYTES = 32; // 256 bits of entropy

/** Generate a cryptographically secure random token. Returns raw bytes as hex. */
export function generateRawToken(): string {
  return crypto.randomBytes(TOKEN_BYTES).toString("hex");
}

/** Hash a raw token for Firestore storage. Never store the raw token. */
export function hashToken(rawToken: string): string {
  return crypto.createHash(HASH_ALGORITHM).update(rawToken).digest("hex");
}

/** Constant-time comparison to prevent timing attacks. */
export function verifyToken(rawToken: string, storedHash: string): boolean {
  const incomingHash = hashToken(rawToken);
  if (incomingHash.length !== storedHash.length) return false;
  return crypto.timingSafeEqual(
    Buffer.from(incomingHash),
    Buffer.from(storedHash)
  );
}

/** Build the universal link for a pass. rawToken is embedded in the URL. */
export function buildUniversalLink(accessPassId: string, rawToken: string): string {
  return `https://amen.app/access/${accessPassId}?t=${rawToken}`;
}

/** Build the app deep link for a pass. */
export function buildDeepLink(accessPassId: string, rawToken: string): string {
  return `amen://access/${accessPassId}?t=${rawToken}`;
}

// integrations/oauth/oauthRefresh.ts
// Token refresh — called internally by backend; also exposed as callable for explicit refresh

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { writeAuditLog } from "../integrationAudit";
import { AmenIntegrationError, errorResponse } from "../integrationErrors";
import type { AmenIntegrationProvider, AmenIntegrationTokenRecord } from "../types";

const db = admin.firestore();

function getEncryptionKey(): Buffer {
  const hex = functions.config()["integrations"]?.["encryption_key"] as string | undefined;
  if (!hex || hex.length !== 64) throw new Error("Invalid encryption key");
  return Buffer.from(hex, "hex");
}

export function decryptToken(ciphertext: string): string {
  const key = getEncryptionKey();
  const [ivHex, encHex] = ciphertext.split(":");
  const iv = Buffer.from(ivHex, "hex");
  const enc = Buffer.from(encHex, "hex");
  const decipher = crypto.createDecipheriv("aes-256-cbc", key, iv);
  return Buffer.concat([decipher.update(enc), decipher.final()]).toString("utf8");
}

function encryptToken(plaintext: string): string {
  const key = getEncryptionKey();
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv("aes-256-cbc", key, iv);
  const enc = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  return `${iv.toString("hex")}:${enc.toString("hex")}`;
}

export async function refreshProviderToken(uid: string, provider: AmenIntegrationProvider): Promise<string> {
  const accountId = `${uid}_${provider}`;
  const snap = await db.collection("integrationTokens").doc(accountId).get();
  if (!snap.exists) throw new AmenIntegrationError("provider-not-connected");

  const record = snap.data() as AmenIntegrationTokenRecord;
  if (!record.encryptedRefreshToken) throw new AmenIntegrationError("provider-expired");

  const refreshToken = decryptToken(record.encryptedRefreshToken);
  const clientId = functions.config()["integrations"]?.[provider]?.["client_id"] as string;
  const clientSecret = functions.config()["integrations"]?.[provider]?.["client_secret"] as string;

  let newAccess: string;
  let newRefresh: string | undefined;
  let expiresIn: number;

  if (provider === "microsoft") {
    const body = new URLSearchParams({
      client_id: clientId, client_secret: clientSecret,
      refresh_token: refreshToken, grant_type: "refresh_token",
    });
    const resp = await fetch("https://login.microsoftonline.com/common/oauth2/v2.0/token", {
      method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: body.toString(),
    });
    if (!resp.ok) throw new AmenIntegrationError("provider-expired");
    const j = await resp.json() as { access_token: string; refresh_token?: string; expires_in: number };
    newAccess = j.access_token; newRefresh = j.refresh_token; expiresIn = j.expires_in;
  } else if (provider === "zoom") {
    const creds = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
    const body = new URLSearchParams({ refresh_token: refreshToken, grant_type: "refresh_token" });
    const resp = await fetch("https://zoom.us/oauth/token", {
      method: "POST",
      headers: { "Authorization": `Basic ${creds}`, "Content-Type": "application/x-www-form-urlencoded" },
      body: body.toString(),
    });
    if (!resp.ok) throw new AmenIntegrationError("provider-expired");
    const j = await resp.json() as { access_token: string; refresh_token: string; expires_in: number };
    newAccess = j.access_token; newRefresh = j.refresh_token; expiresIn = j.expires_in;
  } else {
    throw new AmenIntegrationError("provider-expired");
  }

  const newExpiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + expiresIn * 1000);
  const updates: Record<string, unknown> = {
    encryptedAccessToken: encryptToken(newAccess),
    expiresAt: newExpiresAt,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (newRefresh) updates["encryptedRefreshToken"] = encryptToken(newRefresh);

  const batch = db.batch();
  batch.update(db.collection("integrationTokens").doc(accountId), updates);
  batch.update(db.collection("integrationAccounts").doc(accountId), {
    status: "connected", expiresAt: newExpiresAt,
    "audit.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();

  await writeAuditLog({ uid, action: "token_refreshed", provider });
  return newAccess;
}

export const integrationsRefreshConnection = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return errorResponse("auth-required");

  const provider = data["provider"] as AmenIntegrationProvider | undefined;
  if (!provider) return errorResponse("invalid-input");

  try {
    await refreshProviderToken(uid, provider);
    return { success: true, provider };
  } catch (e) {
    if (e instanceof AmenIntegrationError) return errorResponse(e.code);
    console.error("[integrationsRefreshConnection]", e);
    return errorResponse("unknown");
  }
});

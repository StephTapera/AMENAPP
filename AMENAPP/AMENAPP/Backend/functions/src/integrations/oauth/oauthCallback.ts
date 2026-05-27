// integrations/oauth/oauthCallback.ts
// Completes OAuth: validates state, exchanges code, stores encrypted tokens

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { consumeOAuthState } from "./oauthState";
import { writeAuditLog } from "../integrationAudit";
import { checkRateLimit } from "../integrationRateLimits";
import { AmenIntegrationError, errorResponse } from "../integrationErrors";
import type { AmenIntegrationProvider, AmenIntegrationAccount, AmenIntegrationTokenRecord, AmenIntegrationProviderMetadata } from "../types";

const db = admin.firestore();

function encryptToken(plaintext: string, key: Buffer): string {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv("aes-256-cbc", key, iv);
  const encrypted = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  return `${iv.toString("hex")}:${encrypted.toString("hex")}`;
}

function getEncryptionKey(): Buffer {
  const hex = functions.config()["integrations"]?.["encryption_key"] as string | undefined;
  if (!hex || hex.length !== 64) throw new Error("Invalid or missing encryption key");
  return Buffer.from(hex, "hex");
}

async function exchangeCode(
  provider: AmenIntegrationProvider,
  code: string,
  redirectUri: string,
  clientId: string,
  clientSecret: string,
  codeVerifier?: string
): Promise<{ accessToken: string; refreshToken?: string; expiresIn: number; scope: string; rawJson: Record<string, unknown> }> {
  if (provider === "microsoft") {
    const body = new URLSearchParams({
      client_id: clientId, client_secret: clientSecret,
      code, redirect_uri: redirectUri, grant_type: "authorization_code",
      ...(codeVerifier ? { code_verifier: codeVerifier } : {}),
    });
    const resp = await fetch("https://login.microsoftonline.com/common/oauth2/v2.0/token", {
      method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: body.toString(),
    });
    if (!resp.ok) { const t = await resp.text(); console.error("[oauthCallback:ms]", t); throw new AmenIntegrationError("provider-error"); }
    const j = await resp.json() as { access_token: string; refresh_token?: string; expires_in: number; scope: string };
    return { accessToken: j.access_token, refreshToken: j.refresh_token, expiresIn: j.expires_in, scope: j.scope, rawJson: j as Record<string, unknown> };
  }
  if (provider === "zoom") {
    const creds = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
    const body = new URLSearchParams({ code, redirect_uri: redirectUri, grant_type: "authorization_code" });
    const resp = await fetch("https://zoom.us/oauth/token", {
      method: "POST",
      headers: { "Authorization": `Basic ${creds}`, "Content-Type": "application/x-www-form-urlencoded" },
      body: body.toString(),
    });
    if (!resp.ok) throw new AmenIntegrationError("provider-error");
    const j = await resp.json() as { access_token: string; refresh_token: string; expires_in: number; scope: string };
    return { accessToken: j.access_token, refreshToken: j.refresh_token, expiresIn: j.expires_in, scope: j.scope, rawJson: j as Record<string, unknown> };
  }
  // slack
  const body = new URLSearchParams({ code, redirect_uri: redirectUri, client_id: clientId, client_secret: clientSecret });
  const resp = await fetch("https://slack.com/api/oauth.v2.access", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: body.toString(),
  });
  if (!resp.ok) throw new AmenIntegrationError("provider-error");
  const j = await resp.json() as { ok: boolean; access_token: string; bot_user_id?: string; authed_user?: { id: string }; team?: { id: string; name: string }; error?: string };
  if (!j.ok) throw new AmenIntegrationError("provider-error");
  return { accessToken: j.access_token, expiresIn: 365 * 24 * 3600, scope: "channels:read,chat:write", rawJson: j as Record<string, unknown> };
}

async function fetchMetadata(provider: AmenIntegrationProvider, accessToken: string, rawJson: Record<string, unknown>): Promise<AmenIntegrationProviderMetadata> {
  if (provider === "microsoft") {
    try {
      const r = await fetch("https://graph.microsoft.com/v1.0/me?$select=displayName,mail,userPrincipalName,id", {
        headers: { "Authorization": `Bearer ${accessToken}` },
      });
      if (!r.ok) return {};
      const u = await r.json() as { id?: string; displayName?: string; mail?: string; userPrincipalName?: string };
      return { displayName: u.displayName, email: u.mail ?? u.userPrincipalName, microsoftUserId: u.id };
    } catch { return {}; }
  }
  if (provider === "zoom") {
    try {
      const r = await fetch("https://api.zoom.us/v2/users/me", { headers: { "Authorization": `Bearer ${accessToken}` } });
      if (!r.ok) return {};
      const u = await r.json() as { id?: string; account_id?: string; email?: string; first_name?: string; last_name?: string };
      return { email: u.email, displayName: `${u.first_name ?? ""} ${u.last_name ?? ""}`.trim(), zoomUserId: u.id, zoomAccountId: u.account_id };
    } catch { return {}; }
  }
  // slack — metadata from token response
  const j = rawJson as { bot_user_id?: string; authed_user?: { id: string }; team?: { id: string; name: string } };
  return { workspaceId: j.team?.id, workspaceName: j.team?.name, slackUserId: j.authed_user?.id, botUserId: j.bot_user_id };
}

export const integrationsCompleteOAuth = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return errorResponse("auth-required");

  const code = data["code"] as string | undefined;
  const stateToken = data["stateToken"] as string | undefined;
  if (!code || !stateToken) return errorResponse("invalid-input");

  try {
    await checkRateLimit(uid, "oauth_callback");

    const state = await consumeOAuthState(stateToken, uid);
    const provider = state.provider;

    const clientId = functions.config()["integrations"]?.[provider]?.["client_id"] as string;
    const clientSecret = functions.config()["integrations"]?.[provider]?.["client_secret"] as string;
    if (!clientId || !clientSecret) return errorResponse("provider-error");

    const key = getEncryptionKey();
    const { accessToken, refreshToken, expiresIn, scope, rawJson } = await exchangeCode(
      provider, code, state.redirectUri, clientId, clientSecret, state.codeVerifier
    );

    const metadata = await fetchMetadata(provider, accessToken, rawJson);
    const accountId = `${uid}_${provider}`;
    const now = admin.firestore.FieldValue.serverTimestamp();
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + expiresIn * 1000);
    const scopes = scope.split(/[ ,]+/).filter(Boolean);

    const tokenRecord = {
      accountId, uid, provider,
      encryptedAccessToken: encryptToken(accessToken, key),
      ...(refreshToken ? { encryptedRefreshToken: encryptToken(refreshToken, key) } : {}),
      tokenType: "Bearer", expiresAt, scopes,
      updatedAt: now,
    };

    const account = {
      accountId, uid, provider, status: "connected",
      isOrgLevel: provider === "slack",
      providerMetadata: metadata, scopes, expiresAt,
      connectedAt: now, audit: { createdAt: now, updatedAt: now },
    };

    const batch = db.batch();
    batch.set(db.collection("integrationAccounts").doc(accountId), account, { merge: true });
    batch.set(db.collection("integrationTokens").doc(accountId), tokenRecord);
    await batch.commit();

    await writeAuditLog({ uid, action: "oauth_completed", provider });
    return { success: true, provider, status: "connected", displayName: metadata.displayName, email: metadata.email };
  } catch (e) {
    await writeAuditLog({ uid, action: "oauth_failed" }).catch(() => {});
    if (e instanceof AmenIntegrationError) return errorResponse(e.code);
    console.error("[integrationsCompleteOAuth]", e);
    return errorResponse("unknown");
  }
});

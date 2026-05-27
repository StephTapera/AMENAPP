// integrations/oauth/oauthRevoke.ts
// Disconnect and revoke a provider integration

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { writeAuditLog } from "../integrationAudit";
import { AmenIntegrationError, errorResponse } from "../integrationErrors";
import { decryptToken } from "./oauthRefresh";
import type { AmenIntegrationProvider, AmenIntegrationTokenRecord } from "../types";

const db = admin.firestore();

async function bestEffortRevoke(provider: AmenIntegrationProvider, accessToken: string): Promise<void> {
  try {
    if (provider === "zoom") {
      await fetch(`https://zoom.us/oauth/revoke?token=${encodeURIComponent(accessToken)}`, {
        method: "POST", headers: { "Authorization": `Bearer ${accessToken}` },
      });
    } else if (provider === "slack") {
      await fetch("https://slack.com/api/auth.revoke", {
        method: "POST",
        headers: { "Authorization": `Bearer ${accessToken}`, "Content-Type": "application/x-www-form-urlencoded" },
      });
    }
    // Microsoft: no per-token revocation endpoint; local revocation only
  } catch {
    // Best-effort — local revocation always proceeds
  }
}

export const integrationsDisconnectProvider = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return errorResponse("auth-required");

  const provider = data["provider"] as AmenIntegrationProvider | undefined;
  if (!provider || !["microsoft", "zoom", "slack"].includes(provider)) {
    return errorResponse("invalid-input");
  }

  try {
    const accountId = `${uid}_${provider}`;
    const tokenSnap = await db.collection("integrationTokens").doc(accountId).get();

    if (tokenSnap.exists) {
      const record = tokenSnap.data() as AmenIntegrationTokenRecord;
      try {
        const access = decryptToken(record.encryptedAccessToken);
        await bestEffortRevoke(provider, access);
      } catch { /* best-effort */ }
    }

    const batch = db.batch();
    batch.update(db.collection("integrationAccounts").doc(accountId), {
      status: "revoked",
      "audit.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
    });
    batch.delete(db.collection("integrationTokens").doc(accountId));
    await batch.commit();

    await writeAuditLog({ uid, action: "connection_revoked", provider });
    return { success: true, provider };
  } catch (e) {
    if (e instanceof AmenIntegrationError) return errorResponse(e.code);
    console.error("[integrationsDisconnectProvider]", e);
    return errorResponse("unknown");
  }
});

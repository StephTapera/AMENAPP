// integrations/oauth/oauthStart.ts
// Initiates OAuth flow — returns authorization URL to client
// Client opens URL in ASWebAuthenticationSession (never WKWebView)

import * as functions from "firebase-functions";
import { createOAuthState } from "./oauthState";
import { checkRateLimit } from "../integrationRateLimits";
import { writeAuditLog } from "../integrationAudit";
import { AmenIntegrationError, errorResponse } from "../integrationErrors";
import type { AmenIntegrationProvider } from "../types";

const PROVIDER_SCOPES: Record<AmenIntegrationProvider, string[]> = {
  microsoft: [
    "openid", "profile", "email", "offline_access",
    "Calendars.ReadWrite", "OnlineMeetings.ReadWrite",
  ],
  zoom: ["meeting:write:admin", "user:read:admin"],
  slack: ["channels:read", "chat:write", "incoming-webhook"],
};

function buildAuthUrl(
  provider: AmenIntegrationProvider,
  clientId: string,
  redirectUri: string,
  state: string,
  scopes: string[],
  codeChallenge?: string
): string {
  if (provider === "microsoft") {
    const p = new URLSearchParams({
      client_id: clientId,
      response_type: "code",
      redirect_uri: redirectUri,
      scope: scopes.join(" "),
      state,
      response_mode: "query",
      ...(codeChallenge ? { code_challenge: codeChallenge, code_challenge_method: "S256" } : {}),
    });
    return `https://login.microsoftonline.com/common/oauth2/v2.0/authorize?${p.toString()}`;
  }
  if (provider === "zoom") {
    const p = new URLSearchParams({ client_id: clientId, response_type: "code", redirect_uri: redirectUri, state });
    return `https://zoom.us/oauth/authorize?${p.toString()}`;
  }
  // slack
  const p = new URLSearchParams({ client_id: clientId, redirect_uri: redirectUri, state, scope: scopes.join(",") });
  return `https://slack.com/oauth/v2/authorize?${p.toString()}`;
}

export const integrationsStartOAuth = functions.https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) return errorResponse("auth-required");

  const provider = data["provider"] as AmenIntegrationProvider | undefined;
  if (!provider || !["microsoft", "zoom", "slack"].includes(provider)) {
    return errorResponse("invalid-input");
  }

  try {
    await checkRateLimit(uid, "oauth_start", provider);

    const clientId = functions.config()["integrations"]?.[provider]?.["client_id"] as string | undefined;
    const redirectUri = functions.config()["integrations"]?.[provider]?.["redirect_uri"] as string | undefined;
    if (!clientId || !redirectUri) {
      console.error(`[integrationsStartOAuth] Missing config for ${provider}`);
      return errorResponse("provider-error");
    }

    const usePKCE = provider === "microsoft";
    const { stateToken, codeChallenge } = await createOAuthState(uid, provider, redirectUri, usePKCE);
    const authUrl = buildAuthUrl(provider, clientId, redirectUri, stateToken, PROVIDER_SCOPES[provider], codeChallenge);

    await writeAuditLog({ uid, action: "oauth_started", provider });
    return { authUrl, stateToken };
  } catch (e) {
    if (e instanceof AmenIntegrationError) return errorResponse(e.code);
    console.error("[integrationsStartOAuth]", e);
    return errorResponse("unknown");
  }
});

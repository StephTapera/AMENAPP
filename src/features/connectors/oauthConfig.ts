/**
 * oauthConfig.ts — public OAuth authorization parameters per NEW connector.
 * OWNER: Connectors Hub (Connected Intelligence v1) — native OAuth bridge lane.
 *
 * WHY THIS FILE EXISTS
 *   The native bridge (ConnectorOAuthBridge.swift) needs the provider's
 *   *authorization* endpoint, the PUBLIC client_id, the requested OAuth scopes,
 *   and the app redirect URI to present ASWebAuthenticationSession. None of that
 *   is a secret: the OAuth `client_secret` lives ONLY in Cloud Functions
 *   (connectorFunctions.js → defineSecret). Provider names + endpoints are kept
 *   in this adapter-layer config so they never leak into any view component.
 *
 * SECURITY
 *   - client_id is a PUBLIC OAuth identifier (it appears in the auth URL the user
 *     sees). It is NOT the client_secret. The secret never touches the client.
 *   - PKCE is REQUIRED for both providers (usePKCE: true) — the bridge generates a
 *     fresh code_verifier per attempt, stores it in the Keychain (never JS), and
 *     sends ONLY the code_challenge in the auth URL. The verifier travels to the
 *     CF (connectorOAuthExchange) so the token exchange completes server-side.
 *   - redirectUri uses the app's already-registered `amenapp` URL scheme
 *     (Info.plist CFBundleURLSchemes) so ASWebAuthenticationSession can capture
 *     the callback.
 *
 * NOTE: client_id values are environment config. They are intentionally read from
 * a build-time/remote config injection point (CONNECTOR_OAUTH_CLIENT_IDS) rather
 * than hard-coded, so staging/prod can differ without a code change. If unset, the
 * bridge fails closed (see oauthBridge.ts) — never a fake success.
 */

import { ConnectorId } from '../connectedIntelligence.contracts';

/** App-registered custom scheme used as the OAuth redirect target. */
export const OAUTH_REDIRECT_SCHEME = 'amenapp';
/** Full redirect URI handed to the provider + echoed to connectorOAuthExchange. */
export const OAUTH_REDIRECT_URI = `${OAUTH_REDIRECT_SCHEME}://oauth/connector`;

/** Public OAuth parameters required to PRESENT the provider's consent screen. */
export interface ConnectorOAuthParams {
  /** Provider authorization endpoint (NOT the token endpoint — that's server-side). */
  authorizationEndpoint: string;
  /** PUBLIC OAuth client id. Never the secret. */
  clientId: string;
  /** Space-delimited provider scopes requested at the consent screen. */
  scope: string;
  /** PKCE is mandatory for these public-client flows. */
  usePKCE: true;
  /** Extra static query params some providers require (e.g. access_type). */
  extraAuthParams?: Record<string, string>;
}

/**
 * Public client ids are injected at build/remote-config time and read here.
 * `globalThis.CONNECTOR_OAUTH_CLIENT_IDS` is the single injection seam; if a
 * provider's id is missing the bridge surfaces a configuration error rather than
 * attempting a broken flow.
 */
function publicClientId(connectorId: ConnectorId): string {
  const ids =
    (globalThis as { CONNECTOR_OAUTH_CLIENT_IDS?: Record<string, string> })
      .CONNECTOR_OAUTH_CLIENT_IDS ?? {};
  return ids[connectorId] ?? '';
}

/** ONLY the NEW providers (calendar, music) have an OAuth authorization flow. */
export function getConnectorOAuthParams(
  connectorId: ConnectorId,
): ConnectorOAuthParams | null {
  switch (connectorId) {
    case ConnectorId.calendar:
      // Google Calendar — read-only scope at v1 (metadata/content read).
      return {
        authorizationEndpoint: 'https://accounts.google.com/o/oauth2/v2/auth',
        clientId: publicClientId(ConnectorId.calendar),
        scope: 'https://www.googleapis.com/auth/calendar.readonly',
        usePKCE: true,
        extraAuthParams: { access_type: 'offline', prompt: 'consent' },
      };
    case ConnectorId.music:
      // Spotify — read-only library/recently-played at v1.
      return {
        authorizationEndpoint: 'https://accounts.spotify.com/authorize',
        clientId: publicClientId(ConnectorId.music),
        scope: 'user-library-read user-read-recently-played',
        usePKCE: true,
      };
    // bible + church_mgmt are ALIAS connectors — no OAuth authorization flow.
    case ConnectorId.bible:
    case ConnectorId.church_mgmt:
    default:
      return null;
  }
}

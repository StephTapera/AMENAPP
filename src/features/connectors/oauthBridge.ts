/**
 * oauthBridge.ts — JS side of the native OAuth bridge for the Connectors Hub.
 * OWNER: Connected Intelligence v1 — native OAuth bridge lane.
 *
 * RESPONSIBILITY
 *   Provide the `beginOAuth` function that ConnectorsHubScreen calls when the user
 *   taps "connect" on a NEW provider (calendar / music). It:
 *     1. Detects the native host bridge (window.webkit.messageHandlers.connectorOAuth).
 *     2. Builds the PUBLIC auth params from oauthConfig.ts (NO secrets).
 *     3. Asks the native side to present ASWebAuthenticationSession + capture the
 *        redirect, returning ONLY a short-lived { code, redirectUri, codeVerifier? }.
 *     4. Hands that to the caller, which exchanges it via connectorOAuthExchange
 *        (token exchange + storage happen SERVER-SIDE — never here).
 *
 * HARD CONSTRAINTS (enforced below)
 *   - FAIL CLOSED when the native bridge is ABSENT (plain web / no native host):
 *     reject with NativeBridgeUnavailableError so the UI shows "open in app to
 *     connect" — NEVER a fake success.
 *   - The auth `code` returned here is held ONLY in memory, en route to the CF.
 *     The PKCE `code_verifier` is generated + stored in the KEYCHAIN by the native
 *     side; it is NEVER placed in localStorage/sessionStorage/JS persistence. JS
 *     receives the verifier transiently ONLY to forward it to the CF in the same
 *     call stack — it is not persisted anywhere on the JS side.
 *   - No client API keys, no client_secret: only the PUBLIC client_id appears.
 */

import { ConnectorId } from '../connectedIntelligence.contracts';
import {
  getConnectorOAuthParams,
  OAUTH_REDIRECT_URI,
} from './oauthConfig';

/** Thrown when there is no native host to present ASWebAuthenticationSession. */
export class NativeBridgeUnavailableError extends Error {
  readonly code = 'native_bridge_unavailable';
  constructor() {
    super('Open this in the Amen app to connect.');
    this.name = 'NativeBridgeUnavailableError';
  }
}

/** Thrown when a connector has no OAuth flow (alias connector) or missing config. */
export class OAuthConfigError extends Error {
  readonly code = 'oauth_config_error';
  constructor(message: string) {
    super(message);
    this.name = 'OAuthConfigError';
  }
}

/** Thrown when the user cancels, or the native session fails to return a code. */
export class OAuthFlowError extends Error {
  readonly code = 'oauth_flow_error';
  constructor(message: string) {
    super(message);
    this.name = 'OAuthFlowError';
  }
}

/** The minimal shape ConnectorsHubScreen.beginOAuth must return. */
export interface OAuthBridgeResult {
  code: string;
  redirectUri: string;
  codeVerifier?: string;
}

/** Request the native side presents + builds. PUBLIC params only. */
interface NativeOAuthRequest {
  connectorId: string;
  authorizationEndpoint: string;
  clientId: string;
  scope: string;
  redirectUri: string;
  usePKCE: boolean;
  extraAuthParams?: Record<string, string>;
}

/** What the native handler replies with (WKScriptMessageHandlerWithReply). */
interface NativeOAuthReply {
  ok: boolean;
  code?: string;
  redirectUri?: string;
  codeVerifier?: string;
  error?: string;
  cancelled?: boolean;
}

/** The WebKit message-handler bridge name, mirrored in ConnectorOAuthBridge.swift. */
const BRIDGE_HANDLER = 'connectorOAuth';

interface WebKitReplyHandler {
  postMessage(message: unknown): Promise<unknown>;
}

/**
 * True iff a native host that can present ASWebAuthenticationSession is reachable.
 * Used by ConnectorsHubScreen to decide whether to show the new hub at all.
 */
export function isNativeOAuthBridgeAvailable(): boolean {
  return nativeHandler() !== null;
}

function nativeHandler(): WebKitReplyHandler | null {
  const w = globalThis as unknown as {
    webkit?: { messageHandlers?: Record<string, WebKitReplyHandler> };
  };
  const handler = w?.webkit?.messageHandlers?.[BRIDGE_HANDLER];
  return handler && typeof handler.postMessage === 'function' ? handler : null;
}

/**
 * beginOAuth — the function passed to <ConnectorsHubScreen beginOAuth=... />.
 *
 * Resolves with { code, redirectUri, codeVerifier? } for the caller to forward to
 * connectorOAuthExchange. Rejects (fail-closed) when the native bridge is absent,
 * the connector has no OAuth flow, the public client id is unconfigured, or the
 * user cancels.
 */
export async function beginOAuth(meta: {
  id: ConnectorId;
  title: string;
}): Promise<OAuthBridgeResult> {
  // 1. FAIL CLOSED — no native host ⇒ no real OAuth is possible here.
  const handler = nativeHandler();
  if (!handler) {
    throw new NativeBridgeUnavailableError();
  }

  // 2. Resolve PUBLIC auth params (no secrets). Alias connectors have none.
  const params = getConnectorOAuthParams(meta.id);
  if (!params) {
    throw new OAuthConfigError(`Connector "${meta.id}" has no OAuth flow.`);
  }
  if (!params.clientId) {
    // Misconfigured environment — surface, do NOT fake a connection.
    throw new OAuthConfigError(
      `OAuth client id for "${meta.id}" is not configured.`,
    );
  }

  const request: NativeOAuthRequest = {
    connectorId: meta.id,
    authorizationEndpoint: params.authorizationEndpoint,
    clientId: params.clientId,
    scope: params.scope,
    redirectUri: OAUTH_REDIRECT_URI,
    usePKCE: params.usePKCE,
    extraAuthParams: params.extraAuthParams,
  };

  // 3. Ask the native side to present + capture. WKScriptMessageHandlerWithReply
  //    returns a Promise; the native handler does PKCE + Keychain + the web session.
  let reply: NativeOAuthReply;
  try {
    reply = (await handler.postMessage(request)) as NativeOAuthReply;
  } catch (err) {
    throw new OAuthFlowError(
      err instanceof Error ? err.message : 'The connection could not be completed.',
    );
  }

  if (!reply || reply.ok !== true) {
    if (reply?.cancelled) {
      throw new OAuthFlowError('Connection cancelled.');
    }
    throw new OAuthFlowError(reply?.error || 'The connection could not be completed.');
  }
  if (!reply.code || !reply.redirectUri) {
    throw new OAuthFlowError('No authorization code was returned.');
  }

  // 4. Return ONLY the short-lived code (+ verifier en route to the CF). No token,
  //    no persistence. The caller immediately exchanges it server-side.
  return {
    code: reply.code,
    redirectUri: reply.redirectUri,
    codeVerifier: reply.codeVerifier,
  };
}

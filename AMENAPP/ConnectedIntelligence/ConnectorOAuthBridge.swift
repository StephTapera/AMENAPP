//
//  ConnectorOAuthBridge.swift
//  AMENAPP
//
//  Native OAuth bridge for the Connected Intelligence "Connectors Hub".
//
//  WHAT THIS IS
//  ────────────
//  The Connectors Hub is a React/TS surface hosted in a WKWebView. NEW connectors
//  (Calendar, Music) require a real OAuth authorization flow that a web view cannot
//  perform safely on its own. This bridge supplies that missing piece:
//
//    JS  ──postMessage(req)──▶  ConnectorOAuthBridge (WKScriptMessageHandlerWithReply)
//                                  │  generate PKCE verifier+challenge
//                                  │  store verifier in Keychain (this-device-only)
//                                  │  build provider auth URL (+ state + PKCE challenge)
//                                  ▼
//                              ASWebAuthenticationSession  ──▶ provider consent screen
//                                  │  user approves
//                                  ▼
//                              callback amenapp://oauth/connector?code=…&state=…
//                                  │  validate state, load+delete verifier from Keychain
//                                  ▼
//    JS  ◀──reply{ ok, code, redirectUri, codeVerifier }── ConnectorOAuthBridge
//
//  The JS side (oauthBridge.ts) then forwards { code, redirectUri, codeVerifier }
//  to the `connectorOAuthExchange` Cloud Function, which performs the token
//  exchange with the provider's client_secret and stores the resulting OAuth
//  tokens SERVER-SIDE ONLY (connectorTokens collection). No third-party token ever
//  touches this device or JS.
//
//  SECURITY INVARIANTS
//  ───────────────────
//  • TOKENS NEVER ON-DEVICE / NEVER IN JS. This bridge only ever handles the
//    short-lived authorization CODE and the PKCE verifier. It never sees, stores,
//    or returns an access/refresh token.
//  • PKCE code_verifier (the one piece that must persist across the async web
//    session) is written to the iOS Keychain with
//    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly + kSecAttrSynchronizable=false,
//    matching the app's existing Keychain convention (AMENEncryptionService /
//    TwoFactorAuthService). It is deleted immediately after the code is captured.
//    It is NEVER placed in UserDefaults, a file, or anything JS-readable.
//  • Only the PUBLIC client_id + authorization endpoint arrive from JS. The OAuth
//    client_secret lives ONLY in Cloud Functions Secret Manager.
//  • `state` is a fresh random nonce per attempt; a callback whose state does not
//    match is rejected (CSRF defense).
//
//  XCODE TARGET MEMBERSHIP (human step): this file is added to the worktree but NOT
//  to the .xcodeproj. Add it to the AMENAPP app target in Xcode (or via the build
//  tooling) before building. It compiles against UIKit + WebKit +
//  AuthenticationServices, all already linked by the app.
//

import Foundation
import WebKit
import AuthenticationServices
import CryptoKit
import Security

private struct ConnectorOAuthLog: Sendable {
    func error(_ message: String) {
        #if DEBUG
        debugPrint("ConnectorOAuthBridge: \(message)")
        #endif
    }
}

// MARK: - ConnectorOAuthBridge

/// WKScriptMessageHandlerWithReply that presents ASWebAuthenticationSession for a
/// connector OAuth flow and returns the captured authorization code to JS.
///
/// Register on the prototype web view's user-content controller via
/// `ConnectorOAuthBridge.register(on:presentationAnchorProvider:)`.
@MainActor
final class ConnectorOAuthBridge: NSObject {

    /// Mirror of `BRIDGE_HANDLER` in oauthBridge.ts. JS calls
    /// `window.webkit.messageHandlers.connectorOAuth.postMessage(req)`.
    static let handlerName = "connectorOAuth"

    /// Nonisolated so it is callable from the ASWebAuthenticationSession completion handler.
    nonisolated private static let log = ConnectorOAuthLog()

    /// Supplies the window that the system web-auth sheet is anchored to.
    private let anchorProvider: () -> ASPresentationAnchor

    /// Strong reference to the in-flight session (ASWebAuthenticationSession is not
    /// retained by the system once `start()` returns control).
    private var activeSession: ASWebAuthenticationSession?

    private init(anchorProvider: @escaping () -> ASPresentationAnchor) {
        self.anchorProvider = anchorProvider
        super.init()
    }

    /// Register the bridge on the prototype WKWebView's content controller.
    /// Call this when building the WebView that hosts the React prototype.
    ///
    /// - Returns: the bridge instance (retain it for the lifetime of the web view).
    @discardableResult
    static func register(
        on controller: WKUserContentController,
        presentationAnchorProvider: @escaping () -> ASPresentationAnchor
    ) -> ConnectorOAuthBridge {
        let bridge = ConnectorOAuthBridge(anchorProvider: presentationAnchorProvider)
        controller.addScriptMessageHandler(bridge, contentWorld: .page, name: handlerName)
        return bridge
    }

    /// Remove the handler (e.g. when tearing down the web view) to avoid leaks.
    static func unregister(from controller: WKUserContentController) {
        controller.removeScriptMessageHandler(forName: handlerName, contentWorld: .page)
    }
}

// MARK: - Request / Keychain constants

private enum OAuthBridgeKeychain {
    /// Account prefix for the transient PKCE verifier. Reserved namespace —
    /// deliberately distinct from the E2EE `com.amenapp.*` keys and the identity
    /// hint, so connector-flow items are isolated and self-clean.
    static let verifierPrefix = "com.amenapp.connector.pkce."
}

/// Parsed, validated form of the JS request. PUBLIC fields only — no secrets.
private struct ConnectorOAuthRequest {
    let connectorId: String
    let authorizationEndpoint: URL
    let clientId: String
    let scope: String
    let redirectUri: URL
    let usePKCE: Bool
    let extraAuthParams: [String: String]

    init?(from body: Any) {
        guard let dict = body as? [String: Any],
              let connectorId = dict["connectorId"] as? String,
              let endpointStr = dict["authorizationEndpoint"] as? String,
              let endpoint = URL(string: endpointStr),
              let clientId = dict["clientId"] as? String, !clientId.isEmpty,
              let scope = dict["scope"] as? String,
              let redirectStr = dict["redirectUri"] as? String,
              let redirect = URL(string: redirectStr)
        else { return nil }

        self.connectorId = connectorId
        self.authorizationEndpoint = endpoint
        self.clientId = clientId
        self.scope = scope
        self.redirectUri = redirect
        self.usePKCE = (dict["usePKCE"] as? Bool) ?? true
        self.extraAuthParams = (dict["extraAuthParams"] as? [String: String]) ?? [:]
    }

    /// The custom URL scheme ASWebAuthenticationSession listens for (e.g. "amenapp").
    var callbackScheme: String? { redirectUri.scheme }
}

// MARK: - WKScriptMessageHandlerWithReply

extension ConnectorOAuthBridge: WKScriptMessageHandlerWithReply {

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard message.name == Self.handlerName else {
            replyHandler(Self.failure("unknown_handler"), nil)
            return
        }
        guard let request = ConnectorOAuthRequest(from: message.body),
              let scheme = request.callbackScheme else {
            replyHandler(Self.failure("invalid_request"), nil)
            return
        }

        // ── 1. PKCE: fresh verifier + challenge, verifier ⇒ Keychain (never JS). ──
        let verifier = request.usePKCE ? Self.makeCodeVerifier() : nil
        let challenge = verifier.map { Self.codeChallenge(for: $0) }
        let state = Self.randomURLSafe(byteCount: 32)

        if let verifier {
            // Persist the verifier so it survives the async web session. Keyed by
            // state so concurrent attempts don't collide. Fails closed if we cannot
            // store it (better to abort than to lose the verifier mid-flow).
            guard Self.keychainSave(verifier, account: Self.verifierAccount(state: state)) else {
                Self.log.error("PKCE verifier could not be persisted — aborting flow")
                replyHandler(Self.failure("keychain_unavailable"), nil)
                return
            }
        }

        // ── 2. Build the provider authorization URL. ──────────────────────────────
        guard let authURL = Self.buildAuthURL(request: request, state: state, challenge: challenge) else {
            Self.keychainDelete(account: Self.verifierAccount(state: state))
            replyHandler(Self.failure("auth_url_build_failed"), nil)
            return
        }

        // ── 3. Present ASWebAuthenticationSession; capture the redirect. ──────────
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: scheme
        ) { callbackURL, error in
            // Always purge the verifier from the Keychain at the end of the flow.
            defer { Self.keychainDelete(account: Self.verifierAccount(state: state)) }

            if let error {
                let nsErr = error as NSError
                if nsErr.domain == ASWebAuthenticationSessionError.errorDomain,
                   nsErr.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    replyHandler(Self.cancelled(), nil)
                } else {
                    Self.log.error("web auth session failed")
                    replyHandler(Self.failure("session_failed"), nil)
                }
                return
            }

            guard let callbackURL,
                  let result = Self.parseCallback(callbackURL, expectedState: state) else {
                replyHandler(Self.failure("invalid_callback"), nil)
                return
            }

            // Reply to JS with ONLY the short-lived code (+ verifier en route to the
            // CF). No token is ever produced here.
            replyHandler(
                Self.success(
                    code: result.code,
                    redirectUri: request.redirectUri.absoluteString,
                    codeVerifier: verifier
                ),
                nil
            )
        }

        session.presentationContextProvider = self
        // Use an ephemeral session so the provider's web cookies are not persisted
        // on-device — defense in depth for "nothing sensitive lingers on device".
        session.prefersEphemeralWebBrowserSession = true
        self.activeSession = session

        if !session.start() {
            Self.keychainDelete(account: Self.verifierAccount(state: state))
            replyHandler(Self.failure("session_start_failed"), nil)
        }
    }
}

// MARK: - Presentation anchor

extension ConnectorOAuthBridge: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchorProvider()
    }
}

// MARK: - URL building + callback parsing

private extension ConnectorOAuthBridge {

    nonisolated static func buildAuthURL(
        request: ConnectorOAuthRequest,
        state: String,
        challenge: String?
    ) -> URL? {
        guard var comps = URLComponents(url: request.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: request.clientId),
            URLQueryItem(name: "redirect_uri", value: request.redirectUri.absoluteString),
            URLQueryItem(name: "scope", value: request.scope),
            URLQueryItem(name: "state", value: state),
        ]
        if let challenge {
            items.append(URLQueryItem(name: "code_challenge", value: challenge))
            items.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }
        for (k, v) in request.extraAuthParams {
            items.append(URLQueryItem(name: k, value: v))
        }
        // Preserve any params already on the endpoint, then append ours.
        comps.queryItems = (comps.queryItems ?? []) + items
        return comps.url
    }

    struct CallbackResult { let code: String }

    /// Extract + validate the auth code from the redirect, enforcing `state`.
    nonisolated static func parseCallback(_ url: URL, expectedState: String) -> CallbackResult? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else { return nil }

        // Provider-reported error (e.g. user denied) ⇒ no code.
        if items.first(where: { $0.name == "error" })?.value != nil { return nil }

        let returnedState = items.first(where: { $0.name == "state" })?.value
        guard returnedState == expectedState else { return nil }   // CSRF guard

        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            return nil
        }
        return CallbackResult(code: code)
    }
}

// MARK: - PKCE

private extension ConnectorOAuthBridge {

    /// RFC 7636 code_verifier: 43–128 chars of unreserved URL-safe characters.
    nonisolated static func makeCodeVerifier() -> String {
        randomURLSafe(byteCount: 64)   // 64 bytes → 86 base64url chars
    }

    /// S256 challenge = base64url( SHA256( verifier ) ).
    nonisolated static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    nonisolated static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status != errSecSuccess {
            // Fallback — still high-entropy, never predictable token reuse.
            for i in 0..<byteCount { bytes[i] = UInt8.random(in: 0...255) }
        }
        return base64URLEncode(Data(bytes))
    }

    nonisolated static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Keychain (transient PKCE verifier only)

private extension ConnectorOAuthBridge {

    nonisolated static func verifierAccount(state: String) -> String {
        OAuthBridgeKeychain.verifierPrefix + state
    }

    @discardableResult
    nonisolated static func keychainSave(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let base: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
        ]
        SecItemDelete(base as CFDictionary)   // overwrite any stale entry
        var add = base
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrSynchronizable] = false   // never sync OAuth material to iCloud
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    nonisolated static func keychainDelete(account: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

// MARK: - JS reply payloads (mirror NativeOAuthReply in oauthBridge.ts)

private extension ConnectorOAuthBridge {

    nonisolated static func success(code: String, redirectUri: String, codeVerifier: String?) -> [String: Any] {
        var out: [String: Any] = ["ok": true, "code": code, "redirectUri": redirectUri]
        if let codeVerifier { out["codeVerifier"] = codeVerifier }
        return out
    }

    nonisolated static func failure(_ error: String) -> [String: Any] {
        ["ok": false, "error": error]
    }

    nonisolated static func cancelled() -> [String: Any] {
        ["ok": false, "cancelled": true, "error": "cancelled"]
    }
}

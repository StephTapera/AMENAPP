// AmenAccessPassDeepLinkRouter.swift
// AMENAPP — Access Pass Deep Link Parsing & Resolution
//
// Handles: QR scanner input, NFC tap, universal link, share link, in-app invite tap.
// All presentation methods resolve through the same backend call.
//
// URL shape: https://amen.app/access/{accessPassId}?t={rawToken}
//          or amen://access/{accessPassId}?t={rawToken}

import SwiftUI

@MainActor
final class AmenAccessPassDeepLinkRouter: ObservableObject {
    static let shared = AmenAccessPassDeepLinkRouter()

    @Published var pendingPassId: String?
    @Published var pendingToken: String?
    @Published var isPresenting: Bool = false
    @Published var resolvedPreview: AmenAccessPassPreview?
    @Published var resolveError: AmenAccessPassError?
    @Published var isResolving: Bool = false

    // Stored for post-auth redirect
    private var pendingAccessPassId: String?
    private var pendingRawToken: String?

    private init() {}

    // MARK: - Parse Universal Link

    func canHandle(url: URL) -> Bool {
        if url.scheme == "amen", url.host == "access" { return true }
        let isAmenDomain = url.host?.hasSuffix("amen.app") == true
        let hasAccessPath = url.pathComponents.contains("access")
        return isAmenDomain && hasAccessPath
    }

    func handle(url: URL) {
        guard let (passId, token) = parse(url: url) else { return }
        resolve(accessPassId: passId, token: token)
    }

    func handleQRPayload(_ payload: String) {
        guard let url = URL(string: payload), canHandle(url: url) else { return }
        handle(url: url)
    }

    func handleNFCPayload(_ payload: String) {
        handleQRPayload(payload)
    }

    func handleInviteToken(accessPassId: String, token: String) {
        resolve(accessPassId: accessPassId, token: token)
    }

    // MARK: - Parse URL

    private func parse(url: URL) -> (String, String)? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let token = components?.queryItems?.first(where: { $0.name == "t" })?.value ?? ""

        // amen://access/{passId}?t={token}
        if url.scheme == "amen", url.host == "access" {
            let parts = url.pathComponents.filter { $0 != "/" }
            if let passId = parts.first, !passId.isEmpty, !token.isEmpty {
                return (passId, token)
            }
        }

        // https://amen.app/access/{passId}?t={token}
        let parts = url.pathComponents.filter { $0 != "/" }
        if let accessIndex = parts.firstIndex(of: "access"),
           parts.indices.contains(accessIndex + 1) {
            let passId = parts[accessIndex + 1]
            if !passId.isEmpty, !token.isEmpty {
                return (passId, token)
            }
        }
        return nil
    }

    // MARK: - Resolve

    func resolve(accessPassId: String, token: String) {
        guard AMENFeatureFlags.shared.accessPassesEnabled else {
            resolveError = .unknown("This invite feature is not available right now.")
            isPresenting = true
            return
        }

        pendingPassId = accessPassId
        pendingToken = token
        isResolving = true
        resolveError = nil
        resolvedPreview = nil
        isPresenting = true

        Task {
            do {
                let preview = try await AmenAccessPassService.shared.resolveAccessPass(
                    accessPassId: accessPassId,
                    token: token
                )
                self.resolvedPreview = preview
                self.isResolving = false
                AmenAccessPassAnalytics.shared.logResolved(passId: accessPassId, targetType: preview.targetType, mode: preview.mode)
            } catch let passError as AmenAccessPassError {
                self.resolveError = passError
                self.isResolving = false
                AmenAccessPassAnalytics.shared.logInvalid(passId: accessPassId)
            } catch {
                self.resolveError = .unknown(error.localizedDescription)
                self.isResolving = false
            }
        }
    }

    // MARK: - Post-Auth Redirect

    func storePendingPassForAfterSignIn(accessPassId: String, token: String) {
        pendingAccessPassId = accessPassId
        pendingRawToken = token
    }

    func resumePendingPassAfterSignIn() {
        guard let passId = pendingAccessPassId, let token = pendingRawToken else { return }
        pendingAccessPassId = nil
        pendingRawToken = nil
        resolve(accessPassId: passId, token: token)
    }

    func dismiss() {
        isPresenting = false
        resolvedPreview = nil
        resolveError = nil
        pendingPassId = nil
        pendingToken = nil
    }
}

// MARK: - Convenience View Modifier

extension View {
    func amenAccessPassDeepLinkHandler() -> some View {
        self.modifier(AmenAccessPassDeepLinkModifier())
    }
}

private struct AmenAccessPassDeepLinkModifier: ViewModifier {
    @StateObject private var router = AmenAccessPassDeepLinkRouter.shared

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                if AmenAccessPassDeepLinkRouter.shared.canHandle(url: url) {
                    AmenAccessPassDeepLinkRouter.shared.handle(url: url)
                }
            }
            .sheet(isPresented: $router.isPresenting) {
                AmenAccessPassLandingView(
                    accessPassId: router.pendingPassId ?? "",
                    token: router.pendingToken ?? "",
                    preview: router.resolvedPreview,
                    error: router.resolveError,
                    isResolving: router.isResolving
                )
            }
    }
}

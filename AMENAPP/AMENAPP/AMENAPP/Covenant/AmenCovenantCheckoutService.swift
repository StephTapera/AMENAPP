import Foundation
import AuthenticationServices
import FirebaseFunctions
import FirebaseAuth
import UIKit

// MARK: - Checkout Error

enum CheckoutError: LocalizedError {
    case networkError(Error)
    case invalidResponse
    case sessionCanceled

    var errorDescription: String? {
        switch self {
        case .networkError(let underlying): return underlying.localizedDescription
        case .invalidResponse:             return "Received an unexpected response from the server."
        case .sessionCanceled:             return "Checkout was canceled."
        }
    }
}

// MARK: - Checkout State

extension AmenCovenantCheckoutService {
    enum CheckoutState {
        case idle
        case loading
        case success(membershipId: String)
        case canceled
        case failed(Error)
    }
}

// MARK: - Covenant Checkout Service

/// Drives the Stripe-hosted checkout flow for Covenant tier subscriptions.
/// Membership is NEVER written from the client — the server-side Stripe webhook
/// handles `covenantMemberships` creation after payment confirmation.
@MainActor
final class AmenCovenantCheckoutService: NSObject, ObservableObject {

    static let shared = AmenCovenantCheckoutService()

    @Published var isLoading: Bool = false
    @Published var checkoutState: CheckoutState = .idle

    private let functions = Functions.functions()
    private var authSession: ASWebAuthenticationSession?

    private override init() {}

    // MARK: - Start Checkout

    /// Calls the `createCovenantCheckoutSession` Cloud Function to get a Stripe-hosted
    /// checkout URL, then opens it via `ASWebAuthenticationSession`.
    /// The custom URL scheme `amen://covenant-checkout` is used as the callback.
    func startCheckout(covenantId: String, tierId: String) async {
        guard Auth.auth().currentUser != nil else {
            checkoutState = .failed(CheckoutError.invalidResponse)
            return
        }
        isLoading = true
        checkoutState = .loading
        defer { isLoading = false }

        do {
            let result = try await functions.httpsCallable("createCovenantCheckoutSession").call([
                "covenantId": covenantId,
                "tierId": tierId
            ])
            guard
                let data = result.data as? [String: Any],
                let urlString = data["checkoutUrl"] as? String,
                let checkoutURL = URL(string: urlString)
            else {
                checkoutState = .failed(CheckoutError.invalidResponse)
                return
            }
            await presentCheckoutSession(url: checkoutURL)
        } catch {
            checkoutState = .failed(CheckoutError.networkError(error))
        }
    }

    // MARK: - ASWebAuthenticationSession Presentation

    private func presentCheckoutSession(url: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "amen"
            ) { [weak self] callbackURL, error in
                guard let self else {
                    continuation.resume()
                    return
                }
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    self.checkoutState = .canceled
                    continuation.resume()
                    return
                }
                if let error {
                    self.checkoutState = .failed(CheckoutError.networkError(error))
                    continuation.resume()
                    return
                }
                guard let callbackURL else {
                    self.checkoutState = .failed(CheckoutError.invalidResponse)
                    continuation.resume()
                    return
                }
                self.handleCallback(callbackURL)
                continuation.resume()
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }

    // MARK: - Callback Parsing

    /// Parses `amen://covenant-checkout?result=success&membershipId=xyz` or `?result=cancel`.
    private func handleCallback(_ url: URL) {
        guard
            url.scheme == "amen",
            url.host == "covenant-checkout"
        else {
            checkoutState = .failed(CheckoutError.invalidResponse)
            return
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let params = Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name, value)
            }
        )
        switch params["result"] {
        case "success":
            let membershipId = params["membershipId"] ?? ""
            guard !membershipId.isEmpty else {
                checkoutState = .failed(CheckoutError.invalidResponse)
                return
            }
            Task { await verifyAndConfirmMembership(membershipId: membershipId) }
        case "cancel":
            checkoutState = .canceled
        default:
            checkoutState = .failed(CheckoutError.invalidResponse)
        }
    }

    // MARK: - Server Membership Verification

    /// Confirms with the server that the membership created by the Stripe webhook
    /// actually exists before surfacing success to the UI. Trusting only the URL
    /// param would allow a forged callback to unlock covenant features client-side.
    private func verifyAndConfirmMembership(membershipId: String) async {
        do {
            _ = try await functions.httpsCallable("verifyCovenantMembership").call([
                "membershipId": membershipId
            ])
            checkoutState = .success(membershipId: membershipId)
            NotificationCenter.default.post(
                name: .covenantCheckoutSucceeded,
                object: nil,
                userInfo: ["membershipId": membershipId]
            )
        } catch {
            checkoutState = .failed(CheckoutError.networkError(error))
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension AmenCovenantCheckoutService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let covenantCheckoutSucceeded = Notification.Name("covenantCheckoutSucceeded")
}

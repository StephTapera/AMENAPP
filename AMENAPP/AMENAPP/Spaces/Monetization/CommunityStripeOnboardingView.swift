// CommunityStripeOnboardingView.swift
// AMENAPP — Spaces Monetization (Agent E)
//
// Glass sheet for community owners enabling paid Spaces.
//
// Flow:
//   1. Owner taps "Enable paid Spaces" in community settings.
//   2. Button → calls `createStripeConnectAccount` CF.
//   3. CF creates Stripe Express account, returns { accountId, onboardingURL }.
//   4. ASWebAuthenticationSession opens the onboarding URL.
//   5. On return: CF has already written stripeConnectAccountId to
//      amenCommunities/{communityId}.
//   6. Shows "Your account is ready" glass card.
//
// Hard constraints:
//   - stripeConnectAccountId is SERVER-OWNED; client never writes it.
//   - Collection is `amenCommunities` (never `communities`).
//   - Money never crosses a community Link.

import SwiftUI
import AuthenticationServices
import FirebaseFunctions
import UIKit

// MARK: - Onboarding State

private enum OnboardingState: Equatable {
    case idle
    case loading
    case awaitingReturn
    case complete(accountId: String)
    case failed(message: String)

    static func == (lhs: OnboardingState, rhs: OnboardingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.awaitingReturn, .awaitingReturn): return true
        case (.complete(let a), .complete(let b)): return a == b
        case (.failed(let a), .failed(let b)):     return a == b
        default: return false
        }
    }
}

// MARK: - CommunityStripeOnboardingView

struct CommunityStripeOnboardingView: View {

    let communityId: String
    @Binding var isPresented: Bool

    @State private var onboardingState: OnboardingState = .idle
    @StateObject private var coordinator = StripeOnboardingCoordinator()

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        headerSection
                        benefitsSection
                        actionSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 44)
                }
            }
            .navigationTitle("Paid Spaces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if reduceTransparency {
            AmenTheme.Colors.backgroundGrouped
        } else {
            LinearGradient(
                colors: [AmenTheme.Colors.backgroundPrimary,
                         AmenTheme.Colors.amenPurple.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 72, height: 72)
                    .overlay {
                        Circle().stroke(AmenTheme.Colors.amenGold.opacity(0.30), lineWidth: 1)
                    }
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
            }
            .accessibilityHidden(true)

            Text("Enable Paid Spaces")
                .font(.title2.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("Charge members for access to your premium Spaces. Powered by Stripe.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Benefits

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow(icon: "lock.rectangle.stack.fill",
                       title: "Per-Space gating",
                       detail: "Charge for individual Spaces — chat, study, or group.")
            benefitRow(icon: "arrow.clockwise.circle.fill",
                       title: "One-time or recurring",
                       detail: "Set a one-time price or a monthly/yearly subscription.")
            benefitRow(icon: "banknote.fill",
                       title: "Direct payouts",
                       detail: "Revenue goes straight to your Stripe account.")
        }
        .padding(18)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(AmenTheme.Colors.backgroundGroupedRow)
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }

    // MARK: - Action Section

    @ViewBuilder
    private var actionSection: some View {
        switch onboardingState {
        case .idle:
            enableButton
        case .loading:
            loadingView(label: "Setting up your account…")
        case .awaitingReturn:
            loadingView(label: "Completing Stripe onboarding…")
        case .complete(let accountId):
            completeView(accountId: accountId)
        case .failed(let message):
            VStack(spacing: 16) {
                errorView(message: message)
                enableButton
            }
        }
    }

    private var enableButton: some View {
        Button {
            Task { await startOnboarding() }
        } label: {
            Label("Enable paid Spaces", systemImage: "creditcard")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(AmenTheme.Colors.amenGold,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: AmenTheme.Colors.amenGold.opacity(0.35), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Enable paid Spaces")
        .accessibilityHint("Double-tap to set up your Stripe Connect account")
    }

    private func loadingView(label: String) -> some View {
        HStack(spacing: 12) {
            ProgressView().progressViewStyle(.circular)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .accessibilityLabel(label)
    }

    private func completeView(accountId: String) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.green.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.green)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your account is ready")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("You can now create paid Spaces.")
                        .font(.footnote)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .fill(AmenTheme.Colors.backgroundGroupedRow)
                } else {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                                .fill(Color.green.opacity(0.05))
                        }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .stroke(Color.green.opacity(0.25), lineWidth: 0.5)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Your account is ready. You can now create paid Spaces.")

            Button { isPresented = false } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AmenTheme.Colors.amenGold.opacity(0.30), lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
        }
    }

    private func errorView(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote).foregroundStyle(.red)
                .multilineTextAlignment(.leading)
        }
        .accessibilityLabel("Error: \(message)")
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - Start Onboarding

    private func startOnboarding() async {
        onboardingState = .loading
        do {
            let result = try await coordinator.createConnectAccount(communityId: communityId)
            onboardingState = .awaitingReturn
            guard let url = URL(string: result.onboardingURL) else {
                onboardingState = .failed(message: "Invalid onboarding URL returned from server.")
                return
            }
            try await coordinator.presentOnboarding(url: url)
            onboardingState = .complete(accountId: result.accountId)
        } catch let error as StripeOnboardingError {
            onboardingState = .failed(message: error.localizedDescription)
        } catch {
            onboardingState = .failed(message: error.localizedDescription)
        }
    }
}

// MARK: - Stripe Onboarding Error

private enum StripeOnboardingError: LocalizedError {
    case canceled
    case invalidResponse
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .canceled:        return "Onboarding was canceled."
        case .invalidResponse: return "Received an unexpected response. Please try again."
        case .network(let e):  return e.localizedDescription
        }
    }
}

// MARK: - Stripe Connect Account Result

private struct StripeConnectAccountResult {
    let accountId: String
    let onboardingURL: String
}

// MARK: - StripeOnboardingCoordinator

@MainActor
private final class StripeOnboardingCoordinator: NSObject, ObservableObject {

    private let functions = Functions.functions()
    private var authSession: ASWebAuthenticationSession?

    func createConnectAccount(communityId: String) async throws -> StripeConnectAccountResult {
        // B-24: Gate — createStripeConnectAccount CF is not yet deployed.
        guard AMENFeatureFlags.shared.paymentsEnabled else {
            throw StripeOnboardingError.canceled
        }
        let payload: [String: Any] = ["communityId": communityId]
        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("createStripeConnectAccount").call(payload)
        } catch {
            throw StripeOnboardingError.network(error)
        }
        guard
            let data = result.data as? [String: Any],
            let accountId = data["accountId"] as? String,
            let onboardingURL = data["onboardingURL"] as? String,
            !accountId.isEmpty, !onboardingURL.isEmpty
        else {
            throw StripeOnboardingError.invalidResponse
        }
        return StripeConnectAccountResult(accountId: accountId, onboardingURL: onboardingURL)
    }

    func presentOnboarding(url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "amen"
            ) { _, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: StripeOnboardingError.canceled)
                    return
                }
                if let error {
                    continuation.resume(throwing: StripeOnboardingError.network(error))
                    return
                }
                continuation.resume()
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }
}

extension StripeOnboardingCoordinator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

// MARK: - Preview

#if DEBUG
#Preview("CommunityStripeOnboardingView") {
    CommunityStripeOnboardingView(communityId: "community_123", isPresented: .constant(true))
}
#endif

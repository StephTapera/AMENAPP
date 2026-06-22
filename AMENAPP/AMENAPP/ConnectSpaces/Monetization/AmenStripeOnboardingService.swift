// AmenStripeOnboardingService.swift
// AMEN Spaces — Monetization: Stripe Connect onboarding service + sheet
//
// Glass rule: sheet background is .ultraThinMaterial over dark;
// no glass-on-glass layering inside the card container.
// Written: 2026-06-02

import SwiftUI
import SafariServices
import FirebaseFunctions

// MARK: - Service

@MainActor
final class AmenStripeOnboardingService: ObservableObject {

    @Published var onboardingURL: URL?
    @Published var isLoading: Bool = false
    @Published var error: String?

    private let functions: Functions = Functions.functions()

    // MARK: - Public API

    /// Calls the `createStripeConnectAccount` CF and parses the returned URL.
    /// On success `onboardingURL` is set and callers should present the Safari sheet.
    func fetchOnboardingURL(spaceId: String) async {
        guard !spaceId.isEmpty else {
            error = "Space identifier is missing."
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let callable = functions.httpsCallable("createStripeConnectAccount")
            let result = try await callable.call(["spaceId": spaceId])

            guard
                let data = result.data as? [String: Any],
                let urlString = data["url"] as? String,
                let url = URL(string: urlString)
            else {
                error = "Could not parse onboarding link from server."
                return
            }

            onboardingURL = url
        } catch {
            self.error = "Could not start Stripe onboarding. Please check your connection and try again."
        }
    }

    /// Resets state so the sheet can be re-presented (e.g. after user returns
    /// from Safari and onboarding is incomplete).
    func reset() {
        onboardingURL = nil
        error = nil
    }
}

// MARK: - Safari View (UIViewControllerRepresentable)

/// Wraps `SFSafariViewController` for use inside SwiftUI sheets.
struct AmenSafariView: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredBarTintColor = UIColor(red: 0.07, green: 0.024, blue: 0.027, alpha: 1)
        vc.preferredControlTintColor = UIColor(red: 0.851, green: 0.643, blue: 0.255, alpha: 1)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Stripe Onboarding Sheet

/// Full-screen sheet that walks a space host through Stripe Connect onboarding.
/// Present using `.sheet(isPresented:)` or `.fullScreenCover(isPresented:)`.
struct AmenStripeOnboardingSheet: View {

    let spaceId: String
    let onDismiss: () -> Void

    @StateObject private var service = AmenStripeOnboardingService()
    @State private var showingSafari: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Dark canvas — not glass so inner card reads clearly
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHandle
                Spacer()
                contentCard
                Spacer()
                dismissButton
                    .padding(.bottom, 36)
            }
        }
        .task { await service.fetchOnboardingURL(spaceId: spaceId) }
        .fullScreenCover(isPresented: $showingSafari, onDismiss: {
            // User returned from Safari; reset so they can re-enter if needed
            service.reset()
        }) {
            if let url = service.onboardingURL {
                AmenSafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .onChange(of: service.onboardingURL) { _, url in
            if url != nil {
                // Small delay so the loading state resolves before Safari appears
                withAnimation(reduceMotion ? nil : .easeIn(duration: 0.15)) {
                    showingSafari = true
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Sub-views

    private var sheetHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.25))
            .frame(width: 36, height: 5)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .accessibilityHidden(true)
    }

    private var contentCard: some View {
        VStack(spacing: 20) {
            stripeLockup

            if service.isLoading {
                loadingState
            } else if let errorMessage = service.error {
                errorState(message: errorMessage)
            } else {
                readyState
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
    }

    private var stripeLockup: some View {
        VStack(spacing: 10) {
            Image(systemName: "creditcard.and.123")
                .font(.systemScaled(36, weight: .light))
                .foregroundStyle(Color(hex: "D9A441"))
                .accessibilityHidden(true)

            Text("Connect Stripe")
                .font(.systemScaled(22, weight: .bold))
                .foregroundStyle(.white)

            Text("Set up payouts to start receiving membership revenue from your Space.")
                .font(.systemScaled(14))
                .foregroundStyle(Color.white.opacity(0.60))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color(hex: "D9A441"))
                .scaleEffect(1.2)
                .accessibilityHidden(true)

            Text("Connecting to Stripe...")
                .font(.systemScaled(14))
                .foregroundStyle(Color.white.opacity(0.55))
                .accessibilityLabel("Loading Stripe onboarding, please wait")
        }
        .padding(.vertical, 8)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.systemScaled(13))
                .foregroundStyle(Color.red.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Error: \(message)")

            Button {
                Task { await service.fetchOnboardingURL(spaceId: spaceId) }
            } label: {
                Text("Try Again")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "D9A441"))
                    )
            }
            .accessibilityLabel("Retry Stripe connection")
        }
    }

    private var readyState: some View {
        Button {
            if service.onboardingURL != nil {
                showingSafari = true
            } else {
                Task { await service.fetchOnboardingURL(spaceId: spaceId) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.systemScaled(15, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Open Stripe Onboarding")
                    .font(.systemScaled(15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "D9A441"))
            )
        }
        .accessibilityLabel("Open Stripe Connect onboarding in Safari")
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Text("Not now")
                .font(.systemScaled(14))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .accessibilityLabel("Dismiss Stripe onboarding sheet")
    }
}

// MARK: - Preview

#Preview("Loading") {
    AmenStripeOnboardingSheet(spaceId: "preview-space") {}
}

#Preview("Error") {
    let sheet = AmenStripeOnboardingSheet(spaceId: "preview-space") {}
    // Preview shows error state by observing service — illustrative only
    return sheet
}

// TrustWarningBanner.swift
// AMEN — Global Resilience System
// Impersonation-risk banner shown on profile views.
// Non-dismissable. The caller controls visibility via isVisible or the
// .trustWarningBanner(userId:) view modifier which fetches the score automatically.

import SwiftUI
import FirebaseFunctions
import FirebaseFirestore

// MARK: - TrustWarningBanner

/// Red-tinted glass banner warning that an account may be impersonating someone.
/// Not dismissable. Caller controls `isVisible`; for automatic score-based
/// display, apply the `.trustWarningBanner(userId:)` modifier instead.
///
/// - Parameters:
///   - message: Override message. Defaults to the standard impersonation copy.
///   - level: Reserved for future severity tiers; currently always treated as "high".
///   - isVisible: When `false` the view renders nothing (EmptyView).
struct TrustWarningBanner: View {

    // MARK: Input

    let message: String
    let level: String
    let isVisible: Bool

    // MARK: Constants

    private static let defaultMessage =
        "This account may be impersonating someone. Verify identity before engaging."

    // MARK: Body

    var body: some View {
        if isVisible {
            bannerContent
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
        }
    }

    // MARK: Banner Layout

    private var bannerContent: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.red)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Potential Impersonation Risk")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(effectiveMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.12))
                .glassEffect()
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.45), lineWidth: 1.5)
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trust warning: \(effectiveMessage)")
    }

    // MARK: Helpers

    private var effectiveMessage: String {
        message.isEmpty ? Self.defaultMessage : message
    }
}

// MARK: - TrustWarningBannerModifier

/// Fetches the trust profile for `userId` and shows `TrustWarningBanner`
/// automatically when `impersonationRiskScore > 0.70`.
private struct TrustWarningBannerModifier: ViewModifier {

    let userId: String

    @State private var isVisible: Bool = false
    @State private var fetchComplete: Bool = false

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if isVisible {
                TrustWarningBanner(
                    message: "",
                    level: "high",
                    isVisible: isVisible
                )
                .padding(.bottom, 4)
            }

            content
        }
        .onAppear {
            guard !fetchComplete else { return }
            fetchTrustProfile()
        }
    }

    // MARK: Firestore Fetch

    /// Reads the `trustProfiles/{userId}` document and checks `impersonationRiskScore`.
    /// Falls back to the Cloud Function if the Firestore document is absent.
    private func fetchTrustProfile() {
        let db = Firestore.firestore()
        db.collection("trustProfiles").document(userId).getDocument { snapshot, error in
            if let data = snapshot?.data(),
               let score = data["impersonationRiskScore"] as? Double {
                DispatchQueue.main.async {
                    isVisible = score > 0.70
                    fetchComplete = true
                }
            } else {
                // Fallback: call the Cloud Function.
                fetchFromFunction()
            }
        }
    }

    /// Fallback to `trustScoring-getProfileTrustScore` when Firestore doc is missing.
    private func fetchFromFunction() {
        Task {
            do {
                let functions = Functions.functions()
                let result = try await functions
                    .httpsCallable("trustScoring-getProfileTrustScore")
                    .call(["userId": userId])

                guard let data = result.data as? [String: Any],
                      let score = data["impersonationRiskScore"] as? Double else {
                    // On error: fail safe — do not show banner if score unknown.
                    fetchComplete = true
                    return
                }

                isVisible = score > 0.70
                fetchComplete = true
            } catch {
                // On error: fail safe — do not show banner if score unknown.
                fetchComplete = true
            }
        }
    }
}

// MARK: - View Extension

extension View {

    /// Automatically fetches the trust profile for `userId` and overlays a
    /// `TrustWarningBanner` when the impersonation risk score exceeds 0.70.
    ///
    /// Usage:
    /// ```swift
    /// ProfileView(user: user)
    ///     .trustWarningBanner(userId: user.id)
    /// ```
    func trustWarningBanner(userId: String) -> some View {
        modifier(TrustWarningBannerModifier(userId: userId))
    }
}

// MARK: - Preview

#Preview("TrustWarningBanner — visible") {
    ZStack(alignment: .top) {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()

        VStack(spacing: 16) {
            TrustWarningBanner(
                message: "",
                level: "high",
                isVisible: true
            )

            TrustWarningBanner(
                message: "This ministry account has unusually high impersonation signals.",
                level: "high",
                isVisible: true
            )

            // isVisible = false → renders nothing
            TrustWarningBanner(
                message: "",
                level: "high",
                isVisible: false
            )

            Spacer()
        }
        .padding(.top, 24)
    }
}

#Preview("TrustWarningBanner — view modifier") {
    // Simulates how the modifier is applied to any profile view.
    VStack {
        Text("@someuser")
            .font(.title.bold())
        Text("Profile content here")
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    // Replace "preview-high-risk-uid" with a real UID during manual testing.
    .trustWarningBanner(userId: "preview-high-risk-uid")
}

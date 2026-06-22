// WIRING CERT (2026-06-11 | branch: safety-hardening)
// ─────────────────────────────────────────────────────────────────────────────
// WIRED:
//   • updateBirthYear CF call (server-enforced age-downgrade protection, M-02)
//   • AgeAssuranceService.setDateOfBirth() — writes full private age_assurance
//     subcollection and populates in-memory tier for downstream gating
//   • enforceMinorDefaults() via AmenChildSafetyService for tierB/tierC users
//     (sets privacyPreset:private, dmPolicy:mutualFollows, capability overrides)
//   • VoiceOver .announcement on under-age rejection (audit E-08)
//   • accessibilityReduceTransparency fallback for DatePicker background (E-08)
//
// DECISION-GATED (NOT wired — awaiting human resolution):
//   • Guardian consent UI for 13-15 (tierB):
//     AmenChildSafetyService.requestGuardianLink() exists and is stubbed below
//     behind TODO(gate: DECISION-OPEN-2). T&S Lead must resolve guardian scope
//     (C5 §4e / OPEN-2) before this can be activated. Until then, the minor
//     defaults (private posts, restricted DMs) are enforced but no guardian email
//     is solicited during first-run onboarding.
//   • Social sign-in age bypass (audit D-01): Google/Apple paths still bypass
//     DOB collection. This requires restructuring SignInView.swift and is gated
//     behind ff_onboarding_v2. Tracked in AUDIT.md D-01.
//
// Phone numbers: not present in this file. Masked at PhoneVerificationService
//   layer via redactedPhoneForLog() (last-4 only in DEBUG logs).
// ─────────────────────────────────────────────────────────────────────────────

//
//  AgeVerificationOnboardingView.swift
//  AMENAPP
//
//  New onboarding screen — inserted after the Welcome screen.
//  Dark glassmorphic design. Age gate: min 13 (COPPA). Saves ageTier to Firestore.
//

import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFunctions

struct AgeVerificationOnboardingView: View {
    @Binding var currentStep: Int
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var showUnderAgeMessage = false
    @State private var isSubmitting = false
    @State private var submissionError: String?

    /// Injected for testability; production callers leave nil to use .shared.
    var ageAssuranceService: AgeAssuranceService? = nil
    var childSafetyService: AmenChildSafetyService? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
    }

    // Derived age category using the canonical tier vocabulary (ageTier.js).
    private var ageCategory: AgeCategory {
        let birthYear = Calendar.current.component(.year, from: birthDate)
        let currentYear = Calendar.current.component(.year, from: Date())
        let computedAge = currentYear - birthYear
        if computedAge < 13 { return .blocked }
        if computedAge <= 15 { return .tierB }
        if computedAge <= 17 { return .tierC }
        return .tierD
    }

    var body: some View {
        ZStack {
            Color(hex: "#0A0A0A").ignoresSafeArea()

            // Glowing orbs
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: -80, y: -200)
                .allowsHitTesting(false)

            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: 120, y: 100)
                .allowsHitTesting(false)

            VStack(spacing: 32) {
                Spacer()

                Text("How old are you?")
                    .font(.systemScaled(32, weight: .bold))
                    .foregroundColor(.white)

                Text("We keep our community safe for everyone")
                    .font(.subheadline)
                    .foregroundColor(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // Wheel date picker — reduceTransparency fallback per audit E-08.
                DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .colorScheme(.dark)
                    // E-08 fix: opaque fallback when user has Reduce Transparency enabled.
                    .background(
                        reduceTransparency
                            ? AnyView(Color(white: 0.12))
                            : AnyView(Color.clear.background(.ultraThinMaterial))
                    )
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)

                if showUnderAgeMessage {
                    Text("This app isn't for you yet. Come back when you're 13!")
                        .foregroundColor(.red.opacity(0.8))
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let submissionError {
                    Text(submissionError)
                        .foregroundColor(.red.opacity(0.8))
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()

                // Glassmorphic black pill button
                Button(action: handleContinue) {
                    Text(isSubmitting ? "Checking..." : "Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.black)
                        .cornerRadius(50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 50)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                }
                .disabled(isSubmitting)
                .opacity(isSubmitting ? 0.7 : 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .accessibilityLabel(isSubmitting ? "Checking age, please wait" : "Continue")
            }
            .padding()
        }
    }

    private func handleContinue() {
        guard !isSubmitting else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            showUnderAgeMessage = false
            submissionError = nil
        }

        if age < 13 {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
                showUnderAgeMessage = true
            }
            // E-08 fix: post accessibility announcement so VoiceOver users hear the block.
            UIAccessibility.post(
                notification: .announcement,
                argument: "You must be 13 or older to use this app."
            )
            return
        }

        isSubmitting = true
        Task {
            do {
                try await submitAgeToServer()
                await MainActor.run {
                    isSubmitting = false
                    withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.8))) {
                        currentStep += 1
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    withAnimation(.easeInOut(duration: 0.25)) {
                        submissionError = "We couldn't verify your age yet. Please try again."
                    }
                }
            }
        }
    }

    /// Full age submission pipeline:
    ///   1. `updateBirthYear` CF — server-enforced tier write, downgrade protection (M-02)
    ///   2. `AgeAssuranceService.setDateOfBirth` — writes private/age_assurance subcollection,
    ///      populates in-memory currentUserTier for downstream gating
    ///   3. `enforceMinorDefaults` — for tierB/tierC: enforces private posts, restricted DMs,
    ///      capability overrides (defense-in-depth, server is authoritative)
    ///   4. Guardian link stub — TODO(gate: DECISION-OPEN-2)
    private func submitAgeToServer() async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AgeVerificationError.notAuthenticated
        }

        let birthYear = Calendar.current.component(.year, from: birthDate)

        // Step 1: Server-enforced tier write via updateBirthYear CF.
        // This is the authoritative write; it includes downgrade protection (M-02).
        _ = try await Functions.functions(region: "us-central1")
            .httpsCallable("updateBirthYear")
            .call(["birthYear": birthYear])

        // Step 2: Write full age_assurance subcollection and refresh in-memory tier.
        let service = ageAssuranceService ?? AgeAssuranceService.shared
        try await service.setDateOfBirth(userId: uid, dateOfBirth: birthDate)

        // Step 3: For minor tiers, enforce default privacy/capability restrictions.
        // This is defense-in-depth — the server-side Firestore rules and CF are authoritative.
        let category = ageCategory
        if category.isMinor {
            let safetyService = childSafetyService ?? AmenChildSafetyService.shared
            // Best-effort: log but do not surface to user if this write fails.
            // The server will enforce defaults regardless.
            do {
                try await safetyService.enforceMinorDefaults(userId: uid)
            } catch {
                dlog("[AgeVerificationOnboardingView] enforceMinorDefaults failed (non-fatal): \(error)")
            }
        }

        // Step 4: Guardian consent for tierB (13-15).
        // TODO(gate: DECISION-OPEN-2): Guardian scope is undefined for v1.
        // T&S Lead must resolve C5 §4e / OPEN-2 before activating this path.
        // When OPEN-2 is resolved:
        //   • Present a sheet collecting the guardian's email address.
        //   • Call AmenChildSafetyService.shared.requestGuardianLink(
        //         minorId: uid, guardianEmail: collectedEmail)
        //   • A CF trigger on /guardianLinkRequests sends the verification email.
        // Until then, minor onboarding proceeds without guardian email collection.
        // Minor defaults (private posts, restricted DMs) are already enforced above.
        if category == .tierB {
            dlog("[AgeVerificationOnboardingView] tierB user — guardian consent deferred (DECISION-OPEN-2)")
        }
    }
}

private enum AgeVerificationError: Error {
    case notAuthenticated
}

#Preview {
    AgeVerificationOnboardingView(currentStep: .constant(0))
}

// AccountStatusGate.swift
// AMENAPP
//
// C-3 fix: wraps the root ContentView and blocks access for banned/frozen accounts.
// Loaded once at app root — reads EnforcementLadderService after auth confirms user.
// Banned → hard block + link to appeal flow.
// Frozen → temporary lock screen with reason + expected lift time.
// Active → passes through to ContentView unchanged.

import SwiftUI
import FirebaseAuth

// MARK: - AccountStatusGate

struct AccountStatusGate<Content: View>: View {

    @ViewBuilder let content: () -> Content

    @State private var authUser: FirebaseAuth.User? = Auth.auth().currentUser
    @State private var didLoad = false
    private let ladder = EnforcementLadderService.shared

    var body: some View {
        Group {
            if !didLoad {
                // Show content immediately while enforcement status loads.
                // EnforcementLadderService will update @Observable state when ready.
                content()
                    .task {
                        if Auth.auth().currentUser != nil {
                            await ladder.loadCurrentUser()
                        }
                        didLoad = true
                    }
            } else if ladder.isBanned {
                BannedAccountView()
            } else if ladder.isFrozen {
                FrozenAccountView(enforcementHistory: ladder.enforcementHistory)
            } else {
                content()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("AmenAuthStateChanged"))) { _ in
            Task {
                if Auth.auth().currentUser != nil {
                    await ladder.loadCurrentUser()
                }
            }
        }
    }
}

// MARK: - Banned Account Screen

private struct BannedAccountView: View {

    @State private var showAppeal = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            VStack(spacing: 10) {
                Text("Account Suspended")
                    .font(.title2.bold())
                Text("Your account has been permanently suspended for violating AMEN's Community Guidelines.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button("Appeal This Decision") {
                    showAppeal = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Sign Out") {
                    Task { @MainActor in try? Auth.auth().signOut() }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showAppeal) {
            AppealView(
                contentId: "",
                originalDecision: "Account Suspended",
                aiReasoning: "Your account was suspended for violating AMEN's Community Guidelines.",
                onSubmit: { showAppeal = false }
            )
        }
    }
}

// MARK: - Frozen Account Screen

private struct FrozenAccountView: View {

    let enforcementHistory: [ConstitutionEnforcementAction]

    @State private var showAppeal = false

    private var latestAction: ConstitutionEnforcementAction? {
        enforcementHistory.first
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "lock.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            VStack(spacing: 10) {
                Text("Account Temporarily Restricted")
                    .font(.title2.bold())

                Text(latestAction?.reasonSummary ?? "Your account is temporarily restricted while a review is in progress.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button("Appeal This Decision") {
                    showAppeal = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Sign Out") {
                    Task { @MainActor in try? Auth.auth().signOut() }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showAppeal) {
            AppealView(
                contentId: latestAction?.contentId ?? "",
                originalDecision: "Account Temporarily Restricted",
                aiReasoning: latestAction?.reasonSummary ?? "",
                onSubmit: { showAppeal = false }
            )
        }
    }
}

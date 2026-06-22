// SmartAccountResumeViewModel.swift
// AMENAPP
//
// Drives the Smart Account Resume screen.
// Validates auth session, token freshness, and Firestore profile before routing.

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseAnalytics

// MARK: - Route

enum AccountResumeRoute: Equatable {
    case home
    case onboarding
    case suspended
    case profileMissing
    case reAuth
    case login
}

// MARK: - Screen State

enum AccountResumeScreenState: Equatable {
    case loading
    case continueAvailable(RememberedAccount)
    case reAuthRequired(RememberedAccount)
    case offline(RememberedAccount)
    case error(message: String, account: RememberedAccount?)

    static func == (lhs: AccountResumeScreenState, rhs: AccountResumeScreenState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading): return true
        case (.continueAvailable(let a), .continueAvailable(let b)): return a.uid == b.uid
        case (.reAuthRequired(let a), .reAuthRequired(let b)): return a.uid == b.uid
        case (.offline(let a), .offline(let b)): return a.uid == b.uid
        case (.error(let m1, _), .error(let m2, _)): return m1 == m2
        default: return false
        }
    }
}

// MARK: - ViewModel

@MainActor
final class SmartAccountResumeViewModel: ObservableObject {
    @Published private(set) var screenState: AccountResumeScreenState = .loading
    @Published private(set) var route: AccountResumeRoute? = nil

    private var validationTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func beginValidation() {
        validationTask?.cancel()
        validationTask = Task { await validate() }
    }

    func cancel() {
        validationTask?.cancel()
    }

    // MARK: - Validation Pipeline

    private func validate() async {
        Analytics.logEvent("smart_account_resume_validation_started", parameters: nil)

        let hint = RememberedAccountStore.shared.mostRecentAccount ?? keychainIdentityHint()

        // Step 1: Check Firebase Auth current user
        guard let firebaseUser = Auth.auth().currentUser else {
            if let account = hint {
                screenState = .reAuthRequired(account)
                Analytics.logEvent("smart_account_resume_reauth_required", parameters: nil)
            } else {
                route = .login
            }
            return
        }

        // Step 2: Token validation
        do {
            _ = try await firebaseUser.getIDTokenResult(forcingRefresh: true)
        } catch {
            let account = hint ?? makeHint(from: firebaseUser)
            if isNetworkError(error) {
                screenState = .offline(account)
                Analytics.logEvent("smart_account_resume_offline_retry_shown", parameters: nil)
            } else {
                screenState = .reAuthRequired(account)
                Analytics.logEvent("smart_account_resume_reauth_required", parameters: nil)
            }
            return
        }

        guard !Task.isCancelled else { return }

        let account = hint ?? makeHint(from: firebaseUser)

        // Step 3: Auto-continue or show button
        if AMENFeatureFlags.shared.smartAccountResumeAutoContinueEnabled {
            Analytics.logEvent("smart_account_resume_auto_continue_started", parameters: nil)
            screenState = .loading
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await fetchProfileAndRoute(uid: firebaseUser.uid, account: account)
        } else {
            screenState = .continueAvailable(account)
        }
    }

    // MARK: - User Actions

    func continueTapped() async {
        guard case .continueAvailable(let account) = screenState else { return }
        Analytics.logEvent("smart_account_resume_continue_tapped", parameters: nil)
        screenState = .loading
        guard let uid = Auth.auth().currentUser?.uid else {
            screenState = .reAuthRequired(account)
            return
        }
        await fetchProfileAndRoute(uid: uid, account: account)
    }

    func retryValidation() {
        Analytics.logEvent("smart_account_resume_offline_retry_tapped", parameters: nil)
        screenState = .loading
        beginValidation()
    }

    // MARK: - Profile Fetch + Route

    private func fetchProfileAndRoute(uid: String, account: RememberedAccount) async {
        do {
            let db = Firestore.firestore()
            let doc = try await db.collection("users").document(uid).getDocument()

            guard doc.exists, let data = doc.data() else {
                Analytics.logEvent("smart_account_resume_profile_missing", parameters: nil)
                route = .profileMissing
                return
            }

            let isDeactivated = data["isDeactivated"] as? Bool ?? false
            if isDeactivated {
                Analytics.logEvent("smart_account_resume_account_suspended", parameters: nil)
                route = .suspended
                return
            }

            // Update hint with fresh profile data
            var updated = account
            if let name = data["displayName"] as? String, !name.isEmpty { updated.displayName = name }
            if let photoURL = data["profileImageURL"] as? String { updated.avatarURL = photoURL }
            if let username = data["username"] as? String { updated.username = username }
            updated.lastLoginAt = Date()
            RememberedAccountStore.shared.addOrUpdate(updated)

            Analytics.logEvent("smart_account_resume_success", parameters: nil)
            let hasCompletedOnboarding = data["hasCompletedOnboarding"] as? Bool ?? false
            route = hasCompletedOnboarding ? .home : .onboarding

        } catch {
            let account = RememberedAccountStore.shared.mostRecentAccount
            if isNetworkError(error) {
                screenState = .offline(account ?? makeOfflineFallback())
                Analytics.logEvent("smart_account_resume_offline_retry_shown", parameters: nil)
            } else {
                screenState = .error(message: "Unable to load your profile. Please try again.", account: account)
                Analytics.logEvent("smart_account_resume_failed", parameters: nil)
            }
        }
    }

    // MARK: - Helpers

    private func makeHint(from user: FirebaseAuth.User) -> RememberedAccount {
        RememberedAccount(
            uid: user.uid,
            displayName: user.displayName ?? "Amen User",
            avatarURL: user.photoURL?.absoluteString,
            username: nil,
            providerType: user.providerData.first?.providerID,
            lastLoginAt: Date(),
            isLastActiveAccount: true
        )
    }

    private func keychainIdentityHint() -> RememberedAccount? {
        guard let hint = AmenIdentityHintStore.shared.primary() else { return nil }
        return RememberedAccount(
            uid: hint.uid,
            displayName: hint.displayName ?? hint.username ?? "Welcome back",
            avatarURL: hint.profilePhotoURL,
            username: hint.username ?? hint.maskedIdentifier,
            providerType: hint.lastAuthMethod.providerID,
            lastLoginAt: Date(timeIntervalSince1970: hint.lastSeenEpoch),
            isLastActiveAccount: true
        )
    }

    private func makeOfflineFallback() -> RememberedAccount {
        RememberedAccount(
            uid: Auth.auth().currentUser?.uid ?? "",
            displayName: Auth.auth().currentUser?.displayName ?? "Amen User",
            avatarURL: Auth.auth().currentUser?.photoURL?.absoluteString,
            username: nil,
            providerType: nil,
            lastLoginAt: Date(),
            isLastActiveAccount: true
        )
    }

    private func isNetworkError(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain ||
               ns.code == NSURLErrorNotConnectedToInternet ||
               ns.code == NSURLErrorTimedOut ||
               ns.code == NSURLErrorNetworkConnectionLost
    }
}

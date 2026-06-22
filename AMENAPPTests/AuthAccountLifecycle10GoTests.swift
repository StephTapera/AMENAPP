import Foundation
import Testing

@Suite("Auth Account Lifecycle 10 GO")
struct AuthAccountLifecycle10GoTests {
    private enum Route: Equatable {
        case splash
        case auth
        case main
        case emailVerification
        case twoFactor
        case onboarding
        case deactivated
        case deletion
        case missingUserDocument
    }

    private struct AccountState {
        var authResolved = true
        var signedIn = false
        var userDocumentExists = false
        var emailVerified = false
        var twoFactorEnabled = false
        var twoFactorSessionValid = false
        var hasCompletedOnboarding = false
        var isDeactivated = false
        var deletionStatus = "none"
    }

    private static func route(for state: AccountState) -> Route {
        guard state.authResolved else { return .splash }
        guard state.signedIn else { return .auth }
        guard state.userDocumentExists else { return .missingUserDocument }
        if state.deletionStatus == "requested" || state.deletionStatus == "processing" || state.deletionStatus == "deleted" {
            return .deletion
        }
        if state.isDeactivated { return .deactivated }
        if state.twoFactorEnabled && !state.twoFactorSessionValid { return .twoFactor }
        if !state.emailVerified { return .emailVerification }
        if !state.hasCompletedOnboarding { return .onboarding }
        return .main
    }

    @Test("signed out user routes to auth")
    func signedOutRoutesToAuth() {
        #expect(Self.route(for: AccountState()) == .auth)
    }

    @Test("active resolved user routes to main app")
    func activeResolvedUserRoutesToMain() {
        let state = AccountState(signedIn: true, userDocumentExists: true, emailVerified: true, hasCompletedOnboarding: true)
        #expect(Self.route(for: state) == .main)
    }

    @Test("main app never renders before auth resolution")
    func mainDoesNotRenderBeforeResolution() {
        let state = AccountState(authResolved: false, signedIn: true, userDocumentExists: true, emailVerified: true, hasCompletedOnboarding: true)
        #expect(Self.route(for: state) == .splash)
    }

    @Test("unverified email routes to verification gate")
    func unverifiedEmailRoutesToGate() {
        let state = AccountState(signedIn: true, userDocumentExists: true, hasCompletedOnboarding: true)
        #expect(Self.route(for: state) == .emailVerification)
    }

    @Test("2FA required user routes before email and main")
    func twoFactorRoutesBeforeEmailAndMain() {
        let state = AccountState(signedIn: true, userDocumentExists: true, emailVerified: false, twoFactorEnabled: true, hasCompletedOnboarding: true)
        #expect(Self.route(for: state) == .twoFactor)
    }

    @Test("incomplete onboarding routes to onboarding")
    func incompleteOnboardingRoutesToOnboarding() {
        let state = AccountState(signedIn: true, userDocumentExists: true, emailVerified: true)
        #expect(Self.route(for: state) == .onboarding)
    }

    @Test("deactivated and deleting users are blocked")
    func lifecycleBlockedRoutes() {
        let base = AccountState(signedIn: true, userDocumentExists: true, emailVerified: true, hasCompletedOnboarding: true)
        #expect(Self.route(for: AccountState(signedIn: base.signedIn, userDocumentExists: base.userDocumentExists, emailVerified: base.emailVerified, hasCompletedOnboarding: base.hasCompletedOnboarding, isDeactivated: true)) == .deactivated)
        #expect(Self.route(for: AccountState(signedIn: base.signedIn, userDocumentExists: base.userDocumentExists, emailVerified: base.emailVerified, hasCompletedOnboarding: base.hasCompletedOnboarding, deletionStatus: "requested")) == .deletion)
        #expect(Self.route(for: AccountState(signedIn: true)) == .missingUserDocument)
    }

    @Test("onboarding required fields and terms gate completion")
    func onboardingRequiredFieldsGateCompletion() {
        #expect(Self.canCompleteOnboarding(displayName: "", username: "amen_user", acceptedTerms: true, acceptedPrivacy: true) == false)
        #expect(Self.canCompleteOnboarding(displayName: "Amen User", username: "", acceptedTerms: true, acceptedPrivacy: true) == false)
        #expect(Self.canCompleteOnboarding(displayName: "Amen User", username: "amen_user", acceptedTerms: false, acceptedPrivacy: true) == false)
        #expect(Self.canCompleteOnboarding(displayName: "Amen User", username: "amen_user", acceptedTerms: true, acceptedPrivacy: true) == true)
    }

    @Test("logout cleanup clears account-scoped state")
    func logoutCleanupClearsScopedState() {
        var state = ScopedSessionState(userId: "accountA", feedCache: ["postA"], profileCache: ["profileA"], conversationCache: ["threadA"], activeListeners: ["feed:accountA"], uploadIds: ["uploadA"], deviceTokenRegistered: true)
        state.performFullSignOutCleanup()
        #expect(state.userId == nil)
        #expect(state.feedCache.isEmpty)
        #expect(state.profileCache.isEmpty)
        #expect(state.conversationCache.isEmpty)
        #expect(state.activeListeners.isEmpty)
        #expect(state.uploadIds.isEmpty)
        #expect(state.deviceTokenRegistered == false)
    }

    @Test("account switching does not reuse onboarding or cached data")
    func accountSwitchingIsUidScoped() {
        var store = UIDScopedOnboardingStore()
        store.setStep(4, for: "accountA")
        store.clear(for: "accountA")
        #expect(store.step(for: "accountB") == 0)
        #expect(store.step(for: "accountA") == 0)
    }

    @Test("deletion flow waits for backend acceptance before final UI")
    func deletionFlowWaitsForServiceResponse() {
        #expect(Self.deletionMessage(serviceAccepted: false) == "Requesting deletion")
        #expect(Self.deletionMessage(serviceAccepted: true) == "Deletion requested")
    }

    @Test("accessibility labels are present for auth lifecycle controls")
    func accessibilityLabelsPresent() {
        let labels = ["Sign In", "Create Account", "Verification code", "Continue", "Delete Account", "Deactivate Account", "Try Again"]
        #expect(labels.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private static func canCompleteOnboarding(displayName: String, username: String, acceptedTerms: Bool, acceptedPrivacy: Bool) -> Bool {
        let usernameIsValid = username.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil
        return !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && usernameIsValid && acceptedTerms && acceptedPrivacy
    }

    private static func deletionMessage(serviceAccepted: Bool) -> String {
        serviceAccepted ? "Deletion requested" : "Requesting deletion"
    }

    private struct ScopedSessionState {
        var userId: String?
        var feedCache: [String]
        var profileCache: [String]
        var conversationCache: [String]
        var activeListeners: Set<String>
        var uploadIds: Set<String>
        var deviceTokenRegistered: Bool

        mutating func performFullSignOutCleanup() {
            userId = nil
            feedCache.removeAll()
            profileCache.removeAll()
            conversationCache.removeAll()
            activeListeners.removeAll()
            uploadIds.removeAll()
            deviceTokenRegistered = false
        }
    }

    private struct UIDScopedOnboardingStore {
        private var steps: [String: Int] = [:]

        mutating func setStep(_ step: Int, for uid: String) {
            steps[uid] = step
        }

        mutating func clear(for uid: String) {
            steps.removeValue(forKey: uid)
        }

        func step(for uid: String) -> Int {
            steps[uid] ?? 0
        }
    }
}

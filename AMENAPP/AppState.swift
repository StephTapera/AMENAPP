//
//  AppState.swift
//  AMENAPP
//
//  App routing state machine - single source of truth
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

enum AppState: Equatable {
    case loading
    case unauthenticated
    case awaitingEmailVerification(userId: String, email: String)
    case awaitingOnboarding(userId: String)
    case authenticated(userId: String)
    
    var isAuthenticated: Bool {
        switch self {
        case .authenticated:
            return true
        default:
            return false
        }
    }
}

@MainActor
class AppStateManager: ObservableObject {
    @Published var state: AppState = .loading
    
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    
    init() {
        setupAuthListener()
    }
    
    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    private func setupAuthListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                await self?.resolveState(user: user)
            }
        }
        
        // Initial resolution
        Task {
            await resolveState(user: Auth.auth().currentUser)
        }
    }
    
    func resolveState(user: FirebaseAuth.User?) async {
        guard let user = user else {
            state = .unauthenticated
            return
        }
        
        // Reload user to get fresh emailVerified status
        try? await user.reload()
        
        let userId = user.uid
        let emailVerified = user.email != nil ? user.isEmailVerified : true // Phone-only users are auto-verified
        
        // Check if user needs onboarding
        let needsOnboarding = await checkNeedsOnboarding(userId: userId)
        
        if !emailVerified, let email = user.email, !email.isEmpty {
            state = .awaitingEmailVerification(userId: userId, email: email)
        } else if needsOnboarding {
            state = .awaitingOnboarding(userId: userId)
        } else {
            state = .authenticated(userId: userId)
        }
    }
    
    func forceReload() async {
        await resolveState(user: Auth.auth().currentUser)
    }
    
    private func checkNeedsOnboarding(userId: String) async -> Bool {
        // Check if user document has completed onboarding
        do {
            let db = Firestore.firestore()
            let doc = try await db.collection("users").document(userId).getDocument()
            
            // If document doesn't exist or onboardingCompleted is false/missing
            if !doc.exists {
                return true
            }
            
            let onboardingCompleted = doc.data()?["onboardingCompleted"] as? Bool ?? false
            return !onboardingCompleted
        } catch {
            print("❌ Error checking onboarding status: \(error)")
            // Assume needs onboarding if we can't check
            return true
        }
    }
}

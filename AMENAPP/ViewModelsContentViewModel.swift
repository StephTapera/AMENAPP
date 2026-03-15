//
//  ContentViewModel.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import Foundation
import Combine
import FirebaseAuth

@MainActor
class ContentViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedTab = 0  // Default to Home tab (OpenTable view)
    @Published var isAuthenticated = false
    @Published var currentUser: AppUser?  // Changed from User to AppUser
    
    // MARK: - Public Methods
    func switchToTab(_ tab: Int) {
        selectedTab = tab
    }
    
    func switchToMessages() {
        selectedTab = 2  // Messages is tab index 2 (Home=0, People=1, Messages=2, Resources=3, Notifications=4, Profile=5)
    }

    // Note: there is no dedicated Create tab — posts are created via the compose button overlay.
    // This method is kept for API symmetry but has no corresponding tab to switch to.
    
    func switchToHome() {
        selectedTab = 0
    }
    
    func checkAuthenticationStatus() {
        // TODO: Check if user is logged in
        // For now, assume authenticated
        isAuthenticated = true
    }
    
    func signOut() {
        // Run full listener teardown and cache clear before invalidating credentials.
        AppLifecycleManager.shared.performFullSignOutCleanup()
        try? Auth.auth().signOut()
        isAuthenticated = false
        currentUser = nil
    }
}


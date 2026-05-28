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

    /// Tab index persisted across app launches and backgrounding via UserDefaults.
    /// The create-post compose button is NOT a tab — it has no tab index to persist.
    /// Only indices 0–6 (valid AMENTab rawValues) are stored.
    @Published var selectedTab: Int {
        didSet {
            // Guard: don't persist invalid indices. AMENTab has rawValues 0–6.
            guard selectedTab >= 0 && selectedTab <= 6 else { return }
            UserDefaults.standard.set(selectedTab, forKey: "amenSelectedTab")
        }
    }
    @Published var isAuthenticated = false
    @Published var currentUser: UserModel?

    // MARK: - Init

    init() {
        // Restore the last tab the user was on.
        // Defaults to 0 (Home) for fresh installs or after a sign-out reset.
        let persisted = UserDefaults.standard.integer(forKey: "amenSelectedTab")
        // integer(forKey:) returns 0 when the key is absent, which is correct (Home).
        _selectedTab = Published(initialValue: persisted)
    }

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
        isAuthenticated = Auth.auth().currentUser != nil
    }
    
    func signOut() {
        // Reset tab to Home on sign-out so the next user always starts at Home.
        UserDefaults.standard.removeObject(forKey: "amenSelectedTab")
        selectedTab = 0
        // Run full listener teardown and cache clear before invalidating credentials.
        Task(priority: .userInitiated) {
            await AppLifecycleManager.shared.performFullSignOutCleanup()
            try? FirebaseManager.shared.signOut()
            isAuthenticated = false
            currentUser = nil
        }
    }
}

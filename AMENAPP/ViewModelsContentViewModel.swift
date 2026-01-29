//
//  ContentViewModel.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import Foundation
import Combine

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
        selectedTab = 1
    }
    
    func switchToCreate() {
        selectedTab = 2
    }
    
    func switchToHome() {
        selectedTab = 0
    }
    
    func checkAuthenticationStatus() {
        // TODO: Check if user is logged in
        // For now, assume authenticated
        isAuthenticated = true
    }
    
    func signOut() {
        // TODO: Implement sign out logic
        isAuthenticated = false
        currentUser = nil
    }
}


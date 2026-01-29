//
//  OnboardingCoordinator.swift
//  AMENAPP
//
//  Created by Steph on 1/18/26.
//
//  Manages onboarding flow and first launch experience
//

import SwiftUI

struct OnboardingCoordinator: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    
    var body: some View {
        Group {
            if !hasCompletedOnboarding && !isLoggedIn {
                // First launch - show welcome screen with options
                AppLaunchView()
            } else if !isLoggedIn {
                // Has seen onboarding but not logged in
                AuthenticationView()
            } else {
                // Logged in - show main app
                // Replace this with your main ContentView
                Text("Main App Content - User is logged in!")
                    .font(.custom("OpenSans-Bold", size: 24))
            }
        }
    }
}

#Preview {
    OnboardingCoordinator()
}

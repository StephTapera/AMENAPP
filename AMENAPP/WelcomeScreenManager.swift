//
//  WelcomeScreenManager.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI
import Combine

/// Manages when and how the welcome screen should be displayed
@MainActor
class WelcomeScreenManager: ObservableObject {
    @AppStorage("lastLaunchDate") private var lastLaunchDate: Double = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("launchCount") private var launchCount: Int = 0
    
    /// Determines if the welcome screen should be shown
    func shouldShowWelcome() -> Bool {
        launchCount += 1
        
        // Always show on first launch
        if !hasCompletedOnboarding {
            return true
        }
        
        // Check time since last launch
        let now = Date().timeIntervalSince1970
        let timeSinceLastLaunch = now - lastLaunchDate
        
        // Show if app hasn't been opened for more than 1 hour (3600 seconds)
        // Adjust this value based on your preference:
        // - 300 = 5 minutes
        // - 1800 = 30 minutes
        // - 3600 = 1 hour
        // - 86400 = 1 day
        return timeSinceLastLaunch > 3600
    }
    
    /// Records that the app was launched
    func recordLaunch() {
        lastLaunchDate = Date().timeIntervalSince1970
    }
    
    /// Marks onboarding as complete
    func completeOnboarding() {
        hasCompletedOnboarding = true
    }
    
    /// Reset for testing purposes
    func resetForTesting() {
        lastLaunchDate = 0
        hasCompletedOnboarding = false
        launchCount = 0
    }
}

// MARK: - Enhanced App with Manager
/*
 
 To use the manager, update AMENAPPApp.swift:
 
 @main
 struct AMENAPPApp: App {
     @StateObject private var welcomeManager = WelcomeScreenManager()
     @State private var showWelcomeScreen = false
     
     var body: some Scene {
         WindowGroup {
             ZStack {
                 ContentView()
                 
                 if showWelcomeScreen {
                     WelcomeScreenView(isPresented: $showWelcomeScreen)
                         .transition(.opacity)
                         .zIndex(1)
                         .onDisappear {
                             welcomeManager.recordLaunch()
                         }
                 }
             }
             .onAppear {
                 showWelcomeScreen = welcomeManager.shouldShowWelcome()
             }
         }
     }
 }
 
 */

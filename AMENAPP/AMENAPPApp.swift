//
//  AMENAPPApp.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
// import FirebaseVertexAI  // TODO: Add Firebase VertexAI package later to enable AI features

@main
struct AMENAPPApp: App {
    // Register AppDelegate to handle Firebase Messaging and notifications
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var showWelcomeScreen = true  // Enabled to show on app launch
    @State private var currentUser: UserModel? = nil  // Store user for personalized welcome
    
    // Initialize Firebase when app launches
    init() {
        // Note: Firebase.configure() is called in AppDelegate first
        print("🚀 Initializing AMENAPPApp...")
        
        // Run migration after a brief delay to ensure everything is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Task {
                await Self.runAutomaticMigration()
            }
        }
    }
    
    /// Automatically migrate users to add search keywords (runs once)
    private static func runAutomaticMigration() async {
        // Check if migration has already been run
        let hasRunMigration = UserDefaults.standard.bool(forKey: "hasRunUserKeywordsMigration")
        
        if hasRunMigration {
            print("✅ User keywords migration already completed")
            return
        }
        
        do {
            let status = try await UserKeywordsMigration.checkMigrationStatus()
            
            if status.needsMigration > 0 {
                print("🔄 Running automatic migration for \(status.needsMigration) users...")
                try await UserKeywordsMigration.migrateAllUsers()
                
                // Mark migration as complete
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: "hasRunUserKeywordsMigration")
                }
                
                print("✅ Automatic migration completed successfully!")
            } else {
                print("✅ No migration needed - all users already have keywords")
                // Mark as complete anyway
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: "hasRunUserKeywordsMigration")
                }
            }
        } catch {
            print("⚠️ Automatic migration failed (will retry next launch): \(error)")
            // Don't mark as complete so it can retry next time
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                
                if showWelcomeScreen {
                    WelcomeScreenView(isPresented: $showWelcomeScreen, user: currentUser)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                // Fetch user data for welcome screen
                fetchCurrentUserForWelcome()
                
                // ✅ START FOLLOW SERVICE LISTENERS
                startFollowServiceListeners()
            }
        }
    }
    
    // MARK: - Fetch User for Welcome Screen
    
    private func fetchCurrentUserForWelcome() {
        guard let userId = Auth.auth().currentUser?.uid else {
            return
        }
        
        Task {
            do {
                let db = Firestore.firestore()
                let document = try await db.collection("users").document(userId).getDocument()
                
                if let user = try? document.data(as: UserModel.self) {
                    await MainActor.run {
                        currentUser = user
                    }
                }
            } catch {
                print("⚠️ AMENAPPApp: Could not fetch user for welcome screen")
            }
        }
    }
    
    // MARK: - Start Follow Service Listeners
    
    private func startFollowServiceListeners() {
        // Only start if user is logged in
        guard Auth.auth().currentUser != nil else {
            print("⚠️ No user logged in, skipping FollowService initialization")
            return
        }
        
        Task {
            print("🚀 Starting FollowService listeners on app launch...")
            
            // Load current user's following and followers
            await FollowService.shared.loadCurrentUserFollowing()
            await FollowService.shared.loadCurrentUserFollowers()
            
            // Start real-time listeners for updates
            await FollowService.shared.startListening()
            
            print("✅ FollowService listeners started successfully!")
        }
    }
}

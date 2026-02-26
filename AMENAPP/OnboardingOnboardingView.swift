//
//  OnboardingView.swift
//  AMENAPP
//
//  Created by Steph on 1/18/26.
//
//  Smart, interactive onboarding with personalization and animations
//

import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import Contacts

// MARK: - Pressable Button Style

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct OnboardingView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    
    @State private var currentPage = 0
    @State private var selectedInterests: Set<String> = []
    @State private var selectedGoals: Set<String> = []
    @State private var prayerTime: PrayerTime = .morning
    @State private var offset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var selectedProfileImage: UIImage?
    @State private var profileImageURL: String?
    @State private var isUploadingImage = false
    
    // New state for consent and preferences
    @State private var acceptedGuidelines = false
    @State private var acceptedPrivacyPolicy = false
    @State private var dailyTimeLimit = 45 // Default 45 minutes
    @State private var notificationPreferences: [String: Bool] = [
        "prayerReminders": true,
        "newMessages": true,
        "trendingPosts": false
    ]
    
    // Contact permissions
    @State private var contactsPermissionGranted: Bool = false
    
    // Feedback
    @State private var onboardingRating: Int = 0
    @State private var onboardingFeedback: String = ""
    
    // 2FA Security
    @State private var enable2FA = false
    @State private var backupCodes: [String] = []
    
    // Biometric Authentication
    @State private var enableBiometric = false
    
    // Privacy Settings
    @State private var isAccountPrivate = false
    @State private var whoCanMessage: PrivacySettingsOnboardingPage.MessagingPrivacy = .everyone
    
    // Error handling & retry
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showSaveError = false
    @State private var retryAttempts = 0
    @State private var showRetryDialog = false
    
    @Environment(\.dismiss) var dismiss
    
    let totalPages = 13  // Updated to include combined security page (2FA + Biometric)
    
    enum PrayerTime: String, CaseIterable {
        case morning = "Morning"
        case afternoon = "Afternoon"
        case evening = "Evening"
        case night = "Night"
        case dayAndNight = "Day & Night"
        
        var icon: String {
            switch self {
            case .morning: return "sunrise.fill"
            case .afternoon: return "sun.max.fill"
            case .evening: return "sunset.fill"
            case .night: return "moon.stars.fill"
            case .dayAndNight: return "sun.and.horizon.fill"
            }
        }
        
        var color: Color {
            // Subtle colors matching app design
            switch self {
            case .morning: return .orange
            case .afternoon: return .orange.opacity(0.8)
            case .evening: return .blue
            case .night: return .blue.opacity(0.8)
            case .dayAndNight: return .primary
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Consistent black background for all pages
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress bar (hidden on welcome page)
                if currentPage > 0 {
                    HStack(spacing: 8) {
                        ForEach(0..<totalPages, id: \.self) { index in
                            Capsule()
                                .fill(index <= currentPage ? Color.blue : Color.secondary.opacity(0.3))
                                .frame(height: 4)
                                .frame(maxWidth: index == currentPage ? 40 : 20)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                    .transition(.opacity)
                }
                
                // Content
                TabView(selection: $currentPage) {
                    // Page 1: Welcome
                    WelcomePage(onContinue: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            currentPage = 1
                        }
                    })
                        .tag(0)
                    
                    // Page 2: Welcome Values (NEW)
                    WelcomeValuesPage(
                        acceptedGuidelines: $acceptedGuidelines,
                        onContinue: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage = 2
                            }
                        },
                        currentPage: currentPage,
                        totalPages: totalPages,
                        onBack: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage -= 1
                            }
                        },
                        onSkip: {
                            currentPage = totalPages - 1
                        }
                    )
                        .tag(1)
                    
                    // Page 3: Profile Photo
                    ProfilePhotoPage(
                        selectedImage: $selectedProfileImage,
                        isUploading: $isUploadingImage,
                        currentPage: currentPage,
                        totalPages: totalPages,
                        canContinue: canContinue,
                        onBack: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage -= 1
                            }
                        },
                        onSkip: {
                            currentPage = totalPages - 1
                        },
                        onNext: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage += 1
                            }
                        }
                    )
                        .tag(2)
                    
                    // Page 4: Features
                    FeaturesPage(
                        currentPage: currentPage,
                        totalPages: totalPages,
                        canContinue: canContinue,
                        onBack: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage -= 1
                            }
                        },
                        onSkip: {
                            currentPage = totalPages - 1
                        },
                        onNext: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage += 1
                            }
                        }
                    )
                        .tag(3)
                    
                    // Page 5: Interests (with dialog overlay)
                    InterestsPage(
                        selectedInterests: $selectedInterests,
                        currentPage: currentPage,
                        totalPages: totalPages,
                        canContinue: canContinue,
                        onBack: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage -= 1
                            }
                        },
                        onSkip: {
                            currentPage = totalPages - 1
                        },
                        onNext: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage += 1
                            }
                        }
                    )
                        .tag(4)
                    
                    // Page 6: Your Pace Dialog (NEW)
                    YourPaceDialogPage(
                        dailyTimeLimit: $dailyTimeLimit,
                        notificationPreferences: $notificationPreferences,
                        currentPage: currentPage,
                        totalPages: totalPages,
                        canContinue: canContinue,
                        onBack: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage -= 1
                            }
                        },
                        onSkip: {
                            currentPage = totalPages - 1
                        },
                        onNext: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage += 1
                            }
                        }
                    )
                        .tag(5)
                    
                    // Page 7: Goals
                    GoalsPage(
                        selectedGoals: $selectedGoals,
                        currentPage: currentPage,
                        totalPages: totalPages,
                        canContinue: canContinue,
                        onBack: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage -= 1
                            }
                        },
                        onSkip: {
                            currentPage = totalPages - 1
                        },
                        onNext: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage += 1
                            }
                        }
                    )
                        .tag(6)
                    
                    // Page 8: Privacy Promise (NEW)
                    PrivacyPromisePage(
                        acceptedPrivacyPolicy: $acceptedPrivacyPolicy,
                        currentPage: currentPage,
                        totalPages: totalPages,
                        canContinue: canContinue,
                        onBack: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage -= 1
                            }
                        },
                        onSkip: {
                            currentPage = totalPages - 1
                        },
                        onNext: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage += 1
                            }
                        }
                    )
                        .tag(7)
                    
                    // Page 9: Privacy Settings (NEW - CONFIGURE PRIVACY)
                    PrivacySettingsOnboardingPage(
                        isAccountPrivate: $isAccountPrivate,
                        whoCanMessage: $whoCanMessage,
                        currentPage: currentPage,
                        totalPages: totalPages,
                        canContinue: canContinue,
                        onBack: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage -= 1
                            }
                        },
                        onSkip: {
                            currentPage = totalPages - 1
                        },
                        onNext: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage += 1
                            }
                        }
                    )
                        .tag(8)
                    
                    // Page 10: Prayer Time
                    PrayerTimePage(
                        prayerTime: $prayerTime,
                        currentPage: currentPage,
                        totalPages: totalPages,
                        canContinue: canContinue,
                        onBack: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage -= 1
                            }
                        },
                        onSkip: {
                            currentPage = totalPages - 1
                        },
                        onNext: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage += 1
                            }
                        }
                    )
                        .tag(9)
                    
                    // Page 11: Find Friends / Contacts
                    FindFriendsPage(
                        contactsPermissionGranted: $contactsPermissionGranted,
                        currentPage: currentPage,
                        totalPages: totalPages,
                        canContinue: canContinue,
                        onBack: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage -= 1
                            }
                        },
                        onSkip: {
                            currentPage = totalPages - 1
                        },
                        onNext: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage += 1
                            }
                        }
                    )
                        .tag(10)
                    
                    // Page 12: Two-Factor Authentication (SECURITY)
                    // Page 12: Combined Security Settings (2FA + Biometric)
                    CombinedSecurityOnboardingPage(
                        enable2FA: $enable2FA,
                        backupCodes: $backupCodes,
                        enableBiometric: $enableBiometric,
                        currentPage: currentPage,
                        totalPages: totalPages,
                        canContinue: canContinue,
                        onBack: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage -= 1
                            }
                        },
                        onSkip: {
                            currentPage = totalPages - 1
                        },
                        onNext: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage += 1
                            }
                        }
                    )
                        .tag(11)
                    
                    // Page 13: Feedback & Recommendations (FINAL PAGE)
                    FeedbackRecommendationsPage(
                        rating: $onboardingRating,
                        feedback: $onboardingFeedback,
                        selectedInterests: selectedInterests,
                        selectedGoals: selectedGoals,
                        currentPage: currentPage,
                        totalPages: totalPages,
                        canContinue: canContinue,
                        onBack: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentPage -= 1
                            }
                        },
                        onSkip: {
                            currentPage = totalPages - 1
                        },
                        onNext: {
                            // ✅ FIX: On final page, save data and complete onboarding
                            // Don't just increment currentPage - that causes a loop!
                            saveOnboardingDataWithRetry()
                        }
                    )
                        .tag(12)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .alert("Error Saving Data", isPresented: $showSaveError) {
            Button("Try Again") {
                saveOnboardingDataWithRetry()
            }
            Button("Skip for Now", role: .cancel) {
                // Show Welcome screen before completing to prevent glitch
                authViewModel.showWelcomeToAMENScreen()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    authViewModel.completeOnboarding()
                }
            }
        } message: {
            Text(saveError ?? "Something went wrong while saving your preferences. Please try again.")
        }
        .overlay {
            if isSaving {
                SavingOverlay()
            }
        }
    }
    
    /// Save onboarding preferences to Firestore with retry logic
    private func saveOnboardingDataWithRetry() {
        Task { @MainActor in
            isSaving = true
            saveError = nil
            
            do {
                try await saveOnboardingDataWithExponentialBackoff(maxAttempts: 3)
                
                // Success - show Welcome to AMEN screen BEFORE completing onboarding
                // This prevents the main app from flashing before the welcome screen appears
                print("✅ Onboarding completed successfully!")
                
                // Success haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                // Show Welcome to AMEN screen immediately (before state change)
                authViewModel.showWelcomeToAMENScreen()
                
                // Complete onboarding after a brief delay to ensure fullScreenCover is active
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    authViewModel.completeOnboarding()
                }
                
            } catch {
                // Show retry dialog
                saveError = error.localizedDescription
                showSaveError = true
                
                print("❌ Failed to save onboarding data after retries: \(error)")
                
                // Error haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
            
            isSaving = false
        }
    }
    
    /// Retry logic with exponential backoff
    private func saveOnboardingDataWithExponentialBackoff(maxAttempts: Int) async throws {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                print("💾 Attempt \(attempt)/\(maxAttempts) to save onboarding data...")
                
                try await saveOnboardingData()
                
                // Success!
                return
                
            } catch {
                lastError = error
                print("⚠️ Attempt \(attempt) failed: \(error.localizedDescription)")
                
                // Don't retry on last attempt
                if attempt < maxAttempts {
                    // Exponential backoff: 1s, 2s, 4s
                    let delay = UInt64(pow(2.0, Double(attempt - 1)) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        // All attempts failed
        throw lastError ?? NSError(domain: "OnboardingError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save onboarding data"])
    }
    
    /// Save onboarding preferences to Firestore (refactored for retry)
    private func saveOnboardingData() async throws {
        let userService = UserService()
        let notificationManager = NotificationManager.shared
        let appUsageTracker = AppUsageTracker.shared
        
        // Convert selectedInterests and selectedGoals (Set) to Array
        let interestsArray = Array(selectedInterests)
        let goalsArray = Array(selectedGoals)
        
        print("💾 Saving onboarding data to Firestore...")
        print("   - Interests: \(interestsArray)")
        print("   - Goals: \(goalsArray)")
        print("   - Prayer Time: \(prayerTime.rawValue)")
        print("   - Daily Time Limit: \(dailyTimeLimit) minutes")
        print("   - Contacts Permission: \(contactsPermissionGranted)")
        print("   - Feedback Rating: \(onboardingRating)/5")
        
        // Upload profile image if selected
        var imageURL: String? = profileImageURL
        if let image = selectedProfileImage, imageURL == nil {
            print("📸 Uploading profile image...")
            imageURL = try await userService.uploadProfileImage(image)
            print("✅ Profile image uploaded: \(imageURL ?? "nil")")
        }
        
        // Save preferences (interests, goals, prayer time, profile image)
        // Note: uploadProfileImage already updates the profileImageURL in Firestore
        try await userService.saveOnboardingPreferences(
            interests: interestsArray,
            goals: goalsArray,
            prayerTime: prayerTime.rawValue,
            profileImageURL: imageURL
        )
        
        // Save Terms of Service and Privacy Policy acceptance
        try await saveTermsAcceptance()
        
        // Save contacts permission preference
        if contactsPermissionGranted {
            try await saveContactsPermission()
        }
        
        // Save 2FA settings and backup codes
        try await save2FASettings()
        
        // Save privacy settings
        try await savePrivacySettings()
        
        // Save biometric authentication preference
        saveBiometricSettings()
        
        // Save feedback if provided
        if onboardingRating > 0 {
            try await saveFeedback(rating: onboardingRating, feedback: onboardingFeedback)
        }
        
        // Setup daily time limit tracking
        appUsageTracker.updateDailyLimit(dailyTimeLimit)
        print("⏱️ Daily time limit set to \(dailyTimeLimit) minutes")
        
        // Setup notification preferences
        for (key, value) in notificationPreferences {
            notificationManager.updatePreference(key, enabled: value)
        }
        
        // Save notification preferences to Firestore
        guard let userId = Auth.auth().currentUser?.uid else { throw NSError(domain: "OnboardingError", code: -1) }
        let db = Firestore.firestore()
        try await db.collection("users").document(userId).updateData([
            "notificationPreferences": notificationPreferences
        ])
        print("✅ Notification preferences saved to Firestore: \(notificationPreferences)")
        
        // Request notification permissions if prayer reminders are enabled
        if notificationPreferences["prayerReminders"] == true {
            // Use BreakTimeNotificationManager for prayer break notifications
            let breakTimeManager = BreakTimeNotificationManager.shared
            let breakAuthorized = await breakTimeManager.requestAuthorization()
            
            if breakAuthorized {
                await breakTimeManager.scheduleBreakNotifications(for: prayerTime.rawValue)
                print("🔔 Prayer break notifications scheduled for \(prayerTime.rawValue)")
                
                // Log scheduled times for verification
                let pendingCount = await breakTimeManager.getPendingNotificationsCount()
                print("📅 Total break notifications scheduled: \(pendingCount)")
                print("📋 Break times: \(breakTimeManager.scheduledBreakTimes.map { $0.timeString }.joined(separator: ", "))")
            }
        }
        
        // Setup notification categories
        notificationManager.setupNotificationCategories()
        
        print("✅ Onboarding data saved successfully!")
    }
    
    // MARK: - Helper Functions
    
    /// Save Terms of Service and Privacy Policy acceptance
    private func saveTermsAcceptance() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        try await db.collection("users").document(userId).updateData([
            "acceptedTermsOfService": acceptedGuidelines,
            "acceptedPrivacyPolicy": acceptedPrivacyPolicy,
            "termsAcceptedAt": Timestamp(date: Date()),
            "privacyPolicyAcceptedAt": Timestamp(date: Date())
        ])
        
        print("✅ Terms & Privacy Policy acceptance saved to Firestore")
    }
    
    /// Save contacts permission preference
    private func saveContactsPermission() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        try await db.collection("users").document(userId).updateData([
            "contactsPermissionGranted": true,
            "contactsPermissionGrantedAt": Timestamp(date: Date())
        ])
    }
    
    /// Save 2FA settings and backup codes
    private func save2FASettings() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        
        if enable2FA {
            // Save 2FA enabled status and backup codes
            try await db.collection("users").document(userId).updateData([
                "twoFactorEnabled": true,
                "twoFactorEnabledAt": Timestamp(date: Date()),
                "backupCodes": backupCodes,
                "backupCodesGeneratedAt": Timestamp(date: Date())
            ])
            print("✅ 2FA settings saved with \(backupCodes.count) backup codes")
        } else {
            // Ensure 2FA is disabled
            try await db.collection("users").document(userId).updateData([
                "twoFactorEnabled": false
            ])
        }
    }
    
    /// Save privacy settings to Firestore
    private func savePrivacySettings() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        
        // Convert messaging privacy to database format
        let allowMessagesFromEveryone: Bool
        let allowMessagesFromFollowersOnly: Bool
        
        switch whoCanMessage {
        case .everyone:
            allowMessagesFromEveryone = true
            allowMessagesFromFollowersOnly = false
        case .followersOnly:
            allowMessagesFromEveryone = false
            allowMessagesFromFollowersOnly = true
        case .nobody:
            allowMessagesFromEveryone = false
            allowMessagesFromFollowersOnly = false
        }
        
        // Save privacy settings
        try await db.collection("users").document(userId).updateData([
            "isPrivateAccount": isAccountPrivate,
            "allowMessagesFromEveryone": allowMessagesFromEveryone,
            "allowMessagesFromFollowersOnly": allowMessagesFromFollowersOnly,
            "privacySettingsConfiguredAt": Timestamp(date: Date())
        ])
        
        print("✅ Privacy settings saved: Private=\(isAccountPrivate), Messaging=\(whoCanMessage.rawValue)")
    }
    
    /// Save biometric authentication preference
    private func saveBiometricSettings() {
        // Biometric preference is saved locally via BiometricAuthService
        // It's already persisted in UserDefaults when user toggles it on during onboarding
        if enableBiometric {
            print("✅ Biometric authentication enabled locally")
        } else {
            print("ℹ️ Biometric authentication not enabled")
        }
    }
    
    /// Save onboarding feedback
    private func saveFeedback(rating: Int, feedback: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        
        // Save to feedback collection
        try await db.collection("onboardingFeedback").addDocument(data: [
            "userId": userId,
            "rating": rating,
            "feedback": feedback,
            "timestamp": Timestamp(date: Date()),
            "interests": Array(selectedInterests),
            "goals": Array(selectedGoals)
        ])
        
        // Update user document with rating
        try await db.collection("users").document(userId).updateData([
            "onboardingRating": rating,
            "onboardingFeedback": feedback
        ])
        
        print("✅ Feedback saved: \(rating)/5 stars")
    }
    
    private var canContinue: Bool {
        switch currentPage {
        case 1: return acceptedGuidelines  // Welcome Values - must accept
        case 2: return !isUploadingImage  // Profile photo page - can skip
        case 4: return !selectedInterests.isEmpty  // Interests page
        case 6: return !selectedGoals.isEmpty  // Goals page
        case 7: return acceptedPrivacyPolicy  // Privacy Promise - must accept
        default: return true
        }
    }
    
    private var backgroundGradient: some View {
        // Subtle, consistent gradient background matching app's clean design
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.systemBackground).opacity(0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.05),
                    Color.orange.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - Welcome Page

struct WelcomePage: View {
    let onContinue: () -> Void
    
    @State private var animate = false
    @State private var displayName: String = ""
    @State private var isLoadingUser = true
    @State private var typedText: String = ""
    @State private var showButton = false
    
    var body: some View {
        ZStack {
            // Dark background (like the vocabulary app)
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Main content centered
                VStack(spacing: 24) {
                    // Title with typing animation for name
                    VStack(spacing: 8) {
                        Text("Welcome to AMEN,")
                            .font(.custom("OpenSans-Bold", size: 32))
                            .foregroundStyle(.white)
                            .opacity(animate ? 1.0 : 0)
                        
                        if !displayName.isEmpty {
                            Text(typedText)
                                .font(.custom("OpenSans-Bold", size: 32))
                                .foregroundStyle(.white)
                                .opacity(1.0)
                        } else if isLoadingUser {
                            // Loading placeholder
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }
                    }
                    .multilineTextAlignment(.center)
                    
                    Text("Your digital companion for\nspiritual growth and connection")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Liquid glass continue button
                if showButton {
                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 14)
                            .background(
                                ZStack {
                                    // Base glass background
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                    
                                    // Blue gradient overlay
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.blue.opacity(0.8),
                                                    Color.blue.opacity(0.6)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    
                                    // Subtle shimmer edge
                                    Capsule()
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.3),
                                                    Color.white.opacity(0.1)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 0.5
                                        )
                                }
                            )
                            .shadow(color: .blue.opacity(0.4), radius: 16, y: 8)
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .padding(.bottom, 60)
                }
            }
        }
        .task {
            // Fetch user's display name
            await fetchDisplayName()
            
            // Animate after user data loads
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animate = true
            }
            
            // Start typing animation for name
            if !displayName.isEmpty {
                await typeNameAnimation()
            }
            
            // Show button after typing completes
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showButton = true
            }
        }
    }
    
    /// Typewriter animation for user's name
    private func typeNameAnimation() async {
        typedText = ""
        
        for character in displayName {
            typedText.append(character)
            // Delay between each character
            try? await Task.sleep(nanoseconds: 80_000_000) // 0.08 seconds per character
        }
    }
    
    /// Fetch the user's display name from Firebase Auth or Firestore
    private func fetchDisplayName() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            isLoadingUser = false
            return
        }
        
        // First try Firebase Auth displayName
        if let authDisplayName = Auth.auth().currentUser?.displayName,
           !authDisplayName.isEmpty {
            displayName = authDisplayName
            isLoadingUser = false
            print("✅ WelcomePage: Loaded display name from Auth: \(authDisplayName)")
            return
        }
        
        // Fallback to Firestore
        do {
            let db = Firestore.firestore()
            let document = try await db.collection("users").document(userId).getDocument()
            
            if let data = document.data() {
                if let firestoreName = data["displayName"] as? String,
                   !firestoreName.isEmpty {
                    displayName = firestoreName
                    print("✅ WelcomePage: Loaded display name from Firestore: \(firestoreName)")
                } else if let username = data["username"] as? String {
                    // Fallback to username
                    displayName = username
                    print("✅ WelcomePage: Using username as display name: \(username)")
                }
            }
        } catch {
            print("❌ WelcomePage: Error fetching display name: \(error)")
        }
        
        isLoadingUser = false
    }
}

// MARK: - Profile Photo Page

struct ProfilePhotoPage: View {
    @Binding var selectedImage: UIImage?
    @Binding var isUploading: Bool
    var currentPage: Int = 2
    var totalPages: Int = 12
    var canContinue: Bool = true
    var onBack: () -> Void = {}
    var onSkip: () -> Void = {}
    var onNext: () -> Void = {}
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Black background extending into ALL safe areas
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        VStack(spacing: 12) {
                            Text("Add a Profile Photo")
                                .font(.custom("OpenSans-Bold", size: 28))
                                .foregroundStyle(.white)
                                .offset(y: animate ? 0 : -20)
                                .opacity(animate ? 1.0 : 0)
                            
                            Text("Show the community who you are")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .offset(y: animate ? 0 : -20)
                                .opacity(animate ? 1.0 : 0)
                        }
                        .padding(.top, 60)
                    
                    // Profile photo preview or placeholder
                    ZStack {
                        if let selectedImage {
                            Image(uiImage: selectedImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 200, height: 200)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.blue.opacity(0.5), lineWidth: 4)
                                )
                                .shadow(color: .blue.opacity(0.3), radius: 20, y: 10)
                                .scaleEffect(animate ? 1.0 : 0.8)
                                .opacity(animate ? 1.0 : 0)
                        } else {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 200, height: 200)
                                
                                Circle()
                                    .stroke(Color.blue.opacity(0.5), lineWidth: 3)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10, 10]))
                                    .frame(width: 200, height: 200)
                                
                                Image(systemName: "person.crop.circle.fill.badge.plus")
                                    .font(.system(size: 80))
                                    .foregroundStyle(Color.white.opacity(0.5))
                            }
                            .scaleEffect(animate ? 1.0 : 0.8)
                            .opacity(animate ? 1.0 : 0)
                        }
                    }
                    
                    // Photo picker button
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        HStack(spacing: 12) {
                            Image(systemName: selectedImage == nil ? "photo.on.rectangle" : "arrow.triangle.2.circlepath.circle.fill")
                                .font(.system(size: 20))
                            
                            Text(selectedImage == nil ? "Choose Photo" : "Change Photo")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color.blue)
                                .shadow(color: .blue.opacity(0.4), radius: 12, y: 6)
                        )
                    }
                        .padding(.horizontal, 40)
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                        
                        if selectedImage == nil {
                            Text("You can also add a photo later")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.white.opacity(0.6))
                                .offset(y: animate ? 0 : 20)
                                .opacity(animate ? 1.0 : 0)
                        }
                        
                        Spacer(minLength: 100)
                        
                        // Navigation buttons inside scroll view
                        OnboardingNavigationButtons(
                            currentPage: currentPage,
                            totalPages: totalPages,
                            canContinue: canContinue,
                            onBack: onBack,
                            onSkip: onSkip,
                            onNext: onNext
                        )
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: selectedItem) { _, newItem in
            // Haptic feedback
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        selectedImage = image
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animate = true
            }
        }
    }
}

// MARK: - Features Page (Black & White Design with Colorful Icons)

struct FeaturesPage: View {
    var currentPage: Int = 3
    var totalPages: Int = 12
    var canContinue: Bool = true
    var onBack: () -> Void = {}
    var onSkip: () -> Void = {}
    var onNext: () -> Void = {}
    
    @State private var animate = false
    
    let features = [
        OnboardingFeature(
            icon: "book.closed.fill",
            title: "Berean AI Assistant",
            description: "Get instant biblical answers & guidance",
            color: .blue
        ),
        OnboardingFeature(
            icon: "hands.sparkles.fill",
            title: "Prayer Network",
            description: "Share and support prayer requests",
            color: .purple
        ),
        OnboardingFeature(
            icon: "person.3.fill",
            title: "#OPENTABLE",
            description: "AI, faith, ideas, and innovation hub",
            color: .orange
        ),
        OnboardingFeature(
            icon: "heart.text.square.fill",
            title: "Testimonies & Stories",
            description: "Share God's faithfulness with others",
            color: .pink
        ),
        OnboardingFeature(
            icon: "books.vertical.fill",
            title: "Resources Library",
            description: "Biblical tools, devotionals, and more",
            color: .green
        )
    ]
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Text("Everything You Need")
                        .font(.custom("OpenSans-Bold", size: 26))
                        .foregroundStyle(.white)
                        .offset(y: animate ? 0 : -20)
                        .opacity(animate ? 1.0 : 0)
                    
                    Text("Powerful features to strengthen your faith")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .offset(y: animate ? 0 : -20)
                        .opacity(animate ? 1.0 : 0)
                }
                .padding(.top, 60)
                
                VStack(spacing: 16) {
                    ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                        OnboardingFeatureCard(feature: feature)
                            .offset(x: animate ? 0 : -50)
                            .opacity(animate ? 1.0 : 0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(index) * 0.1), value: animate)
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer(minLength: 100)
                
                // Navigation buttons inside ScrollView
                OnboardingNavigationButtons(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    canContinue: canContinue,
                    onBack: onBack,
                    onSkip: onSkip,
                    onNext: onNext
                )
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animate = true
            }
        }
    }
}

struct OnboardingFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let color: Color
}

struct OnboardingFeatureCard: View {
    let feature: OnboardingFeature
    
    var body: some View {
        HStack(spacing: 16) {
            // Colorful icon on dark background
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 56, height: 56)
                
                Image(systemName: feature.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(feature.color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.white)
                
                Text(feature.description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Interests Page (Expanded Topics)

struct InterestsPage: View {
    @Binding var selectedInterests: Set<String>
    var currentPage: Int = 4
    var totalPages: Int = 12
    var canContinue: Bool = true
    var onBack: () -> Void = {}
    var onSkip: () -> Void = {}
    var onNext: () -> Void = {}
    
    @State private var animate = false
    @State private var showMaxReachedAlert = false
    
    let maxInterests = 3
    
    // ✅ Expanded from 16 to 30+ topics for better personalization
    let interests = [
        // Core Spiritual Practices
        ("Bible Study", "book.fill"),
        ("Prayer", "hands.sparkles.fill"),
        ("Worship", "music.note"),
        ("Fasting", "heart.circle.fill"),
        
        // Community & Ministry
        ("Community", "person.3.fill"),
        ("Youth Ministry", "figure.walk"),
        ("Children's Ministry", "figure.and.child.holdinghands"),
        ("Small Groups", "person.2.circle.fill"),
        ("Missions", "globe"),
        ("Evangelism", "megaphone.fill"),
        ("Discipleship", "person.2.fill"),
        
        // Learning & Growth
        ("Theology", "graduationcap.fill"),
        ("Apologetics", "lightbulb.fill"),
        ("Church History", "clock.arrow.circlepath"),
        ("Scripture Memory", "brain.fill"),
        ("Biblical Languages", "character.book.closed.fill"),
        ("Devotionals", "heart.text.square.fill"),
        
        // Life & Relationships
        ("Marriage & Family", "house.heart.fill"),
        ("Parenting", "figure.2.and.child.holdinghands"),
        ("Dating & Relationships", "heart.circle"),
        ("Friendship", "person.2.wave.2.fill"),
        ("Mental Health", "brain.head.profile"),
        ("Christian Living", "figure.walk.circle.fill"),
        
        // Social & Cultural
        ("Social Justice", "scale.3d"),
        ("Politics & Faith", "building.columns.fill"),
        ("Creation Care", "globe.americas.fill"),
        ("Racial Reconciliation", "hands.and.sparkles.fill"),
        
        // Work & Creativity
        ("Workplace Faith", "briefcase.fill"),
        ("Entrepreneurship", "lightbulb.max.fill"),
        ("Arts & Creativity", "paintbrush.fill"),
        ("Music Ministry", "music.mic"),
        
        // Tech & Innovation
        ("AI & Faith", "cpu.fill"),
        ("Tech Ethics", "shield.checkered"),
        ("Digital Discipleship", "iphone.and.arrow.forward")
    ]
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("What interests you?")
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(.white)
                        .offset(y: animate ? 0 : -20)
                        .opacity(animate ? 1.0 : 0)
                    
                    Text("Select up to 3 topics you'd like to explore")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                        .offset(y: animate ? 0 : -20)
                        .opacity(animate ? 1.0 : 0)
                    
                    // Selection counter
                    if !selectedInterests.isEmpty {
                        HStack(spacing: 4) {
                            Text("\(selectedInterests.count)")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(selectedInterests.count == maxInterests ? .orange : .blue)
                            Text("/ \(maxInterests) selected")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill((selectedInterests.count == maxInterests ? Color.orange : Color.blue).opacity(0.2))
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 60)
                
                // Interest chips
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(interests.enumerated()), id: \.element.0) { index, interest in
                        OnboardingInterestChip(
                            icon: interest.1,
                            title: interest.0,
                            isSelected: selectedInterests.contains(interest.0),
                            isDisabled: !selectedInterests.contains(interest.0) && selectedInterests.count >= maxInterests
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedInterests.contains(interest.0) {
                                    // Allow deselecting
                                    selectedInterests.remove(interest.0)
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                } else if selectedInterests.count < maxInterests {
                                    // Allow selecting if under limit
                                    selectedInterests.insert(interest.0)
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                } else {
                                    // Show alert when limit reached
                                    showMaxReachedAlert = true
                                    let haptic = UINotificationFeedbackGenerator()
                                    haptic.notificationOccurred(.warning)
                                }
                            }
                        }
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(index) * 0.03), value: animate)
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer(minLength: 100)
                
                // Navigation buttons inside ScrollView
                OnboardingNavigationButtons(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    canContinue: canContinue,
                    onBack: onBack,
                    onSkip: onSkip,
                    onNext: onNext
                )
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .alert("Maximum Reached", isPresented: $showMaxReachedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You can select up to \(maxInterests) interests. Deselect one to choose a different topic.")
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animate = true
            }
        }
    }
}

struct OnboardingInterestChip: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var isDisabled: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(isSelected ? Color.blue : (isDisabled ? .white.opacity(0.3) : .white.opacity(0.6)))
                
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(isSelected ? Color.white : (isDisabled ? .white.opacity(0.4) : .white.opacity(0.8)))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue.opacity(0.2) : (isDisabled ? Color.white.opacity(0.05) : Color.white.opacity(0.1)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.blue : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .opacity(isDisabled ? 0.6 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
    }
}

// MARK: - Goals Page

struct GoalsPage: View {
    @Binding var selectedGoals: Set<String>
    var currentPage: Int = 6
    var totalPages: Int = 12
    var canContinue: Bool = true
    var onBack: () -> Void = {}
    var onSkip: () -> Void = {}
    var onNext: () -> Void = {}
    
    @State private var animate = false
    
    let goals = [
        ("Grow in Faith", "chart.line.uptrend.xyaxis", Color.green),
        ("Daily Bible Reading", "book.fill", Color.purple),
        ("Consistent Prayer", "hands.sparkles.fill", Color.cyan),
        ("Build Community", "person.3.fill", Color.orange),
        ("Share the Gospel", "megaphone.fill", Color.red),
        ("Serve Others", "heart.fill", Color.pink)
    ]
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("What are your goals?")
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(.white)
                        .offset(y: animate ? 0 : -20)
                        .opacity(animate ? 1.0 : 0)
                    
                    Text("We'll personalize your experience")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                        .offset(y: animate ? 0 : -20)
                        .opacity(animate ? 1.0 : 0)
                }
                .padding(.top, 60)
                
                VStack(spacing: 12) {
                    ForEach(Array(goals.enumerated()), id: \.element.0) { index, goal in
                        GoalCard(
                            icon: goal.1,
                            title: goal.0,
                            color: goal.2,
                            isSelected: selectedGoals.contains(goal.0)
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedGoals.contains(goal.0) {
                                    selectedGoals.remove(goal.0)
                                } else {
                                    selectedGoals.insert(goal.0)
                                }
                            }
                            let haptic = UIImpactFeedbackGenerator(style: .medium)
                            haptic.impactOccurred()
                        }
                        .offset(x: animate ? 0 : -50)
                        .opacity(animate ? 1.0 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(index) * 0.1), value: animate)
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer(minLength: 100)
                
                // Navigation buttons inside ScrollView
                OnboardingNavigationButtons(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    canContinue: canContinue,
                    onBack: onBack,
                    onSkip: onSkip,
                    onNext: onNext
                )
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animate = true
            }
        }
    }
}

struct GoalCard: View {
    let icon: String
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? color : color.opacity(0.3))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
                
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 17))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28))
                    .foregroundStyle(isSelected ? color : .white.opacity(0.3))
                    .symbolEffect(.bounce, value: isSelected)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? color.opacity(0.2) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? color : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Prayer Reminder & Accountability Page

struct PrayerTimePage: View {
    @Binding var prayerTime: OnboardingView.PrayerTime
    var currentPage: Int = 8
    var totalPages: Int = 12
    var canContinue: Bool = true
    var onBack: () -> Void = {}
    var onSkip: () -> Void = {}
    var onNext: () -> Void = {}
    
    @State private var animate = false
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    // Icon with animation
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolEffect(.bounce, value: animate)
                    }
                    .scaleEffect(animate ? 1.0 : 0.8)
                    .opacity(animate ? 1.0 : 0)
                    
                    Text("Prayer Reminders")
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(.white)
                        .offset(y: animate ? 0 : -20)
                        .opacity(animate ? 1.0 : 0)
                    
                    Text("Set gentle reminders to take a break from the app and spend time in prayer")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .offset(y: animate ? 0 : -20)
                        .opacity(animate ? 1.0 : 0)
                }
                .padding(.top, 60)
                
                // Accountability Message
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stay Accountable")
                                .font(.custom("OpenSans-Bold", size: 15))
                                .foregroundStyle(.white)
                            
                            Text("Regular reminders help build consistent prayer habits")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.green.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .padding(.horizontal, 40)
                .offset(y: animate ? 0 : 20)
                .opacity(animate ? 1.0 : 0)
                
                // Time Selection
                VStack(alignment: .leading, spacing: 16) {
                    Text("When should we remind you?")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                    
                    VStack(spacing: 12) {
                        ForEach(Array(OnboardingView.PrayerTime.allCases.enumerated()), id: \.element) { index, time in
                            PrayerTimeCard(
                                time: time,
                                isSelected: prayerTime == time
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    prayerTime = time
                                }
                                let haptic = UIImpactFeedbackGenerator(style: .medium)
                                haptic.impactOccurred()
                            }
                            .offset(x: animate ? 0 : 50)
                            .opacity(animate ? 1.0 : 0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(index) * 0.08), value: animate)
                        }
                    }
                }
                .padding(.horizontal, 40)
                
                // Benefits Section
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        
                        Text("Why prayer reminders work")
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.white)
                        
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        BenefitRow(icon: "clock.fill", text: "Build consistent habits", color: .blue)
                        BenefitRow(icon: "brain.fill", text: "Reduce digital distraction", color: .purple)
                        BenefitRow(icon: "heart.fill", text: "Deepen your relationship with God", color: .pink)
                        BenefitRow(icon: "moon.stars.fill", text: "Find peace in your day", color: .indigo)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                )
                .padding(.horizontal, 40)
                .offset(y: animate ? 0 : 20)
                .opacity(animate ? 1.0 : 0)
                
                // Disclaimer
                Text("You can change this anytime in Settings")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 8)
                    .offset(y: animate ? 0 : 20)
                    .opacity(animate ? 1.0 : 0)
                
                Spacer(minLength: 100)
                
                // Navigation buttons inside ScrollView
                OnboardingNavigationButtons(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    canContinue: canContinue,
                    onBack: onBack,
                    onSkip: onSkip,
                    onNext: onNext
                )
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animate = true
            }
        }
    }
}

// MARK: - Benefit Row Component

struct BenefitRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.white)
            
            Spacer()
        }
    }
}

struct PrayerTimeCard: View {
    let time: OnboardingView.PrayerTime
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? time.color.opacity(0.3) : Color.white.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: time.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(isSelected ? time.color : .white.opacity(0.6))
                        .symbolEffect(.bounce, value: isSelected)
                }
                
                Text(time.rawValue)
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 32))
                    .foregroundStyle(isSelected ? time.color : .white.opacity(0.3))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? time.color.opacity(0.2) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isSelected ? time.color : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )
            )
            .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Welcome Values Page (NEW)

struct WelcomeValuesPage: View {
    @Binding var acceptedGuidelines: Bool
    let onContinue: () -> Void
    var currentPage: Int = 1
    var totalPages: Int = 12
    var canContinue: Bool { acceptedGuidelines }
    var onBack: () -> Void = {}
    var onSkip: () -> Void = {}
    
    @State private var animate = false
    @State private var showTermsSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Dark background matching welcome page
                Color.black
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: 100)
                
                // Main content
                VStack(spacing: 32) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 50, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .scaleEffect(animate ? 1.0 : 0.8)
                    .opacity(animate ? 1.0 : 0)
                    
                    VStack(spacing: 16) {
                        Text("Our Commitment to You")
                            .font(.custom("OpenSans-Bold", size: 28))
                            .foregroundStyle(.white)
                            .opacity(animate ? 1.0 : 0)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            CommitmentRow(text: "No endless scrolling")
                            CommitmentRow(text: "No algorithmic manipulation")
                            CommitmentRow(text: "Your data stays private")
                            CommitmentRow(text: "Faith over engagement")
                            CommitmentRow(text: "Community over competition")
                        }
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                    }
                    .padding(.horizontal, 40)
                    
                    // Terms link
                    Button(action: { showTermsSheet = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 14))
                            Text("View Guidelines & Terms")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .offset(y: animate ? 0 : 20)
                    .opacity(animate ? 1.0 : 0)
                    
                    // Checkbox
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            acceptedGuidelines.toggle()
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: acceptedGuidelines ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24))
                                .foregroundStyle(acceptedGuidelines ? .blue : .white.opacity(0.5))
                                .symbolEffect(.bounce, value: acceptedGuidelines)
                            
                            Text("I understand and agree")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule()
                                        .stroke(acceptedGuidelines ? Color.blue.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 2)
                                )
                        )
                    }
                    .offset(y: animate ? 0 : 20)
                    .opacity(animate ? 1.0 : 0)
                    .padding(.bottom, 16)
                }
            }
            }
            }
            
            // Navigation buttons fixed at bottom (outside ScrollView and ZStack)
            OnboardingNavigationButtons(
            currentPage: currentPage,
            totalPages: totalPages,
            canContinue: canContinue,
            onBack: onBack,
            onSkip: onSkip,
            onNext: onContinue
        )
        .padding(.horizontal, 40)
        .padding(.top, 16)
        .padding(.bottom, 32)
        .background(Color.black)
        }
        .sheet(isPresented: $showTermsSheet) {
            GuidelinesTermsView()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animate = true
            }
        }
    }
}

struct CommitmentRow: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.blue)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.white)
            
            Spacer()
        }
    }
}

struct GuidelinesTermsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Community Guidelines")
                        .font(.custom("OpenSans-Bold", size: 24))
                    
                    Text("""
                    AMEN is a faith-based community focused on spiritual growth, not engagement metrics.
                    
                    **What We Encourage:**
                    • Authentic sharing of faith journeys
                    • Prayer support and encouragement
                    • Thoughtful biblical discussions
                    • Respectful disagreement
                    
                    **What We Don't Allow:**
                    • Hate speech or discrimination
                    • Spam or promotional content
                    • Misinformation or conspiracy theories
                    • Content designed to manipulate engagement
                    
                    **Privacy & Data:**
                    • We do not sell your data
                    • We do not use algorithms to increase engagement
                    • We do not track you across other apps
                    • You can export or delete your data anytime
                    
                    **Terms of Service:**
                    By using AMEN, you agree to use the platform responsibly and respect other community members.
                    """)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .lineSpacing(6)
                }
                .padding()
            }
            .navigationTitle("Guidelines & Terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Your Pace Dialog Page (NEW)

struct YourPaceDialogPage: View {
    @Binding var dailyTimeLimit: Int
    @Binding var notificationPreferences: [String: Bool]
    var currentPage: Int = 5
    var totalPages: Int = 12
    var canContinue: Bool = true
    var onBack: () -> Void = {}
    var onSkip: () -> Void = {}
    var onNext: () -> Void = {}
    
    @State private var animate = false
    
    let timeLimits = [20, 45, 90] // minutes
    
    var body: some View {
        ZStack {
            // Dark background matching welcome page
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 32) {
                    // Skip button at top
                    HStack {
                        Spacer()
                        Button {
                            onSkip()
                        } label: {
                            Text("Skip")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    Spacer()
                        .frame(height: 16)
                    
                    // Header
                    VStack(spacing: 16) {
                        // Glassmorphic Clock Icon
                        ZStack {
                            // Outer glow
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color.blue.opacity(0.3),
                                            Color.blue.opacity(0.1),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 20,
                                        endRadius: 60
                                    )
                                )
                                .frame(width: 120, height: 120)
                                .blur(radius: 10)
                            
                            // Glass circle background
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.4),
                                                    Color.white.opacity(0.1)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                            
                            // Clock icon
                            Image(systemName: "clock.fill")
                                .font(.system(size: 48, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .blue.opacity(0.5), radius: 10, y: 5)
                        }
                        .scaleEffect(animate ? 1.0 : 0.8)
                        .opacity(animate ? 1.0 : 0)
                        
                        Text("Your Pace, Your Space")
                            .font(.custom("OpenSans-Bold", size: 32))
                            .foregroundStyle(.white)
                            .opacity(animate ? 1.0 : 0)
                        
                        Text("Based on your interests, we'll suggest content that helps you grow—not content that keeps you scrolling.")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 40)
                            .offset(y: animate ? 0 : 20)
                            .opacity(animate ? 1.0 : 0)
                    }
                    
                    // Daily time limit
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Text("📱")
                                .font(.system(size: 20))
                            Text("Set Your Daily Limit")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.white)
                        }
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                        
                        HStack(spacing: 12) {
                            ForEach(timeLimits, id: \.self) { limit in
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        dailyTimeLimit = limit
                                    }
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                }) {
                                    VStack(spacing: 4) {
                                        Text("\(limit)")
                                            .font(.custom("OpenSans-Bold", size: 24))
                                        Text("min")
                                            .font(.custom("OpenSans-Regular", size: 12))
                                    }
                                    .foregroundStyle(dailyTimeLimit == limit ? .white : .white.opacity(0.5))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(dailyTimeLimit == limit ? Color.blue.opacity(0.3) : Color.white.opacity(0.1))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(dailyTimeLimit == limit ? Color.blue : Color.white.opacity(0.2), lineWidth: 2)
                                            )
                                    )
                                }
                            }
                        }
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                    }
                    .padding(.horizontal, 40)
                    
                    // Notification preferences
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Text("🔔")
                                .font(.system(size: 20))
                            Text("Notification Preferences")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.white)
                        }
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                        
                        VStack(spacing: 12) {
                            NotificationToggle(
                                title: "Prayer reminders",
                                isOn: Binding(
                                    get: { notificationPreferences["prayerReminders"] ?? true },
                                    set: { notificationPreferences["prayerReminders"] = $0 }
                                )
                            )
                            
                            NotificationToggle(
                                title: "New messages",
                                isOn: Binding(
                                    get: { notificationPreferences["newMessages"] ?? true },
                                    set: { notificationPreferences["newMessages"] = $0 }
                                )
                            )
                            
                            NotificationToggle(
                                title: "Trending posts",
                                isOn: Binding(
                                    get: { notificationPreferences["trendingPosts"] ?? false },
                                    set: { notificationPreferences["trendingPosts"] = $0 }
                                )
                            )
                            
                            NotificationToggle(
                                title: "Follow requests",
                                isOn: Binding(
                                    get: { notificationPreferences["followRequests"] ?? true },
                                    set: { notificationPreferences["followRequests"] = $0 }
                                )
                            )
                            
                            NotificationToggle(
                                title: "Post interactions",
                                isOn: Binding(
                                    get: { notificationPreferences["postInteractions"] ?? true },
                                    set: { notificationPreferences["postInteractions"] = $0 }
                                )
                            )
                        }
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)
                }
            }
            
            // Navigation buttons fixed at bottom
            OnboardingNavigationButtons(
                currentPage: currentPage,
                totalPages: totalPages,
                canContinue: canContinue,
                onBack: onBack,
                onSkip: onSkip,
                onNext: onNext
            )
            .padding(.horizontal, 40)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .background(Color.black)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                animate = true
            }
        }
    }
}

struct NotificationToggle: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isOn.toggle()
            }
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        }) {
            HStack {
                Text(title)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isOn ? .blue : .white.opacity(0.3))
                    .symbolEffect(.bounce, value: isOn)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isOn ? Color.blue.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Privacy Promise Page (NEW)

struct PrivacyPromisePage: View {
    @Binding var acceptedPrivacyPolicy: Bool
    var currentPage: Int = 7
    var totalPages: Int = 12
    var canContinue: Bool = true
    var onBack: () -> Void = {}
    var onSkip: () -> Void = {}
    var onNext: () -> Void = {}
    
    @State private var animate = false
    @State private var showPrivacyPolicy = false
    
    var body: some View {
        ZStack {
            // Dark background matching welcome page
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 32) {
                        // Skip button at top
                        HStack {
                            Spacer()
                            Button {
                                onSkip()
                            } label: {
                                Text("Skip")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        Spacer()
                            .frame(height: 16)
                        
                        // Header
                        VStack(spacing: 16) {
                            Text("🔒")
                                .font(.system(size: 60))
                                .scaleEffect(animate ? 1.0 : 0.8)
                                .opacity(animate ? 1.0 : 0)
                            
                            Text("Your Data, Your Control")
                                .font(.custom("OpenSans-Bold", size: 32))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .opacity(animate ? 1.0 : 0)
                        }
                        
                        // What we collect
                        VStack(alignment: .leading, spacing: 16) {
                            Text("What We Collect:")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.white)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                PrivacyRow(icon: "person.circle", text: "Name, email, profile photo", color: .blue)
                                PrivacyRow(icon: "text.bubble", text: "Posts, prayers, testimonies", color: .blue)
                                PrivacyRow(icon: "chart.bar", text: "Anonymous analytics", color: .blue)
                            }
                        }
                        .padding(.horizontal, 40)
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                        
                        // What we DON'T do
                        VStack(alignment: .leading, spacing: 16) {
                            Text("What We DON'T Do:")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.white)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                PrivacyRow(icon: "xmark.circle", text: "Sell your data", color: .red)
                                PrivacyRow(icon: "xmark.circle", text: "Track across other apps", color: .red)
                                PrivacyRow(icon: "xmark.circle", text: "Use data for ads", color: .red)
                                PrivacyRow(icon: "xmark.circle", text: "Share with third parties", color: .red)
                            }
                        }
                        .padding(.horizontal, 40)
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                        
                        // What you can do
                        VStack(alignment: .leading, spacing: 16) {
                            Text("You Can Always:")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.white)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                PrivacyRow(icon: "arrow.down.doc", text: "Export your data (Settings)", color: .green)
                                PrivacyRow(icon: "trash", text: "Delete your account", color: .green)
                                PrivacyRow(icon: "eye.slash", text: "Control what's public", color: .green)
                            }
                        }
                        .padding(.horizontal, 40)
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                        
                        // Privacy policy link
                        Button(action: { showPrivacyPolicy = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 14))
                                Text("View Privacy Policy")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                        
                        // Checkbox
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                acceptedPrivacyPolicy.toggle()
                            }
                            let haptic = UIImpactFeedbackGenerator(style: .medium)
                            haptic.impactOccurred()
                        }) {
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: acceptedPrivacyPolicy ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 24))
                                        .foregroundStyle(acceptedPrivacyPolicy ? .blue : .white.opacity(0.5))
                                        .symbolEffect(.bounce, value: acceptedPrivacyPolicy)
                                    
                                    Text("I understand how my data is used and protected")
                                        .font(.custom("OpenSans-SemiBold", size: 15))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(acceptedPrivacyPolicy ? Color.blue.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 2)
                                    )
                            )
                        }
                        .padding(.horizontal, 40)
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                        .padding(.bottom, 16)
                    }
                }
                
                // Navigation buttons fixed at bottom (outside ScrollView)
                OnboardingNavigationButtons(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    canContinue: canContinue,
                    onBack: onBack,
                    onSkip: onSkip,
                    onNext: onNext
                )
                .padding(.horizontal, 40)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .background(Color.black)
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            OnboardingPrivacyPolicyView()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animate = true
            }
        }
    }
}

struct PrivacyRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.white)
            
            Spacer()
        }
    }
}
// MARK: - Onboarding Privacy Policy View

struct OnboardingPrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Privacy Policy")
                        .font(.custom("OpenSans-Bold", size: 24))
                    
                    Text("""
                    **Last Updated: January 2026**
                    
                    **What Information We Collect:**
                    • Account information (name, email, username)
                    • Profile information (photo, bio, interests)
                    • Content you create (posts, prayers, comments)
                    • Usage data (anonymous analytics)
                    
                    **How We Use Your Information:**
                    • To provide and improve our services
                    • To personalize your experience
                    • To communicate with you
                    • To ensure platform safety and security
                    
                    **What We DON'T Do:**
                    • We do not sell your personal information
                    • We do not track you across other websites or apps
                    • We do not use your data for targeted advertising
                    • We do not share your information with third parties (except as required by law)
                    
                    **Your Rights:**
                    • Access your data at any time
                    • Export your data in a portable format
                    • Delete your account and all associated data
                    • Control your privacy settings
                    
                    **Data Security:**
                    We use industry-standard encryption and security measures to protect your information.
                    
                    **Contact Us:**
                    For questions about this policy, email: privacy@amenapp.com
                    """)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .lineSpacing(6)
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .environmentObject(AuthenticationViewModel())
}

// MARK: - Referral Code Page

struct ReferralCodePage: View {
    @Binding var referralCode: String
    @Binding var referralApplied: Bool
    @Binding var referralError: String?
    var currentPage: Int = 10
    var totalPages: Int = 12
    var canContinue: Bool = true
    var onBack: () -> Void = {}
    var onSkip: () -> Void = {}
    var onNext: () -> Void = {}
    
    @State private var animate = false
    @State private var isValidating = false
    @FocusState private var isCodeFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: 40)
                
                // Header
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.purple.opacity(0.3),
                                        Color.purple.opacity(0.1),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 120, height: 120)
                            .blur(radius: 10)
                        
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 100, height: 100)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        
                        Image(systemName: "gift.fill")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .purple.opacity(0.5), radius: 10, y: 5)
                    }
                    .scaleEffect(animate ? 1.0 : 0.8)
                    .opacity(animate ? 1.0 : 0)
                    
                    Text("Have a Referral Code?")
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(.primary)
                        .opacity(animate ? 1.0 : 0)
                    
                    Text("Enter a code from a friend to unlock special perks and rewards")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 40)
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                }
                
                // Referral code input
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("Enter referral code", text: $referralCode)
                            .font(.custom("OpenSans-Bold", size: 18))
                            .textCase(.uppercase)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .focused($isCodeFocused)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemGray6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(referralApplied ? Color.green : (referralError != nil ? Color.red : Color.clear), lineWidth: 2)
                            )
                        
                        if referralApplied {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.green)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    
                    if let error = referralError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                            Text(error)
                                .font(.custom("OpenSans-Regular", size: 13))
                        }
                        .foregroundStyle(.red)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    if referralApplied {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text("Referral code applied! You'll get special perks.")
                                .font(.custom("OpenSans-Regular", size: 13))
                        }
                        .foregroundStyle(.green)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 40)
                .offset(y: animate ? 0 : 20)
                .opacity(animate ? 1.0 : 0)
                
                // Benefits
                VStack(alignment: .leading, spacing: 16) {
                    Text("What you'll get:")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        BenefitRow(
                            icon: "star.fill",
                            text: "Early access to new features",
                            color: .purple
                        )
                        BenefitRow(
                            icon: "heart.fill",
                            text: "Support your friend's journey",
                            color: .pink
                        )
                        BenefitRow(
                            icon: "sparkles",
                            text: "Exclusive community perks",
                            color: .orange
                        )
                    }
                }
                .padding(.horizontal, 40)
                .offset(y: animate ? 0 : 20)
                .opacity(animate ? 1.0 : 0)
                
                Text("You can skip this and add a code later in Settings")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .offset(y: animate ? 0 : 20)
                    .opacity(animate ? 1.0 : 0)
                    .padding(.bottom, 16)
            }
        }
        
        // Navigation buttons fixed at bottom (outside ScrollView)
        OnboardingNavigationButtons(
            currentPage: currentPage,
            totalPages: totalPages,
            canContinue: canContinue,
            onBack: onBack,
            onSkip: onSkip,
            onNext: onNext
        )
        .padding(.horizontal, 40)
        .padding(.top, 16)
        .padding(.bottom, 32)
        .background(Color(.systemBackground))
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animate = true
            }
        }
    }
}

// MARK: - Find Friends / Contacts Page

struct FindFriendsPage: View {
    @Binding var contactsPermissionGranted: Bool
    var currentPage: Int = 9
    var totalPages: Int = 12
    var canContinue: Bool = true
    var onBack: () -> Void = {}
    var onSkip: () -> Void = {}
    var onNext: () -> Void = {}
    
    @State private var animate = false
    @State private var isRequesting = false
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.green.opacity(0.3),
                                        Color.green.opacity(0.1),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 120, height: 120)
                            .blur(radius: 10)
                        
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 100, height: 100)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        
                        Image(systemName: "person.2.badge.gearshape.fill")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .green.opacity(0.5), radius: 10, y: 5)
                    }
                    .scaleEffect(animate ? 1.0 : 0.8)
                    .opacity(animate ? 1.0 : 0)
                    
                    Text("Find Friends from Contacts")
                        .font(.custom("OpenSans-Bold", size: 26))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .opacity(animate ? 1.0 : 0)
                    
                    Text("We'll help you find friends who are already on AMEN. Your contacts are private and never shared.")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 40)
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                }
                .padding(.top, 60)
                
                // Privacy assurance
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Privacy Matters")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.white)
                            
                            Text("We only use contacts to suggest connections. They're never stored or shared.")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.green.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .padding(.horizontal, 40)
                .offset(y: animate ? 0 : 20)
                .opacity(animate ? 1.0 : 0)
                
                // Benefits
                VStack(alignment: .leading, spacing: 12) {
                    Text("Why connect?")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        BenefitRow(
                            icon: "person.2.fill",
                            text: "Find friends already on AMEN",
                            color: .green
                        )
                        BenefitRow(
                            icon: "hands.sparkles.fill",
                            text: "Pray together and share testimonies",
                            color: .blue
                        )
                        BenefitRow(
                            icon: "heart.fill",
                            text: "Build a supportive faith community",
                            color: .pink
                        )
                    }
                }
                .padding(.horizontal, 40)
                .offset(y: animate ? 0 : 20)
                .opacity(animate ? 1.0 : 0)
                
                // Action buttons
                VStack(spacing: 16) {
                    if !contactsPermissionGranted {
                        Button {
                            requestContactsAccess()
                        } label: {
                            HStack(spacing: 12) {
                                if isRequesting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "person.badge.plus.fill")
                                        .font(.system(size: 18))
                                }
                                
                                Text(isRequesting ? "Requesting..." : "Find Friends")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.green, Color.green.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: .green.opacity(0.3), radius: 12, y: 6)
                            )
                        }
                        .disabled(isRequesting)
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.green)
                            
                            Text("Contacts access granted!")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.white)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.green.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.green, lineWidth: 2)
                                )
                        )
                    }
                }
                .padding(.horizontal, 40)
                .offset(y: animate ? 0 : 20)
                .opacity(animate ? 1.0 : 0)
                
                Text("You can change this anytime in Settings")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .offset(y: animate ? 0 : 20)
                    .opacity(animate ? 1.0 : 0)
                
                Spacer(minLength: 100)
                
                // Navigation buttons inside ScrollView
                OnboardingNavigationButtons(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    canContinue: canContinue,
                    onBack: onBack,
                    onSkip: onSkip,
                    onNext: onNext
                )
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animate = true
            }
        }
    }
    
    private func requestContactsAccess() {
        isRequesting = true
        
        let store = CNContactStore()
        
        store.requestAccess(for: .contacts) { granted, error in
            DispatchQueue.main.async {
                isRequesting = false
                
                if granted {
                    contactsPermissionGranted = true
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    print("✅ Contacts access granted")
                } else {
                    print("❌ Contacts access denied: \(error?.localizedDescription ?? "Unknown error")")
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Feedback & Recommendations Page

struct FeedbackRecommendationsPage: View {
    @Binding var rating: Int
    @Binding var feedback: String
    let selectedInterests: Set<String>
    let selectedGoals: Set<String>
    var currentPage: Int = 11
    var totalPages: Int = 12
    var canContinue: Bool = true
    var onBack: () -> Void = {}
    var onSkip: () -> Void = {}
    var onNext: () -> Void = {}
    
    @State private var animate = false
    @FocusState private var isFeedbackFocused: Bool
    
    // Generate personalized recommendations
    private var recommendations: [String] {
        var suggestions: [String] = []
        
        // Based on interests
        if selectedInterests.contains("AI & Faith") || selectedInterests.contains("Tech Ethics") {
            suggestions.append("💡 Join #OPENTABLE for AI & tech discussions")
        }
        
        if selectedInterests.contains("Prayer") || selectedInterests.contains("Worship") {
            suggestions.append("🙏 Explore Prayer Circles to connect with others")
        }
        
        if selectedInterests.contains("Bible Study") || selectedInterests.contains("Theology") {
            suggestions.append("📖 Ask Berean AI for deep biblical insights")
        }
        
        if selectedInterests.contains("Community") || selectedInterests.contains("Small Groups") {
            suggestions.append("👥 Find local faith groups near you")
        }
        
        if selectedInterests.contains("Missions") || selectedInterests.contains("Evangelism") {
            suggestions.append("🌍 Share your testimony to inspire others")
        }
        
        if selectedInterests.contains("Youth Ministry") || selectedInterests.contains("Children's Ministry") {
            suggestions.append("✨ Connect with ministry leaders and parents")
        }
        
        if selectedInterests.contains("Marriage & Family") || selectedInterests.contains("Parenting") {
            suggestions.append("❤️ Join family-focused discussions")
        }
        
        // Based on goals
        if selectedGoals.contains("Grow in Faith") {
            suggestions.append("📚 Check out the Resources Library")
        }
        
        if selectedGoals.contains("Daily Bible Reading") {
            suggestions.append("📖 Set up daily Bible reading reminders")
        }
        
        if selectedGoals.contains("Build Community") {
            suggestions.append("🤝 Follow users with similar interests")
        }
        
        if selectedGoals.contains("Share the Gospel") {
            suggestions.append("📣 Share posts to spread God's word")
        }
        
        // Default recommendations
        if suggestions.isEmpty {
            suggestions = [
                "🙏 Start by exploring Prayer requests",
                "💬 Join conversations in #OPENTABLE",
                "📖 Ask Berean AI your biblical questions"
            ]
        }
        
        // Limit to top 4 recommendations
        return Array(suggestions.prefix(4))
    }
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer()
                            .frame(height: 60)
                
                // Header - Black & White Liquid Glass
                VStack(spacing: 16) {
                    ZStack {
                        // Outer glass glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.15),
                                        Color.black.opacity(0.05),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 120, height: 120)
                            .blur(radius: 10)

                        // Main glass circle
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.1),
                                        Color.black.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 100, height: 100)
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.6),
                                                Color.white.opacity(0.2),
                                                Color.black.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: .black.opacity(0.1), radius: 15, y: 8)

                        // Icon
                        Image(systemName: "sparkles")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color.primary.opacity(0.9),
                                        Color.primary.opacity(0.6)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolEffect(.pulse)
                    }
                    .scaleEffect(animate ? 1.0 : 0.8)
                    .opacity(animate ? 1.0 : 0)

                    Text("You're All Set!")
                        .font(.custom("OpenSans-Bold", size: 32))
                        .foregroundStyle(.white)
                        .opacity(animate ? 1.0 : 0)

                    Text("Here's what we recommend based on your interests")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 40)
                        .offset(y: animate ? 0 : 20)
                        .opacity(animate ? 1.0 : 0)
                }
                
                // Personalized Recommendations - Black & White Liquid Glass
                VStack(alignment: .leading, spacing: 16) {
                    Text("Personalized for You")
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.white)

                    VStack(spacing: 12) {
                        ForEach(recommendations, id: \.self) { recommendation in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.8),
                                                Color.white.opacity(0.5)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )

                                Text(recommendation)
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer()
                            }
                            .padding()
                            .background(
                                ZStack {
                                    // Liquid glass background
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial)

                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.08),
                                                    Color.black.opacity(0.02)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )

                                    // Glass border
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.4),
                                                    Color.white.opacity(0.1),
                                                    Color.black.opacity(0.1)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                }
                            )
                            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .offset(y: animate ? 0 : 20)
                .opacity(animate ? 1.0 : 0)
                
                // Feedback Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("How was your experience?")
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.white)
                    
                    // Star rating
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    rating = star
                                }
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            } label: {
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.system(size: 32))
                                    .foregroundStyle(star <= rating ? .yellow : .gray.opacity(0.3))
                                    .symbolEffect(.bounce, value: rating)
                            }
                        }
                    }
                    
                    // Optional feedback text
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tell us more (optional)")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.white.opacity(0.7))
                        
                        TextEditor(text: $feedback)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .frame(height: 100)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .focused($isFeedbackFocused)
                    }
                    
                    Text("Your feedback helps us improve AMEN for everyone")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 40)
                .offset(y: animate ? 0 : 20)
                .opacity(animate ? 1.0 : 0)
                
                Spacer(minLength: 100)
                
                // Navigation buttons inside ScrollView
                OnboardingNavigationButtons(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    canContinue: canContinue,
                    onBack: onBack,
                    onSkip: onSkip,
                    onNext: onNext
                )
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                animate = true
            }
        }
    }
}

// MARK: - Saving Overlay

struct SavingOverlay: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
                
                Text("Saving your preferences...")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
    }
}

// MARK: - Onboarding Navigation Buttons

struct OnboardingNavigationButtons: View {
    var currentPage: Int
    var totalPages: Int
    var canContinue: Bool
    var onBack: () -> Void
    var onSkip: (() -> Void)? = nil
    var onNext: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            if currentPage > 1 {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onBack()
                } label: {
                    HStack {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .bold))
                        Text("Back")
                            .font(.custom("OpenSans-Bold", size: 15))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .buttonStyle(PressableButtonStyle())
            }
            
            Spacer()
            
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onNext()
            } label: {
                HStack(spacing: 8) {
                    Text(currentPage == totalPages - 1 ? "Get Started" : "Continue")
                        .font(.custom("OpenSans-Bold", size: 16))
                    
                    Image(systemName: currentPage == totalPages - 1 ? "checkmark" : "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(Color.blue)
                        .shadow(color: .blue.opacity(0.3), radius: 12, y: 6)
                )
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canContinue)
            .opacity(canContinue ? 1.0 : 0.5)
            .animation(.easeInOut(duration: 0.2), value: canContinue)
        }
    }
}

// MARK: - Combined Security Onboarding Page (2FA + Biometric)

struct CombinedSecurityOnboardingPage: View {
    @Binding var enable2FA: Bool
    @Binding var backupCodes: [String]
    @Binding var enableBiometric: Bool
    var currentPage: Int = 11
    var totalPages: Int = 13
    var canContinue: Bool = true
    var onBack: () -> Void = {}
    var onSkip: () -> Void = {}
    var onNext: () -> Void = {}
    
    @ObservedObject private var biometricService = BiometricAuthService.shared
    @State private var animate = false
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer()
                            .frame(height: 60)
                        
                        headerSection
                        twoFactorSection
                        
                        if biometricService.isBiometricAvailable {
                            biometricSection
                        }
                        
                        footerText
                        
                        Spacer(minLength: 100)
                        
                        navigationButtons
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: enableBiometric) { _, newValue in
            if newValue {
                BiometricAuthService.shared.enableBiometric()
            } else {
                BiometricAuthService.shared.disableBiometric()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animate = true
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 70))
                .foregroundStyle(.green.opacity(0.9))
                .scaleEffect(animate ? 1.0 : 0.8)
                .opacity(animate ? 1.0 : 0)
            
            Text("Secure Your Account")
                .font(.custom("OpenSans-Bold", size: 28))
                .foregroundStyle(.white)
                .opacity(animate ? 1.0 : 0)
            
            Text("Add extra layers of security to protect your account")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .offset(y: animate ? 0 : 20)
                .opacity(animate ? 1.0 : 0)
        }
    }
    
    private var twoFactorSection: some View {
        VStack(spacing: 16) {
            twoFactorToggle
            
            if enable2FA {
                twoFactorInfoView
            }
        }
        .padding(.horizontal, 24)
        .offset(y: animate ? 0 : 20)
        .opacity(animate ? 1.0 : 0)
    }
    
    private var twoFactorToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.green)
                    Text("Two-Factor Authentication")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                }
                
                Text("Recommended for account security")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Spacer()
            
            Toggle("", isOn: $enable2FA)
                .labelsHidden()
                .tint(.green)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private var twoFactorInfoView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.green)
                Text("Verification Codes")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.white)
            }
            
            Text("When enabled, we'll send verification codes to your email or phone when you sign in from a new device.")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 10) {
                SecurityBenefitRow(icon: "checkmark.shield.fill", text: "Extra layer of security", color: .green)
                SecurityBenefitRow(icon: "envelope.badge.fill", text: "Codes sent to your email", color: .blue)
                SecurityBenefitRow(icon: "message.fill", text: "Or via SMS to your phone", color: .orange)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.green.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.green.opacity(0.3), lineWidth: 1)
                )
        )
        .transition(.opacity.combined(with: .scale))
    }
    
    private var biometricSection: some View {
        VStack(spacing: 16) {
            biometricToggle
            
            if enableBiometric {
                biometricBenefits
            }
        }
        .padding(.horizontal, 24)
        .offset(y: animate ? 0 : 20)
        .opacity(animate ? 1.0 : 0)
    }
    
    private var biometricToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: biometricService.biometricType.icon)
                        .foregroundStyle(.blue)
                    Text("Enable \(biometricService.biometricType.displayName)")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                }
                
                Text("Recommended for convenience")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Spacer()
            
            Toggle("", isOn: $enableBiometric)
                .labelsHidden()
                .tint(.blue)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private var biometricBenefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Text("Quick & Secure")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                SecurityBenefitRow(icon: "bolt.fill", text: "Instant sign-in", color: .orange)
                SecurityBenefitRow(icon: "lock.shield.fill", text: "More secure than passwords", color: .green)
                SecurityBenefitRow(icon: "iphone.gen3", text: "Data stays on device", color: .blue)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.blue.opacity(0.3), lineWidth: 1)
                )
        )
        .transition(.opacity.combined(with: .scale))
    }
    
    private var footerText: some View {
        Text("You can change these anytime in Settings")
            .font(.custom("OpenSans-Regular", size: 12))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 40)
            .padding(.bottom, 16)
            .offset(y: animate ? 0 : 20)
            .opacity(animate ? 1.0 : 0)
    }
    
    private var navigationButtons: some View {
        OnboardingNavigationButtons(
            currentPage: currentPage,
            totalPages: totalPages,
            canContinue: canContinue,
            onBack: onBack,
            onSkip: onSkip,
            onNext: onNext
        )
        .padding(.horizontal, 40)
    }
    
}

struct SecurityBenefitRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.white)
            
            Spacer()
        }
    }
}

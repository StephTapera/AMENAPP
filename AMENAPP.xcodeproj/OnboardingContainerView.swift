//
//  OnboardingContainerView.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import SwiftUI

/// Main container for the onboarding flow
struct OnboardingContainerView: View {
    @StateObject private var coordinator = OnboardingCoordinator()
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color(white: 0.98)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress bar
                if coordinator.currentStep != .welcome && coordinator.currentStep != .completion {
                    OnboardingProgressBar(progress: coordinator.progress)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                }
                
                // Content based on current step
                Group {
                    switch coordinator.currentStep {
                    case .welcome:
                        OnboardingWelcomeView()
                    case .displayName:
                        OnboardingDisplayNameView()
                    case .profilePhoto:
                        OnboardingProfilePhotoView()
                    case .bio:
                        OnboardingBioView()
                    case .interests:
                        OnboardingInterestsView()
                    case .denominations:
                        OnboardingDenominationView()
                    case .notifications:
                        OnboardingNotificationsView()
                    case .completion:
                        OnboardingCompletionView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                
                Spacer()
                
                // Navigation buttons
                OnboardingNavigationButtons()
            }
        }
        .environmentObject(coordinator)
        .onChange(of: coordinator.isOnboardingComplete) { _, isComplete in
            if isComplete {
                // Save user data to Firebase
                Task {
                    await saveUserDataToFirebase()
                }
            }
        }
    }
    
    private func saveUserDataToFirebase() async {
        // TODO: Implement saving to Firebase
        // This would update the user's profile with all the onboarding data
        print("💾 Saving user data to Firebase...")
        print("📝 Display Name: \(coordinator.userData.displayName)")
        print("📝 Bio: \(coordinator.userData.bio)")
        print("📝 Interests: \(coordinator.userData.selectedInterests)")
        print("📝 Denomination: \(coordinator.userData.denomination ?? "Not specified")")
        print("📝 Notifications: \(coordinator.userData.notificationsEnabled)")
        
        // For now, just dismiss after a short delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Mark onboarding as complete in auth view model
        authViewModel.completeOnboarding()
        
        // Trigger haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
}

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let progress: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 6)
                
                // Progress
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress, height: 6)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Navigation Buttons

struct OnboardingNavigationButtons: View {
    @EnvironmentObject var coordinator: OnboardingCoordinator
    
    var body: some View {
        VStack(spacing: 12) {
            // Primary button (Continue/Get Started)
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                coordinator.nextStep()
            } label: {
                Text(buttonText)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                coordinator.canContinue
                                    ? LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.gray.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                            )
                    )
                    .shadow(
                        color: coordinator.canContinue ? .blue.opacity(0.3) : .clear,
                        radius: 12,
                        y: 4
                    )
            }
            .disabled(!coordinator.canContinue)
            
            // Skip button (if applicable)
            if coordinator.currentStep.canSkip && coordinator.currentStep != .completion {
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    coordinator.skipStep()
                } label: {
                    Text("Skip for now")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.black.opacity(0.5))
                }
                .padding(.bottom, 8)
            }
            
            // Back button (if not on first step)
            if coordinator.currentStep != .welcome && coordinator.currentStep != .completion {
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    coordinator.previousStep()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                    }
                    .foregroundStyle(.black.opacity(0.5))
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    private var buttonText: String {
        switch coordinator.currentStep {
        case .welcome:
            return "Get Started"
        case .completion:
            return "Enter AMEN"
        default:
            return "Continue"
        }
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AuthenticationViewModel())
}

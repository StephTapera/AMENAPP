//
//  OnboardingCoordinator.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import Foundation
import SwiftUI

/// Coordinator to manage onboarding flow state
@MainActor
class OnboardingCoordinator: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var userData: OnboardingUserData = OnboardingUserData()
    @Published var isOnboardingComplete: Bool = false
    
    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case displayName = 1
        case profilePhoto = 2
        case bio = 3
        case interests = 4
        case denominations = 5
        case notifications = 6
        case completion = 7
        
        var title: String {
            switch self {
            case .welcome: return "Welcome to AMEN"
            case .displayName: return "What's your name?"
            case .profilePhoto: return "Add a photo"
            case .bio: return "Tell us about yourself"
            case .interests: return "What interests you?"
            case .denominations: return "Your faith background"
            case .notifications: return "Stay connected"
            case .completion: return "You're all set!"
            }
        }
        
        var subtitle: String {
            switch self {
            case .welcome: return "Let's get to know you better"
            case .displayName: return "How should we address you?"
            case .profilePhoto: return "Help others recognize you"
            case .bio: return "Share your testimony or interests"
            case .interests: return "Select topics you care about"
            case .denominations: return "Optional: Share your denomination"
            case .notifications: return "Get updates on prayers and testimonies"
            case .completion: return "Welcome to the AMEN community!"
            }
        }
        
        var icon: String {
            switch self {
            case .welcome: return "hands.sparkles"
            case .displayName: return "person.fill"
            case .profilePhoto: return "camera.fill"
            case .bio: return "text.alignleft"
            case .interests: return "star.fill"
            case .denominations: return "cross.fill"
            case .notifications: return "bell.fill"
            case .completion: return "checkmark.circle.fill"
            }
        }
        
        var canSkip: Bool {
            switch self {
            case .welcome, .displayName, .completion:
                return false
            default:
                return true
            }
        }
    }
    
    var progress: Double {
        Double(currentStep.rawValue) / Double(OnboardingStep.allCases.count - 1)
    }
    
    var canContinue: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .displayName:
            return !userData.displayName.isEmpty
        case .profilePhoto:
            return true // Optional
        case .bio:
            return true // Optional
        case .interests:
            return !userData.selectedInterests.isEmpty
        case .denominations:
            return true // Optional
        case .notifications:
            return true
        case .completion:
            return true
        }
    }
    
    func nextStep() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            completeOnboarding()
            return
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep = next
        }
    }
    
    func previousStep() {
        guard let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep = previous
        }
    }
    
    func skipStep() {
        guard currentStep.canSkip else { return }
        nextStep()
    }
    
    func completeOnboarding() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isOnboardingComplete = true
        }
        
        // Save to UserDefaults
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        
        print("✅ Onboarding completed!")
        print("📝 User Data: \(userData)")
    }
}

/// Data model for onboarding user information
struct OnboardingUserData: Codable {
    var displayName: String = ""
    var profileImage: Data? = nil
    var bio: String = ""
    var selectedInterests: [String] = []
    var denomination: String? = nil
    var notificationsEnabled: Bool = true
    
    // Available options
    static let availableInterests = [
        "Prayer", "Bible Study", "Worship", "Fellowship",
        "Evangelism", "Youth Ministry", "Missions", "Testimonies",
        "Christian Music", "Devotionals", "Theology", "Community Service"
    ]
    
    static let availableDenominations = [
        "Non-denominational", "Baptist", "Catholic", "Methodist",
        "Pentecostal", "Presbyterian", "Lutheran", "Episcopal",
        "Orthodox", "Seventh-day Adventist", "Assembly of God",
        "Church of God", "Other", "Prefer not to say"
    ]
}

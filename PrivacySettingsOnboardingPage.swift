//
//  PrivacySettingsOnboardingPage.swift
//  AMENAPP
//
//  Privacy configuration during onboarding
//

import SwiftUI

struct PrivacySettingsOnboardingPage: View {
    @Binding var isAccountPrivate: Bool
    @Binding var whoCanMessage: MessagingPrivacy
    @Binding var commentModeration: CommentModerationLevel
    let currentPage: Int
    let totalPages: Int
    let canContinue: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onNext: () -> Void

    enum CommentModerationLevel: String, CaseIterable {
        case standard = "Standard"
        case strict   = "Strict"

        var icon: String {
            switch self {
            case .standard: return "text.bubble"
            case .strict:   return "shield.fill"
            }
        }

        var description: String {
            switch self {
            case .standard: return "Filters spam and obvious hate speech"
            case .strict:   return "Hides all comments until you approve them"
            }
        }
    }

    enum MessagingPrivacy: String, CaseIterable {
        case everyone = "Everyone"
        case followersOnly = "People I Follow"
        case nobody = "Nobody"
        
        var icon: String {
            switch self {
            case .everyone: return "person.3.fill"
            case .followersOnly: return "person.2.fill"
            case .nobody: return "hand.raised.fill"
            }
        }
        
        var description: String {
            switch self {
            case .everyone: return "Anyone can send you direct messages"
            case .followersOnly: return "Only people you follow can message you"
            case .nobody: return "Block all direct messages"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 70))
                            .foregroundStyle(.blue.opacity(0.9))
                            .symbolEffect(.pulse)
                        
                        VStack(spacing: 8) {
                            Text("Your Privacy Matters")
                                .font(.custom("OpenSans-Bold", size: 28))
                                .foregroundStyle(.white)
                            
                            Text("Control who can see your content and contact you")
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.top, 60)
                    
                    VStack(spacing: 24) {
                        // Private Account Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 12) {
                                Image(systemName: isAccountPrivate ? "lock.fill" : "lock.open.fill")
                                    .foregroundStyle(isAccountPrivate ? .blue : .white.opacity(0.6))
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Private Account")
                                        .font(.custom("OpenSans-SemiBold", size: 17))
                                        .foregroundStyle(.white)
                                    
                                    Text(isAccountPrivate ? "Only approved followers see your posts" : "Anyone can see your public posts")
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $isAccountPrivate)
                                    .labelsHidden()
                                    .tint(.blue)
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.05))
                            )
                            
                            // Private account explainer
                            if isAccountPrivate {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundStyle(.blue)
                                        .font(.system(size: 16))
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("With a private account:")
                                            .font(.custom("OpenSans-SemiBold", size: 13))
                                            .foregroundStyle(.white)
                                        
                                        BulletPoint(text: "New followers must request to follow you")
                                        BulletPoint(text: "Only approved followers see your posts")
                                        BulletPoint(text: "Your posts won't appear in search results")
                                        BulletPoint(text: "You can still follow and interact with public accounts")
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.blue.opacity(0.1))
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.95)).combined(with: .move(edge: .top)))
                            }
                        }
                        
                        // Messaging Privacy Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Who Can Message You")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.white.opacity(0.7))
                            
                            VStack(spacing: 12) {
                                ForEach(MessagingPrivacy.allCases, id: \.self) { option in
                                    MessagingPrivacyOption(
                                        option: option,
                                        isSelected: whoCanMessage == option,
                                        action: {
                                            // Haptic feedback
                                            let haptic = UIImpactFeedbackGenerator(style: .light)
                                            haptic.impactOccurred()
                                            
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                whoCanMessage = option
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        
                        // Comment Moderation Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Comment Moderation")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.white.opacity(0.7))

                            VStack(spacing: 12) {
                                ForEach(CommentModerationLevel.allCases, id: \.self) { level in
                                    Button(action: {
                                        let haptic = UIImpactFeedbackGenerator(style: .light)
                                        haptic.impactOccurred()
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            commentModeration = level
                                        }
                                    }) {
                                        HStack(spacing: 16) {
                                            ZStack {
                                                Circle()
                                                    .stroke(commentModeration == level ? Color.blue : Color.secondary.opacity(0.3), lineWidth: 2)
                                                    .frame(width: 24, height: 24)
                                                if commentModeration == level {
                                                    Circle()
                                                        .fill(Color.blue)
                                                        .frame(width: 12, height: 12)
                                                }
                                            }

                                            Image(systemName: level.icon)
                                                .foregroundStyle(commentModeration == level ? .blue : .white.opacity(0.6))
                                                .frame(width: 24)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(level.rawValue)
                                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                                    .foregroundStyle(.white)
                                                Text(level.description)
                                                    .font(.custom("OpenSans-Regular", size: 12))
                                                    .foregroundStyle(.white.opacity(0.7))
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }

                                            Spacer()
                                        }
                                        .padding(16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(commentModeration == level ? Color.blue.opacity(0.2) : Color.white.opacity(0.05))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(commentModeration == level ? Color.blue : Color.white.opacity(0.2), lineWidth: 2)
                                                )
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }

                        // AI Moderation Disclosure
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "cpu.fill")
                                .foregroundStyle(.blue)
                                .font(.system(size: 16))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("AI-Assisted Safety")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.white)

                                Text("Messages are reviewed by AI to detect harmful content and protect our community. No human reads your messages except in confirmed safety escalations.")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.blue.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue.opacity(0.25), lineWidth: 1)
                                )
                        )

                        // Additional Info
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "hand.raised.fill")
                                    .foregroundStyle(.orange)
                                    .font(.system(size: 16))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("You're Always in Control")
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                        .foregroundStyle(.white)

                                    Text("Change these settings anytime in your account settings")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.orange.opacity(0.1))
                        )
                    }
                    .padding(.horizontal, 24)
                    
                    // Navigation Buttons
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
        .background(Color.black.ignoresSafeArea())
        .onChange(of: isAccountPrivate) { _, _ in
            // Haptic feedback
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
        }
    }
}

// MARK: - Messaging Privacy Option

struct MessagingPrivacyOption: View {
    let option: PrivacySettingsOnboardingPage.MessagingPrivacy
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                    }
                }
                
                Image(systemName: option.icon)
                    .foregroundStyle(isSelected ? .blue : .white.opacity(0.6))
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.rawValue)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.white)
                    
                    Text(option.description)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.white.opacity(0.2), lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Bullet Point

struct BulletPoint: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.white.opacity(0.7))
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    PrivacySettingsOnboardingPage(
        isAccountPrivate: .constant(false),
        whoCanMessage: .constant(.everyone),
        commentModeration: .constant(.standard),
        currentPage: 8,
        totalPages: 13,
        canContinue: true,
        onBack: {},
        onSkip: {},
        onNext: {}
    )
}

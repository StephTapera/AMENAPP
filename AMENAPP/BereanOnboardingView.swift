//
//  BereanOnboardingView.swift
//  AMENAPP
//
//  Created by Assistant on 2/3/26.
//

import SwiftUI

// MARK: - Onboarding Model

struct BereanOnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let animation: String? // SF Symbol animation
}

// MARK: - Berean Onboarding View

struct BereanOnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var showPermissions = false
    
    let pages: [BereanOnboardingPage] = [
        BereanOnboardingPage(
            icon: "sparkles",
            iconColor: Color(red: 1.0, green: 0.7, blue: 0.5),
            title: "Meet Berean AI",
            description: "Your personal Bible study companion powered by advanced AI. Ask questions, explore Scripture, and deepen your faith.",
            animation: "pulse"
        ),
        BereanOnboardingPage(
            icon: "book.pages.fill",
            iconColor: Color(red: 0.5, green: 0.6, blue: 0.9),
            title: "Deep Scripture Study",
            description: "Get instant explanations, historical context, cross-references, and original language insights for any passage.",
            animation: nil
        ),
        BereanOnboardingPage(
            icon: "globe.americas.fill",
            iconColor: Color(red: 0.6, green: 0.5, blue: 0.8),
            title: "Multiple Translations",
            description: "Compare Bible translations side-by-side. Choose from ESV, NIV, NKJV, KJV, NLT, and more.",
            animation: nil
        ),
        BereanOnboardingPage(
            icon: "person.2.fill",
            iconColor: Color(red: 1.0, green: 0.6, blue: 0.7),
            title: "Share Your Insights",
            description: "Found something meaningful? Share AI insights directly to your OpenTable feed and inspire your community.",
            animation: nil
        ),
        BereanOnboardingPage(
            icon: "waveform",
            iconColor: Color(red: 1.0, green: 0.85, blue: 0.5),
            title: "Voice Conversations",
            description: "Ask questions naturally using your voice. Berean understands context and conversation flow.",
            animation: "variableColor"
        ),
        BereanOnboardingPage(
            icon: "crown.fill",
            iconColor: Color(red: 1.0, green: 0.75, blue: 0.4),
            title: "Ready to Begin?",
            description: "Start your journey into deeper Bible understanding. All features are available with optional premium upgrades.",
            animation: nil
        )
    ]
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.96, blue: 0.94),
                    Color(red: 0.95, green: 0.94, blue: 0.96),
                    Color(red: 0.96, green: 0.95, blue: 0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if showPermissions {
                PermissionsView(
                    isPresented: $isPresented,
                    onComplete: {
                        completeOnboarding()
                    }
                )
            } else {
                onboardingPagesView
            }
        }
    }
    
    private var onboardingPagesView: some View {
        VStack(spacing: 0) {
            // Skip button
            HStack {
                Spacer()
                
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        if currentPage < pages.count - 1 {
                            showPermissions = true
                        } else {
                            completeOnboarding()
                        }
                    }
                } label: {
                    Text("Skip")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(white: 0.4))
                }
                .padding(.trailing, 20)
                .padding(.top, 20)
            }
            
            // Page content
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    BereanOnboardingPageView(page: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color(red: 1.0, green: 0.7, blue: 0.5) : Color(white: 0.8))
                        .frame(width: currentPage == index ? 8 : 6, height: currentPage == index ? 8 : 6)
                        .animation(.smooth(duration: 0.3), value: currentPage)
                }
            }
            .padding(.bottom, 20)
            
            // Navigation buttons
            HStack(spacing: 16) {
                if currentPage > 0 {
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            currentPage -= 1
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(Color(white: 0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.black.opacity(0.04), lineWidth: 0.5)
                                )
                        )
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        if currentPage < pages.count - 1 {
                            currentPage += 1
                        } else {
                            showPermissions = true
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentPage == pages.count - 1 ? "Get Started" : "Next")
                            .font(.system(size: 16, weight: .bold))
                        
                        if currentPage < pages.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.7, blue: 0.5),
                                        Color(red: 1.0, green: 0.6, blue: 0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.4).opacity(0.3), radius: 15, y: 5)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "berean_onboarding_completed")
        
        withAnimation(.smooth(duration: 0.4)) {
            isPresented = false
        }
    }
}

// MARK: - Onboarding Page View

struct BereanOnboardingPageView: View {
    let page: BereanOnboardingPage
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Icon
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                page.iconColor.opacity(0.3),
                                page.iconColor.opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 140, height: 140)
                
                // Icon background
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .stroke(page.iconColor.opacity(0.2), lineWidth: 1)
                    )
                
                // Icon
                Image(systemName: page.icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(page.iconColor)
                    .symbolEffect(.pulse, options: .repeating, value: page.animation == "pulse")
                    .symbolEffect(.variableColor, options: .repeating, value: page.animation == "variableColor")
            }
            .padding(.top, 60)
            
            VStack(spacing: 20) {
                Text(page.title)
                    .font(.custom("Georgia", size: 32))
                    .fontWeight(.light)
                    .foregroundStyle(Color(white: 0.2))
                    .multilineTextAlignment(.center)
                
                Text(page.description)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(white: 0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Permissions View

struct PermissionsView: View {
    @Binding var isPresented: Bool
    let onComplete: () -> Void
    
    @State private var notificationsGranted = false
    @State private var microphoneGranted = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.4, green: 0.85, blue: 0.7),
                                Color(red: 0.3, green: 0.7, blue: 0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 60)
                
                Text("Permissions")
                    .font(.custom("Georgia", size: 32))
                    .fontWeight(.light)
                    .foregroundStyle(Color(white: 0.2))
                
                Text("Enhance your experience with optional permissions")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(white: 0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
            
            // Permission cards
            VStack(spacing: 16) {
                PermissionCard(
                    icon: "bell.fill",
                    iconColor: Color(red: 1.0, green: 0.6, blue: 0.4),
                    title: "Notifications",
                    description: "Get daily verse inspiration and study reminders",
                    isGranted: $notificationsGranted,
                    onRequest: requestNotifications
                )
                
                PermissionCard(
                    icon: "waveform",
                    iconColor: Color(red: 0.5, green: 0.6, blue: 0.9),
                    title: "Microphone",
                    description: "Ask questions using your voice for hands-free study",
                    isGranted: $microphoneGranted,
                    onRequest: requestMicrophone
                )
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Continue button
            Button {
                onComplete()
            } label: {
                Text("Continue")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.7, blue: 0.5),
                                        Color(red: 1.0, green: 0.6, blue: 0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.4).opacity(0.3), radius: 15, y: 5)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            
            Text("You can always change these in Settings")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(white: 0.5))
                .padding(.bottom, 20)
        }
    }
    
    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                notificationsGranted = granted
                if let error = error {
                    print("❌ Notification permission error: \(error)")
                }
            }
        }
    }
    
    private func requestMicrophone() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                microphoneGranted = granted
            }
        }
    }
}

// MARK: - Permission Card

struct PermissionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    @Binding var isGranted: Bool
    let onRequest: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(white: 0.2))
                
                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(white: 0.5))
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Grant button
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(red: 0.4, green: 0.85, blue: 0.7))
            } else {
                Button {
                    onRequest()
                } label: {
                    Text("Allow")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(iconColor.opacity(0.12))
                        )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.black.opacity(0.04), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 8, y: 2)
        )
    }
}

import AVFoundation
import UserNotifications

#Preview {
    BereanOnboardingView(isPresented: .constant(true))
}

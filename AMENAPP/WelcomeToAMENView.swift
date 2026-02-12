//
//  WelcomeToAMENView.swift
//  AMENAPP
//
//  Minimalist black & white glassmorphic welcome screen
//  Features: Clean design, smart animations, elegant transitions
//

import SwiftUI

struct WelcomeToAMENView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Animation states
    @State private var amenOpacity: Double = 0
    @State private var amenScale: CGFloat = 0.95
    @State private var amenTracking: CGFloat = 0
    @State private var taglineOpacity: Double = 0
    @State private var taglineOffset: CGFloat = 20
    @State private var messageOpacity: Double = 0
    @State private var messageScale: CGFloat = 0.95
    @State private var glassOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var buttonScale: CGFloat = 0.9
    @State private var subtleFloat: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Light gray background (matches the design)
            Color(red: 0.95, green: 0.95, blue: 0.95)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // AMEN Logo - Bold serif-style
                Text("AMEN")
                    .font(.system(size: 80, weight: .black, design: .serif))
                    .tracking(amenTracking)
                    .foregroundStyle(.black)
                    .opacity(amenOpacity)
                    .scaleEffect(amenScale)
                    .offset(y: subtleFloat)
                
                Spacer()
                    .frame(height: 60)
                
                // Tagline
                Text("Social Media, Re-ordered")
                    .font(.system(size: 14, weight: .light))
                    .tracking(3)
                    .foregroundStyle(.black.opacity(0.6))
                    .opacity(taglineOpacity)
                    .offset(y: taglineOffset)
                
                Spacer()
                    .frame(height: 80)
                
                // Welcome message card - Glassmorphic
                VStack(spacing: 20) {
                    Text("Welcome to Your Faith Community")
                        .font(.custom("OpenSans-Bold", size: 22))
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                    
                    Text("Join thousands of believers growing in faith, sharing testimonies, and building God's kingdom together.")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.black.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal, 20)
                }
                .padding(32)
                .background(
                    ZStack {
                        // Glass effect
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.ultraThinMaterial)
                        
                        // Subtle white overlay
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.6),
                                        Color.white.opacity(0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Border
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.8),
                                        Color.white.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                )
                .shadow(color: .black.opacity(0.08), radius: 30, y: 15)
                .shadow(color: .black.opacity(0.04), radius: 10, y: 5)
                .padding(.horizontal, 32)
                .opacity(messageOpacity)
                .scaleEffect(messageScale)
                .opacity(glassOpacity)
                
                Spacer()
                
                // CTA Button - Minimalist black
                Button {
                    // Haptic feedback
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                    
                    // Smooth dismiss
                    withAnimation(.easeOut(duration: 0.3)) {
                        amenOpacity = 0
                        taglineOpacity = 0
                        messageOpacity = 0
                        buttonOpacity = 0
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text("Let's Begin")
                            .font(.custom("OpenSans-Bold", size: 17))
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.black)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
                .opacity(buttonOpacity)
                .scaleEffect(buttonScale)
                .buttonStyle(MinimalScaleButtonStyle())
            }
        }
        .onAppear {
            startAnimationSequence()
            startContinuousAnimations()
        }
    }
    
    // MARK: - Animation Sequences
    
    private func startAnimationSequence() {
        // Phase 1: AMEN fades in and expands letter spacing (0.0-1.0s)
        withAnimation(.easeOut(duration: 1.0)) {
            amenOpacity = 1.0
            amenScale = 1.0
        }
        
        withAnimation(.easeOut(duration: 1.2).delay(0.2)) {
            amenTracking = 12
        }
        
        // Phase 2: Tagline slides up (1.0-1.5s)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.0)) {
            taglineOpacity = 1.0
            taglineOffset = 0
        }
        
        // Phase 3: Glass card fades and scales in (1.6-2.2s)
        withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(1.6)) {
            glassOpacity = 1.0
            messageOpacity = 1.0
            messageScale = 1.0
        }
        
        // Phase 4: Button appears (2.3-2.8s)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(2.3)) {
            buttonOpacity = 1.0
            buttonScale = 1.0
        }
    }
    
    private func startContinuousAnimations() {
        // Subtle floating animation for AMEN
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            subtleFloat = -5
        }
    }
}

// MARK: - Button Style

struct MinimalScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    WelcomeToAMENView()
}

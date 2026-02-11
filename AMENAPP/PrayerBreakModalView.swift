//
//  PrayerBreakModalView.swift
//  AMENAPP
//
//  Created by Steph on 1/31/26.
//
//  Glassmorphic modal for prayer break notifications
//

import SwiftUI

struct PrayerBreakModalView: View {
    @Environment(\.dismiss) var dismiss
    @State private var animate = false
    @State private var breatheAnimation = false
    
    let onPrayNow: () -> Void
    let onRemindLater: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        ZStack {
            // Dark background with blur
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        onSkip()
                    }
                }
            
            // Glassmorphic Modal
            VStack(spacing: 0) {
                // Modal pill indicator
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Top badge
                        Text("MODAL")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(.white.opacity(0.15))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .padding(.top, 16)
                        
                        // Main title
                        Text("Time for a Break")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        
                        // Animated breathing icon
                        ZStack {
                            // Pulsing circles
                            ForEach(0..<3) { index in
                                Circle()
                                    .stroke(lineWidth: 2)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 120 + CGFloat(index * 30), height: 120 + CGFloat(index * 30))
                                    .scaleEffect(breatheAnimation ? 1.2 : 0.8)
                                    .opacity(breatheAnimation ? 0 : 0.6)
                                    .animation(
                                        .easeInOut(duration: 2.5)
                                            .repeatForever(autoreverses: false)
                                            .delay(Double(index) * 0.3),
                                        value: breatheAnimation
                                    )
                            }
                            
                            // Center icon
                            Image(systemName: "hands.sparkles.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, .white.opacity(0.8)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .scaleEffect(breatheAnimation ? 1.1 : 1.0)
                                .animation(
                                    .easeInOut(duration: 2.5)
                                        .repeatForever(autoreverses: true),
                                    value: breatheAnimation
                                )
                        }
                        .frame(height: 200)
                        
                        // Description
                        Text("Step away from the screen and spend a moment in prayer with God. Let's take this time to refresh and reconnect.")
                            .font(.system(size: 17, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 32)
                        
                        // Action buttons
                        VStack(spacing: 12) {
                            // Primary: Pray Now
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    onPrayNow()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 18))
                                    Text("Pray Now")
                                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color.white.opacity(0.3),
                                                        Color.white.opacity(0.2)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                        
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(.white.opacity(0.4), lineWidth: 1.5)
                                    }
                                )
                                .shadow(color: .white.opacity(0.2), radius: 12, y: 6)
                            }
                            
                            // Secondary: Remind Later
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    onRemindLater()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: 18))
                                    Text("Remind me in 15 min")
                                        .font(.system(size: 18, weight: .medium, design: .rounded))
                                }
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(.white.opacity(0.12))
                                        
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                                    }
                                )
                            }
                            
                            // Tertiary: Skip
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    onSkip()
                                }
                            } label: {
                                Text("Not now")
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .padding(.vertical, 12)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
            .frame(maxWidth: 520)
            .background(
                ZStack {
                    // Glass base
                    RoundedRectangle(cornerRadius: 32)
                        .fill(.ultraThinMaterial)
                    
                    // Dark overlay for contrast
                    RoundedRectangle(cornerRadius: 32)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.3),
                                    Color.black.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Subtle noise texture effect
                    RoundedRectangle(cornerRadius: 32)
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.03),
                                    Color.clear
                                ],
                                center: .topLeading,
                                startRadius: 100,
                                endRadius: 400
                            )
                        )
                    
                    // Glass border
                    RoundedRectangle(cornerRadius: 32)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            )
            .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20)
            .padding(.horizontal, 24)
            .scaleEffect(animate ? 1.0 : 0.9)
            .opacity(animate ? 1.0 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                animate = true
            }
            breatheAnimation = true
        }
    }
}

// MARK: - Preview

#Preview {
    PrayerBreakModalView(
        onPrayNow: { print("Pray Now") },
        onRemindLater: { print("Remind Later") },
        onSkip: { print("Skip") }
    )
}

//
//  PrayerBreakModalView.swift
//  AMENAPP
//
//  Created by Steph on 1/31/26.
//
//  Compact liquid glass modal for prayer break notifications
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
            // Blurred background with dark overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        onSkip()
                    }
                }
            
            // Compact Liquid Glass Modal
            VStack(spacing: 24) {
                // Icon with breathing animation
                Image(systemName: "hands.sparkles.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.white)
                    .scaleEffect(breatheAnimation ? 1.08 : 1.0)
                    .animation(
                        .easeInOut(duration: 2.5)
                            .repeatForever(autoreverses: true),
                        value: breatheAnimation
                    )
                    .padding(.top, 8)
                
                // Compact title
                Text("Time for a Break")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                // Concise message
                Text("Take a moment to step away and reconnect with God in prayer.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 8)
                
                // Compact action buttons
                VStack(spacing: 12) {
                    // Primary: Pray Now
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            onPrayNow()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Pray Now")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    
                    // Secondary: Remind Later
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            onRemindLater()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 14, weight: .medium))
                            Text("Remind in 15 min")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    
                    // Tertiary: Skip
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            onSkip()
                        }
                    } label: {
                        Text("Not now")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32)
                            .stroke(.white.opacity(0.2), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 10)
            )
            .padding(.horizontal, 32)
            .scaleEffect(animate ? 1.0 : 0.85)
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

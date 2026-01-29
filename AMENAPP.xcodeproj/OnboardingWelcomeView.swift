//
//  OnboardingWelcomeView.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import SwiftUI

/// Welcome screen - First step of onboarding
struct OnboardingWelcomeView: View {
    @EnvironmentObject var coordinator: OnboardingCoordinator
    @State private var showAnimation = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Animated icon
            ZStack {
                // Outer glow rings
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 140 + CGFloat(index * 30), height: 140 + CGFloat(index * 30))
                        .opacity(showAnimation ? 0.0 : 0.8)
                        .scaleEffect(showAnimation ? 1.4 : 1.0)
                        .animation(
                            .easeOut(duration: 2.0)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.3),
                            value: showAnimation
                        )
                }
                
                // Main icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                        .shadow(color: .blue.opacity(0.4), radius: 20, y: 10)
                    
                    Image(systemName: "hands.sparkles")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                }
                .scaleEffect(showAnimation ? 1.0 : 0.8)
                .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showAnimation)
            }
            .padding(.bottom, 20)
            
            // Title
            VStack(spacing: 12) {
                Text("Welcome to AMEN")
                    .font(.custom("OpenSans-Bold", size: 36))
                    .foregroundStyle(.black)
                    .opacity(showAnimation ? 1.0 : 0.0)
                    .offset(y: showAnimation ? 0 : 20)
                    .animation(.easeOut(duration: 0.6).delay(0.2), value: showAnimation)
                
                Text("A community of faith, prayer, and testimony")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(showAnimation ? 1.0 : 0.0)
                    .offset(y: showAnimation ? 0 : 20)
                    .animation(.easeOut(duration: 0.6).delay(0.4), value: showAnimation)
            }
            
            Spacer()
            
            // Features list
            VStack(spacing: 20) {
                FeatureRow(
                    icon: "hands.clap.fill",
                    title: "Pray Together",
                    description: "Share and support prayer requests"
                )
                .opacity(showAnimation ? 1.0 : 0.0)
                .offset(x: showAnimation ? 0 : -20)
                .animation(.easeOut(duration: 0.6).delay(0.6), value: showAnimation)
                
                FeatureRow(
                    icon: "heart.fill",
                    title: "Share Testimonies",
                    description: "Inspire others with your faith journey"
                )
                .opacity(showAnimation ? 1.0 : 0.0)
                .offset(x: showAnimation ? 0 : -20)
                .animation(.easeOut(duration: 0.6).delay(0.8), value: showAnimation)
                
                FeatureRow(
                    icon: "person.3.fill",
                    title: "Connect",
                    description: "Build meaningful relationships in faith"
                )
                .opacity(showAnimation ? 1.0 : 0.0)
                .offset(x: showAnimation ? 0 : -20)
                .animation(.easeOut(duration: 0.6).delay(1.0), value: showAnimation)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
        .onAppear {
            showAnimation = true
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.15), .purple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.black)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.black.opacity(0.6))
            }
            
            Spacer()
        }
    }
}

#Preview {
    OnboardingWelcomeView()
        .environmentObject(OnboardingCoordinator())
}

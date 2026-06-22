//
//  OnboardingCompletionView.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import SwiftUI

struct OnboardingCompletionView: View {
    @EnvironmentObject var coordinator: OnboardingCoordinator
    @State private var showAnimation = false
    @State private var showConfetti = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                Spacer()
                
                // Animated success icon
                ZStack {
                    // Outer glow rings
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.green.opacity(0.3), .blue.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                            .frame(width: 160 + CGFloat(index * 40), height: 160 + CGFloat(index * 40))
                            .opacity(showAnimation ? 0.0 : 1.0)
                            .scaleEffect(showAnimation ? 1.8 : 1.0)
                            .animation(
                                .easeOut(duration: 1.5)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.2),
                                value: showAnimation
                            )
                    }
                    
                    // Main success icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.green, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 160, height: 160)
                            .shadow(color: .green.opacity(0.4), radius: 20, y: 10)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 72, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(showAnimation ? 1.0 : 0.0)
                    .rotationEffect(.degrees(showAnimation ? 0 : -180))
                    .animation(.spring(response: 0.8, dampingFraction: 0.6), value: showAnimation)
                }
                .padding(.bottom, 20)
                
                // Completion message
                VStack(spacing: 16) {
                    Text("Welcome to AMEN!")
                        .font(.custom("OpenSans-Bold", size: 36))
                        .foregroundStyle(.black)
                        .opacity(showAnimation ? 1.0 : 0.0)
                        .offset(y: showAnimation ? 0 : 20)
                        .animation(.easeOut(duration: 0.6).delay(0.3), value: showAnimation)
                    
                    VStack(spacing: 8) {
                        Text("You're all set, \(coordinator.userData.displayName)!")
                            .font(.custom("OpenSans-SemiBold", size: 18))
                            .foregroundStyle(.black)
                        
                        Text("Join thousands of believers in faith, prayer, and testimony")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.black.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 40)
                    .opacity(showAnimation ? 1.0 : 0.0)
                    .offset(y: showAnimation ? 0 : 20)
                    .animation(.easeOut(duration: 0.6).delay(0.5), value: showAnimation)
                }
                
                // Stats/Highlights
                HStack(spacing: 24) {
                    CompletionStatCard(
                        icon: "person.3.fill",
                        value: "10K+",
                        label: "Members"
                    )
                    
                    CompletionStatCard(
                        icon: "hands.clap.fill",
                        value: "50K+",
                        label: "Prayers"
                    )
                    
                    CompletionStatCard(
                        icon: "heart.fill",
                        value: "5K+",
                        label: "Testimonies"
                    )
                }
                .padding(.horizontal, 20)
                .opacity(showAnimation ? 1.0 : 0.0)
                .offset(y: showAnimation ? 0 : 20)
                .animation(.easeOut(duration: 0.6).delay(0.7), value: showAnimation)
                
                Spacer()
                
                // Quick tips
                VStack(spacing: 16) {
                    Text("Quick Tips")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.black)
                    
                    VStack(spacing: 12) {
                        TipRow(icon: "plus.circle.fill", text: "Share your first testimony or prayer")
                        TipRow(icon: "person.badge.plus.fill", text: "Connect with other believers")
                        TipRow(icon: "bell.fill", text: "Turn on notifications to stay updated")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .opacity(showAnimation ? 1.0 : 0.0)
                .offset(y: showAnimation ? 0 : 20)
                .animation(.easeOut(duration: 0.6).delay(0.9), value: showAnimation)
            }
            
            // Simple confetti effect
            if showConfetti {
                ConfettiView()
            }
        }
        .onAppear {
            // Trigger animations
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showAnimation = true
                showConfetti = true
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
            
            // Hide confetti after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    showConfetti = false
                }
            }
        }
    }
}

// Simple confetti effect without external package
struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    ConfettiPiece(particle: particle)
                }
            }
            .onAppear {
                createParticles(in: geometry.size)
            }
        }
        .allowsHitTesting(false)
    }
    
    private func createParticles(in size: CGSize) {
        particles = (0..<50).map { _ in
            ConfettiParticle(
                x: CGFloat.random(in: 0...size.width),
                y: -20,
                color: [Color.blue, Color.purple, Color.green, Color.yellow, Color.pink].randomElement()!,
                size: CGFloat.random(in: 6...12)
            )
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let color: Color
    let size: CGFloat
}

struct ConfettiPiece: View {
    let particle: ConfettiParticle
    @State private var yOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1
    
    var body: some View {
        Circle()
            .fill(particle.color)
            .frame(width: particle.size, height: particle.size)
            .position(x: particle.x, y: particle.y + yOffset)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .onAppear {
                withAnimation(.linear(duration: 3.0)) {
                    yOffset = UIScreen.main.bounds.height + 100
                    rotation = Double.random(in: 0...720)
                    opacity = 0
                }
            }
    }
}

struct CompletionStatCard: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(value)
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.black)
            
            Text(label)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.black.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
    }
}

struct TipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 24)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.black)
            
            Spacer()
        }
    }
}

#Preview {
    OnboardingCompletionView()
        .environmentObject(OnboardingCoordinator())
}

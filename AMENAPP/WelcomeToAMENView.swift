//
//  WelcomeToAMENView.swift
//  AMENAPP
//
//  Created by Assistant on 2/2/26.
//
//  Exciting animated welcome screen shown after feedback/completion
//  Features: Particle effects, dynamic animations, inspiring messaging
//

import SwiftUI

struct WelcomeToAMENView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var animationPhase: AnimationPhase = .initial
    @State private var particles: [Particle] = []
    @State private var glowIntensity: CGFloat = 0
    @State private var letterOffsets: [CGFloat] = Array(repeating: -100, count: 4) // A-M-E-N
    @State private var letterRotations: [Double] = Array(repeating: 0, count: 4)
    @State private var letterScales: [CGFloat] = Array(repeating: 0, count: 4)
    @State private var showTagline = false
    @State private var showMessage = false
    @State private var showCTA = false
    @State private var breathingScale: CGFloat = 1.0
    @State private var rotatingGradient: Double = 0
    
    enum AnimationPhase {
        case initial
        case lettersDrop
        case lettersAssemble
        case glowReveal
        case contentReveal
        case complete
    }
    
    // Gradient colors for dynamic background
    private let gradientColors: [Color] = [
        Color(red: 0.6, green: 0.5, blue: 1.0),   // Purple
        Color(red: 0.4, green: 0.7, blue: 1.0),   // Blue
        Color(red: 1.0, green: 0.7, blue: 0.4),   // Orange
        Color(red: 0.4, green: 0.85, blue: 0.7),  // Teal
        Color(red: 1.0, green: 0.6, blue: 0.7)    // Pink
    ]
    
    var body: some View {
        ZStack {
            // Dynamic gradient background
            AnimatedGradientBackground(rotation: rotatingGradient)
                .ignoresSafeArea()
            
            // Particle system overlay
            ParticleSystemView(particles: $particles)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            
            // Main content
            VStack(spacing: 0) {
                Spacer()
                
                // AMEN Logo Animation
                amenLogoSection
                    .padding(.vertical, 40)
                
                // Tagline
                if showTagline {
                    taglineSection
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                Spacer()
                
                // Welcome Message
                if showMessage {
                    welcomeMessageSection
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                Spacer()
                
                // CTA Button
                if showCTA {
                    ctaButton
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 60)
                }
            }
        }
        .onAppear {
            startAnimationSequence()
            generateParticles()
            startContinuousAnimations()
        }
    }
    
    // MARK: - AMEN Logo Section
    
    private var amenLogoSection: some View {
        ZStack {
            // Outer glow rings
            ForEach(0..<3) { index in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 200 + CGFloat(index * 40), height: 200 + CGFloat(index * 40))
                    .opacity(glowIntensity * (0.5 - Double(index) * 0.15))
                    .scaleEffect(breathingScale)
                    .blur(radius: 2)
            }
            
            // Inner glow circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.4 * glowIntensity),
                            .white.opacity(0.2 * glowIntensity),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .blur(radius: 20)
                .scaleEffect(breathingScale)
            
            // AMEN Letters
            HStack(spacing: 4) {
                // A
                letterView(letter: "A", index: 0, color: Color(red: 0.6, green: 0.5, blue: 1.0))
                
                // M
                letterView(letter: "M", index: 1, color: Color(red: 0.4, green: 0.7, blue: 1.0))
                
                // E
                letterView(letter: "E", index: 2, color: Color(red: 1.0, green: 0.7, blue: 0.4))
                
                // N
                letterView(letter: "N", index: 3, color: Color(red: 0.4, green: 0.85, blue: 0.7))
            }
        }
    }
    
    private func letterView(letter: String, index: Int, color: Color) -> some View {
        ZStack {
            // Shadow/glow effect
            Text(letter)
                .font(.custom("OpenSans-ExtraBold", size: 72))
                .foregroundStyle(color)
                .blur(radius: 8)
                .opacity(0.6 * glowIntensity)
            
            // Main letter
            Text(letter)
                .font(.custom("OpenSans-ExtraBold", size: 72))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, color.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: color.opacity(0.5), radius: 10, y: 5)
        }
        .offset(y: letterOffsets[index])
        .rotationEffect(.degrees(letterRotations[index]))
        .scaleEffect(letterScales[index])
    }
    
    // MARK: - Tagline Section
    
    private var taglineSection: some View {
        VStack(spacing: 8) {
            Text("Welcome to")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.white.opacity(0.8))
            
            Text("Your Faith Community")
                .font(.custom("OpenSans-Bold", size: 24))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        }
        .scaleEffect(showTagline ? 1.0 : 0.8)
        .opacity(showTagline ? 1.0 : 0)
    }
    
    // MARK: - Welcome Message Section
    
    private var welcomeMessageSection: some View {
        VStack(spacing: 24) {
            // Main welcome card
            VStack(spacing: 16) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(red: 1.0, green: 0.6, blue: 0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .pink.opacity(0.5), radius: 10, y: 5)
                    .symbolEffect(.pulse)
                
                Text("You're Part of Something Special")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
                
                Text("Join thousands of believers growing in faith, sharing testimonies, and building God's kingdom together through innovation and community.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 20)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
            .padding(.horizontal, 24)
            
            // Quick feature highlights
            HStack(spacing: 16) {
                FeatureHighlight(
                    icon: "brain.head.profile",
                    title: "AI Study",
                    color: Color(red: 0.6, green: 0.5, blue: 1.0)
                )
                
                FeatureHighlight(
                    icon: "hands.sparkles.fill",
                    title: "Prayer",
                    color: Color(red: 1.0, green: 0.7, blue: 0.4)
                )
                
                FeatureHighlight(
                    icon: "person.3.fill",
                    title: "Community",
                    color: Color(red: 0.4, green: 0.85, blue: 0.7)
                )
            }
            .padding(.horizontal, 24)
        }
        .scaleEffect(showMessage ? 1.0 : 0.9)
        .opacity(showMessage ? 1.0 : 0)
    }
    
    // MARK: - CTA Button
    
    private var ctaButton: some View {
        Button {
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            // Confetti burst
            generateConfetti()
            
            // Delay dismiss for confetti effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Text("Let's Begin!")
                    .font(.custom("OpenSans-Bold", size: 20))
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 24, weight: .bold))
            }
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 0.6, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.8), .white.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .scaleEffect(showCTA ? 1.0 : 0.8)
            .shadow(color: Color(red: 0.6, green: 0.5, blue: 1.0).opacity(0.5), radius: 20, y: 10)
        }
        .padding(.horizontal, 32)
        .buttonStyle(ScaleButtonStyle())
    }
    
    // MARK: - Animation Sequences
    
    private func startAnimationSequence() {
        // Phase 1: Letters drop in (0.8s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            animateLettersDrop()
        }
        
        // Phase 2: Letters assemble and glow (1.0s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animationPhase = .lettersAssemble
            }
            animateGlowReveal()
        }
        
        // Phase 3: Tagline appears (0.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showTagline = true
            }
        }
        
        // Phase 4: Welcome message (0.6s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showMessage = true
            }
        }
        
        // Phase 5: CTA button (0.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.9) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showCTA = true
                animationPhase = .complete
            }
        }
    }
    
    private func animateLettersDrop() {
        let delays: [Double] = [0.0, 0.1, 0.2, 0.3]
        
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delays[i]) {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                    letterOffsets[i] = 0
                    letterRotations[i] = 360
                    letterScales[i] = 1.0
                }
            }
        }
    }
    
    private func animateGlowReveal() {
        withAnimation(.easeInOut(duration: 1.0)) {
            glowIntensity = 1.0
        }
    }
    
    private func startContinuousAnimations() {
        // Breathing effect
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            breathingScale = 1.1
        }
        
        // Rotating gradient
        withAnimation(.linear(duration: 10.0).repeatForever(autoreverses: false)) {
            rotatingGradient = 360
        }
    }
    
    // MARK: - Particle System
    
    private func generateParticles() {
        particles = (0..<30).map { _ in
            Particle(
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                ),
                velocity: CGPoint(
                    x: CGFloat.random(in: -0.5...0.5),
                    y: CGFloat.random(in: -1...(0.5))
                ),
                size: CGFloat.random(in: 2...6),
                color: gradientColors.randomElement() ?? .white,
                opacity: Double.random(in: 0.3...0.7)
            )
        }
        
        // Start particle animation
        animateParticles()
    }
    
    private func animateParticles() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            particles = particles.map { particle in
                var updatedParticle = particle
                updatedParticle.position.x += particle.velocity.x
                updatedParticle.position.y += particle.velocity.y
                
                // Wrap around screen
                if updatedParticle.position.y < 0 {
                    updatedParticle.position.y = UIScreen.main.bounds.height
                    updatedParticle.position.x = CGFloat.random(in: 0...UIScreen.main.bounds.width)
                }
                
                if updatedParticle.position.x < 0 {
                    updatedParticle.position.x = UIScreen.main.bounds.width
                }
                
                if updatedParticle.position.x > UIScreen.main.bounds.width {
                    updatedParticle.position.x = 0
                }
                
                return updatedParticle
            }
        }
    }
    
    private func generateConfetti() {
        let confettiColors: [Color] = [
            Color(red: 0.6, green: 0.5, blue: 1.0),
            Color(red: 0.4, green: 0.7, blue: 1.0),
            Color(red: 1.0, green: 0.7, blue: 0.4),
            Color(red: 0.4, green: 0.85, blue: 0.7),
            Color(red: 1.0, green: 0.6, blue: 0.7)
        ]
        
        // Generate confetti particles from center
        let centerX = UIScreen.main.bounds.width / 2
        let centerY = UIScreen.main.bounds.height / 2
        
        let confettiParticles = (0..<50).map { _ in
            Particle(
                position: CGPoint(x: centerX, y: centerY),
                velocity: CGPoint(
                    x: CGFloat.random(in: -5...5),
                    y: CGFloat.random(in: -8...(-2))
                ),
                size: CGFloat.random(in: 4...8),
                color: confettiColors.randomElement() ?? .white,
                opacity: 1.0
            )
        }
        
        particles.append(contentsOf: confettiParticles)
    }
}

// MARK: - Supporting Views

struct FeatureHighlight: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle()
                            .stroke(color.opacity(0.4), lineWidth: 2)
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(color)
            }
            
            Text(title)
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            color.opacity(0.3),
                            lineWidth: 1
                        )
                )
        )
    }
}

struct AnimatedGradientBackground: View {
    let rotation: Double
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.2, green: 0.1, blue: 0.4),
                    Color(red: 0.4, green: 0.2, blue: 0.6),
                    Color(red: 0.1, green: 0.3, blue: 0.5),
                    Color(red: 0.3, green: 0.1, blue: 0.5)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .hueRotation(.degrees(rotation))
            
            // Overlay with animated circles
            GeometryReader { geometry in
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.6, green: 0.5, blue: 1.0).opacity(0.3), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 400, height: 400)
                        .offset(x: -100, y: -100)
                        .blur(radius: 60)
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 1.0, green: 0.7, blue: 0.4).opacity(0.3), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 400, height: 400)
                        .offset(x: geometry.size.width - 100, y: geometry.size.height - 100)
                        .blur(radius: 60)
                }
            }
        }
    }
}

struct ParticleSystemView: View {
    @Binding var particles: [Particle]
    
    var body: some View {
        GeometryReader { _ in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .opacity(particle.opacity)
                        .frame(width: particle.size, height: particle.size)
                        .position(particle.position)
                        .blur(radius: 1)
                }
            }
        }
    }
}

// MARK: - Models

struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGPoint
    var size: CGFloat
    var color: Color
    var opacity: Double
}

// MARK: - Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    WelcomeToAMENView()
}

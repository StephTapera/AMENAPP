//
//  WelcomeValuesView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//

import SwiftUI

/// Animated welcome screen showcasing AMEN's core values and policies
/// Displays for ~5 seconds with smart animations before transitioning to main app
struct WelcomeValuesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPhase: AnimationPhase = .initial
    @State private var valueIndex = 0
    @State private var showPolicies = false
    @State private var progress: CGFloat = 0
    
    private let values: [CoreValue] = [
        CoreValue(
            icon: "book.pages.fill",
            title: "God's Word",
            subtitle: "Rooted in Scripture",
            description: "Every feature, conversation, and connection is anchored in biblical truth and wisdom.",
            color: Color(red: 0.6, green: 0.5, blue: 1.0), // Purple
            accentColor: Color(red: 0.7, green: 0.6, blue: 1.0)
        ),
        CoreValue(
            icon: "person.3.fill",
            title: "Community",
            subtitle: "United in Faith",
            description: "Building authentic relationships where believers encourage, support, and grow together.",
            color: Color(red: 0.4, green: 0.85, blue: 0.7), // Teal
            accentColor: Color(red: 0.5, green: 0.95, blue: 0.8)
        ),
        CoreValue(
            icon: "hands.and.sparkles.fill",
            title: "Prayer",
            subtitle: "Connect With God",
            description: "Share prayer requests, pray together, and witness answered prayers as a community of faith.",
            color: Color(red: 1.0, green: 0.6, blue: 0.4), // Coral/Orange
            accentColor: Color(red: 1.0, green: 0.7, blue: 0.5)
        ),
        CoreValue(
            icon: "shield.checkered.fill",
            title: "Safety",
            subtitle: "Protected & Secure",
            description: "Your privacy matters. We create a safe space for authentic faith conversations without judgment.",
            color: Color(red: 0.3, green: 0.8, blue: 0.4), // Green
            accentColor: Color(red: 0.4, green: 0.9, blue: 0.5)
        ),
        CoreValue(
            icon: "brain.head.profile",
            title: "Intelligence",
            subtitle: "Wisdom Meets Innovation",
            description: "Leveraging technology thoughtfully to deepen faith and enhance ministry impact.",
            color: Color(red: 0.4, green: 0.7, blue: 1.0), // Blue
            accentColor: Color(red: 0.5, green: 0.8, blue: 1.0)
        )
    ]
    
    enum AnimationPhase {
        case initial
        case logoReveal
        case valuesDisplay
        case policiesReveal
        case completion
    }
    
    var body: some View {
        ZStack {
            // Background with gradient
            backgroundGradient
            
            // Main content
            VStack(spacing: 0) {
                Spacer()
                
                // Logo and Title Section
                if currentPhase != .initial {
                    logoSection
                        .transition(.scale.combined(with: .opacity))
                }
                
                Spacer()
                
                // Values Carousel
                if currentPhase == .valuesDisplay || currentPhase == .policiesReveal {
                    valuesCarousel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                Spacer()
                
                // Policies Section
                if currentPhase == .policiesReveal || currentPhase == .completion {
                    policiesSection
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Progress indicator
                if currentPhase != .completion {
                    progressBar
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            startAnimationSequence()
        }
    }
    
    // MARK: - Background Gradient
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                currentPhase == .initial ? Color(.systemBackground) : values[valueIndex].color.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: currentPhase)
        .animation(.easeInOut(duration: 0.6), value: valueIndex)
    }
    
    // MARK: - Logo Section
    
    private var logoSection: some View {
        VStack(spacing: 16) {
            // Animated logo
            ZStack {
                // Outer glow rings
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(
                            values[valueIndex].color.opacity(0.2),
                            lineWidth: 2
                        )
                        .frame(width: 80 + CGFloat(index * 20), height: 80 + CGFloat(index * 20))
                        .scaleEffect(currentPhase == .logoReveal ? 1.0 : 0.5)
                        .opacity(currentPhase == .logoReveal ? 0.3 - (Double(index) * 0.1) : 0)
                        .animation(
                            .easeOut(duration: 0.8)
                                .delay(Double(index) * 0.1),
                            value: currentPhase
                        )
                }
                
                // Main logo circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                values[valueIndex].color.opacity(0.2),
                                values[valueIndex].accentColor.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(
                                values[valueIndex].color.opacity(0.4),
                                lineWidth: 2
                            )
                    )
                    .scaleEffect(currentPhase == .logoReveal ? 1.0 : 0.8)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: currentPhase)
                
                // AMEN text
                Text("AMEN")
                    .font(.custom("OpenSans-Bold", size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [values[valueIndex].color, values[valueIndex].accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .scaleEffect(currentPhase == .logoReveal ? 1.0 : 0.5)
                    .opacity(currentPhase == .logoReveal ? 1.0 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2), value: currentPhase)
            }
            
            // Tagline
            Text("Where Faith Meets Innovation")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .opacity(currentPhase == .logoReveal ? 1.0 : 0)
                .offset(y: currentPhase == .logoReveal ? 0 : 20)
                .animation(.easeOut(duration: 0.5).delay(0.4), value: currentPhase)
        }
    }
    
    // MARK: - Values Carousel
    
    private var valuesCarousel: some View {
        let currentValue = values[valueIndex]
        
        return VStack(spacing: 20) {
            // Icon with glow effect
            ZStack {
                // Glow
                Circle()
                    .fill(currentValue.color.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)
                    .scaleEffect(1.2)
                
                // Icon background
                Circle()
                    .fill(currentValue.color.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                // Icon
                Image(systemName: currentValue.icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(currentValue.color)
                    .symbolEffect(.bounce, value: valueIndex)
            }
            .scaleEffect(currentPhase == .valuesDisplay ? 1.0 : 0.8)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: currentPhase)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: valueIndex)
            
            // Value title
            VStack(spacing: 8) {
                Text(currentValue.title)
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.primary)
                
                Text(currentValue.subtitle)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(currentValue.color)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(currentValue.color.opacity(0.15))
                    )
            }
            .opacity(currentPhase == .valuesDisplay ? 1.0 : 0)
            .offset(y: currentPhase == .valuesDisplay ? 0 : 20)
            .animation(.easeOut(duration: 0.4).delay(0.2), value: currentPhase)
            .animation(.easeOut(duration: 0.4), value: valueIndex)
            
            // Description
            Text(currentValue.description)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
                .opacity(currentPhase == .valuesDisplay ? 1.0 : 0)
                .offset(y: currentPhase == .valuesDisplay ? 0 : 20)
                .animation(.easeOut(duration: 0.4).delay(0.3), value: currentPhase)
                .animation(.easeOut(duration: 0.4), value: valueIndex)
            
            // Value indicators (dots)
            HStack(spacing: 8) {
                ForEach(0..<values.count, id: \.self) { index in
                    Circle()
                        .fill(index == valueIndex ? values[valueIndex].color : Color.gray.opacity(0.3))
                        .frame(width: index == valueIndex ? 8 : 6, height: index == valueIndex ? 8 : 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: valueIndex)
                }
            }
            .padding(.top, 8)
        }
        .id(valueIndex) // Force re-render on value change
    }
    
    // MARK: - Policies Section
    
    private var policiesSection: some View {
        VStack(spacing: 16) {
            // Divider with icon
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 1)
                
                Image(systemName: "shield.checkered")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.gray)
                
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 1)
            }
            .padding(.horizontal, 40)
            .opacity(currentPhase == .policiesReveal ? 1.0 : 0)
            .animation(.easeIn(duration: 0.3), value: currentPhase)
            
            // Policy links
            VStack(spacing: 12) {
                PolicyLink(icon: "hand.raised.fill", text: "Community Guidelines", color: .blue)
                PolicyLink(icon: "lock.shield.fill", text: "Privacy & Safety", color: .green)
                PolicyLink(icon: "checkmark.seal.fill", text: "Terms of Service", color: .orange)
                PolicyLink(icon: "person.fill.checkmark", text: "Be Authentic - No AI Posts", color: .purple)
            }
            .opacity(currentPhase == .policiesReveal ? 1.0 : 0)
            .offset(y: currentPhase == .policiesReveal ? 0 : 20)
            .animation(.easeOut(duration: 0.4).delay(0.1), value: currentPhase)
            
            // Agreement text
            Text("By continuing, you agree to our community standards rooted in biblical values. We encourage authentic, heartfelt posts written by you, not AI.")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 8)
                .opacity(currentPhase == .policiesReveal ? 1.0 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.2), value: currentPhase)
        }
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 4)
                
                // Progress fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [values[valueIndex].color, values[valueIndex].accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress, height: 4)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .frame(height: 4)
    }
    
    // MARK: - Animation Sequence
    
    private func startAnimationSequence() {
        // Phase 1: Logo reveal (1.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation {
                currentPhase = .logoReveal
            }
            startProgressAnimation(duration: 1.5)
        }
        
        // Phase 2: Values display - cycle through all 5 values (15s total, 3s each)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation {
                currentPhase = .valuesDisplay
            }
            cycleValues()
        }
        
        // Phase 3: Policies reveal (2.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 16.8) {
            withAnimation {
                currentPhase = .policiesReveal
            }
            startProgressAnimation(duration: 2.5, startingFrom: 0.88)
        }
        
        // Phase 4: Completion and dismiss (after 20s total)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) {
            withAnimation {
                currentPhase = .completion
            }
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            // Dismiss after a brief moment
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                dismiss()
            }
        }
    }
    
    private func cycleValues() {
        // Show first value immediately
        valueIndex = 0
        
        // Cycle through values every 3 seconds
        for i in 1..<values.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 3.0) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    valueIndex = i
                }
            }
        }
    }
    
    private func startProgressAnimation(duration: TimeInterval, startingFrom: CGFloat = 0) {
        let steps = 60
        let increment = (1.0 - startingFrom) / CGFloat(steps)
        let stepDuration = duration / Double(steps)
        
        for step in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(step)) {
                progress = startingFrom + (increment * CGFloat(step))
            }
        }
    }
}

// MARK: - Core Value Model

struct CoreValue: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let description: String
    let color: Color
    let accentColor: Color
}

// MARK: - Policy Link Component

struct PolicyLink: View {
    let icon: String
    let text: String
    let color: Color
    
    @State private var isPressed = false
    
    var body: some View {
        Button {
            // Open policy detail
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 24)
                
                Text(text)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 40)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeIn(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Preview

#Preview {
    WelcomeValuesView()
}

//
//  CoachMarkOverlay.swift
//  AMENAPP
//
//  Premium glassmorphic coach marks overlay with animations
//

import SwiftUI

/// Main coach marks overlay that coordinates the FTUE experience
struct CoachMarkOverlay: View {
    @ObservedObject var ftueManager: FTUEManager
    @Namespace private var animation
    
    @State private var showContent = false
    @State private var spotlightScale: CGFloat = 0.8
    @State private var pulseAnimation = false
    
    // Target frames for spotlights (passed from parent)
    let postCardFrame: CGRect?
    let bereanButtonFrame: CGRect?
    
    var body: some View {
        ZStack {
            // Dimmed background with cutout (non-interactive)
            if let targetFrame = currentTargetFrame {
                dimmedBackgroundWithCutout(targetFrame: targetFrame)
                    .allowsHitTesting(false)  // Allow scroll through dimmed area
            } else {
                Color.black.opacity(0.75)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .allowsHitTesting(false)  // Allow scroll through dimmed area
            }
            
            // Spotlight border effect (non-interactive)
            if let targetFrame = currentTargetFrame {
                spotlightView(for: targetFrame)
                    .allowsHitTesting(false)  // Allow scroll through spotlight area
            }
            
            // ✅ FIX: Position card directly without VStack/Spacers that could block scrolls
            // Use GeometryReader only for positioning, card remains interactive for buttons
            GeometryReader { geometry in
                if let targetFrame = currentTargetFrame, shouldPositionCardBelow(targetFrame) {
                    // Position card below spotlight
                    coachMarkCard
                        .padding(.horizontal, 24)
                        .position(
                            x: geometry.size.width / 2,
                            y: min(targetFrame.maxY + 180, geometry.size.height - 200)
                        )
                } else {
                    // Center card in bottom half
                    coachMarkCard
                        .padding(.horizontal, 24)
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height * 0.65
                        )
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                showContent = true
                spotlightScale = 1.0
            }
            startPulseAnimation()
        }
    }
    
    // MARK: - Dimmed Background with Cutout
    
    private func dimmedBackgroundWithCutout(targetFrame: CGRect) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.75))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .frame(width: targetFrame.width + 16, height: targetFrame.height + 16)
                    .position(x: targetFrame.midX, y: targetFrame.midY)
                    .blendMode(.destinationOut)
            )
            .compositingGroup()
            .ignoresSafeArea()
            .transition(.opacity)
    }
    
    // MARK: - Current Target Frame
    
    private var currentTargetFrame: CGRect? {
        switch ftueManager.currentStep {
        case .swipeLeft, .swipeRight:
            return postCardFrame ?? defaultPostCardFrame
        case .bereanIntro:
            return bereanButtonFrame ?? defaultBereanButtonFrame
        }
    }
    
    private var defaultPostCardFrame: CGRect {
        // Fallback position for post card (centered, typical size)
        let screenWidth = UIScreen.main.bounds.width
        let cardWidth = screenWidth - 40
        let cardHeight: CGFloat = 400
        return CGRect(x: 20, y: 200, width: cardWidth, height: cardHeight)
    }
    
    private var defaultBereanButtonFrame: CGRect {
        // Fallback position for Berean button (top right)
        let screenWidth = UIScreen.main.bounds.width
        return CGRect(x: screenWidth - 60, y: 60, width: 38, height: 38)
    }
    
    // MARK: - Spotlight View
    
    private func spotlightView(for frame: CGRect) -> some View {
        ZStack {
            // Cutout rectangle with glow
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.8), lineWidth: 3)
                .frame(width: frame.width + 16, height: frame.height + 16)
                .position(x: frame.midX, y: frame.midY)
                .shadow(color: .white.opacity(0.4), radius: 20)
                .shadow(color: .white.opacity(0.2), radius: 40)
                .scaleEffect(pulseAnimation ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
            
            // Animated gesture demo
            if ftueManager.currentStep == .swipeLeft || ftueManager.currentStep == .swipeRight {
                SwipeGestureDemo(direction: ftueManager.currentStep == .swipeLeft ? .left : .right)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .scaleEffect(spotlightScale)
    }
    
    // MARK: - Coach Mark Card
    
    private var coachMarkCard: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.3),
                                Color.blue.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                    )
                    .frame(width: 60, height: 60)
                    .shadow(color: .blue.opacity(0.3), radius: 15)
                
                Image(systemName: ftueManager.currentStep.icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }
            .scaleEffect(showContent ? 1.0 : 0.5)
            .opacity(showContent ? 1 : 0)
            
            // Title
            Text(ftueManager.currentStep.title)
                .font(.custom("OpenSans-Bold", size: 24))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .offset(y: showContent ? 0 : 20)
                .opacity(showContent ? 1 : 0)
            
            // Description
            Text(ftueManager.currentStep.description)
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 16)
                .offset(y: showContent ? 0 : 20)
                .opacity(showContent ? 1 : 0)
            
            // Buttons
            HStack(spacing: 12) {
                // Skip button (except on last step)
                if ftueManager.currentStep != .bereanIntro {
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            ftueManager.skipFTUE()
                        }
                    } label: {
                        Text("Skip")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                
                // Primary action button
                Button {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        showContent = false
                        spotlightScale = 0.8
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        ftueManager.nextStep()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            showContent = true
                            spotlightScale = 1.0
                        }
                    }
                } label: {
                    Text(ftueManager.currentStep.primaryButtonText)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white)
                                .shadow(color: .white.opacity(0.3), radius: 10)
                        )
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, 4)
            .offset(y: showContent ? 0 : 30)
            .opacity(showContent ? 1 : 0)
            
            // Progress indicator
            progressIndicator
                .offset(y: showContent ? 0 : 20)
                .opacity(showContent ? 1 : 0)
        }
        .padding(28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tutorial step \(ftueManager.currentStep.rawValue + 1) of 3: \(ftueManager.currentStep.title)")
        .accessibilityHint(ftueManager.currentStep.description)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.85),
                            Color.black.opacity(0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.08),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        )
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(CoachMarkStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= ftueManager.currentStep.rawValue ? Color.white : Color.white.opacity(0.3))
                    .frame(width: step == ftueManager.currentStep ? 24 : 8, height: 4)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: ftueManager.currentStep)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func startPulseAnimation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pulseAnimation = true
        }
    }
    
    private func shouldPositionCardBelow(_ targetFrame: CGRect) -> Bool {
        // Position card below spotlight if spotlight is in top half of screen
        return targetFrame.midY < UIScreen.main.bounds.height / 2
    }
}

// MARK: - Swipe Gesture Demo

struct SwipeGestureDemo: View {
    enum Direction {
        case left, right
    }
    
    let direction: Direction
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            // Hand icon
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(direction == .left ? -45 : 45))
                .scaleEffect(x: direction == .left ? 1 : -1)
                .offset(x: offset)
                .opacity(opacity)
                .shadow(color: .black.opacity(0.3), radius: 10)
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        let targetOffset: CGFloat = direction == .left ? -80 : 80
        
        withAnimation(.easeInOut(duration: 0.3)) {
            opacity = 1.0
        }
        
        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: false)
        ) {
            offset = targetOffset
        }
        
        // Fade out and reset animation
        Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                offset = 0
                withAnimation(.easeIn(duration: 0.3)) {
                    opacity = 1.0
                }
            }
        }
    }
}


//
//  DailyCheckInView.swift
//  AMENAPP
//
//  Daily spiritual check-in popup
//

import SwiftUI

struct DailyCheckInView: View {
    @Binding var isPresented: Bool
    let onAnswer: (Bool) -> Void
    
    @State private var isAnimating = false
    @State private var selectedAnswer: Bool? = nil
    @State private var showButtons = false
    
    var body: some View {
        ZStack {
            // Dark background overlay
            Color.black
                .opacity(isAnimating ? 0.7 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    // Prevent dismissal by tapping background
                }
                // Hidden: Triple-tap in top-left corner to reset for testing
                .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 50, perform: {}, onPressingChanged: { pressing in
                    // This is a debug feature - remove in production
                })
            
            // Glass dialog card
            VStack(spacing: 24) {
                // Question text
                VStack(spacing: 12) {
                    Text("Have you spent time")
                        .font(.custom("OpenSans-Regular", size: 22))
                        .foregroundStyle(.white.opacity(0.95))
                    
                    Text("with God today?")
                        .font(.custom("OpenSans-Regular", size: 22))
                        .foregroundStyle(.white.opacity(0.95))
                }
                .multilineTextAlignment(.center)
                .padding(.top, 32)
                
                // Buttons
                if showButtons {
                    HStack(spacing: 20) {
                        // No Button
                        DailyCheckInButton(
                            title: "No",
                            isSelected: selectedAnswer == false,
                            isPrimary: false
                        ) {
                            handleAnswer(false)
                        }
                        
                        // Yes Button
                        DailyCheckInButton(
                            title: "Yes",
                            isSelected: selectedAnswer == true,
                            isPrimary: true
                        ) {
                            handleAnswer(true)
                        }
                    }
                    .padding(.bottom, 32)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: 340)
            .background(
                ZStack {
                    // Glass morphism background
                    RoundedRectangle(cornerRadius: 32)
                        .fill(.ultraThinMaterial)
                    
                    // Subtle gradient overlay
                    RoundedRectangle(cornerRadius: 32)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Border
                    RoundedRectangle(cornerRadius: 32)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.3), radius: 30, y: 15)
            .scaleEffect(isAnimating ? 1.0 : 0.8)
            .opacity(isAnimating ? 1.0 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                isAnimating = true
            }
            
            // Show buttons after card animation
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.2)) {
                showButtons = true
            }
        }
    }
    
    private func handleAnswer(_ answer: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedAnswer = answer
        }
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Delay for visual feedback, then callback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.3)) {
                isAnimating = false
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isPresented = false
                onAnswer(answer)
            }
        }
    }
}

// MARK: - Daily Check-In Button

struct DailyCheckInButton: View {
    let title: String
    let isSelected: Bool
    let isPrimary: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("OpenSans-SemiBold", size: 17))
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    ZStack {
                        // Button background
                        RoundedRectangle(cornerRadius: 16)
                            .fill(buttonBackgroundColor)
                        
                        // Selection highlight
                        if isSelected {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.2),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                        
                        // Border
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(borderColor, lineWidth: 1)
                    }
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
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
    
    private var buttonTextColor: Color {
        if isSelected {
            return isPrimary ? .white : .white.opacity(0.9)
        }
        return .white.opacity(0.7)
    }
    
    private var buttonBackgroundColor: Color {
        if isSelected {
            return isPrimary ? Color.white.opacity(0.25) : Color.white.opacity(0.15)
        }
        return Color.white.opacity(0.08)
    }
    
    private var borderColor: Color {
        if isSelected {
            return .white.opacity(0.4)
        }
        return .white.opacity(0.2)
    }
}

// MARK: - Preview

#Preview {
    DailyCheckInView(isPresented: .constant(true)) { answer in
        print("User answered: \(answer)")
    }
}

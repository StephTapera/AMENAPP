//
//  AuthSuccessCheckmarkView.swift
//  AMENAPP
//
//  Dynamic Island-style status capsule after successful authentication
//

import SwiftUI

struct AuthSuccessCheckmarkView: View {
    @Binding var isPresented: Bool
    
    @State private var capsuleScale: CGFloat = 0.8
    @State private var capsuleOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var checkmarkRotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0
    
    var body: some View {
        VStack {
            Spacer()
                .frame(height: 60)
            
            // Dynamic Island-style capsule
            HStack(spacing: 10) {
                // Red checkmark icon (similar to red accent in "Thinking")
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(checkmarkRotation))
                    .opacity(contentOpacity)
                
                Text("Signed In")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.white)
                    .opacity(contentOpacity)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    // Subtle pulse effect
                    Capsule()
                        .fill(Color.black.opacity(0.95))
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                    
                    // Main black capsule
                    Capsule()
                        .fill(Color.black.opacity(0.95))
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.15),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
            )
            .shadow(color: .black.opacity(0.4), radius: 15, y: 8)
            .scaleEffect(capsuleScale)
            .opacity(capsuleOpacity)
            
            Spacer()
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        // Capsule slides in with smooth spring
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            capsuleScale = 1.0
            capsuleOpacity = 1.0
        }
        
        // Content fades in
        withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
            contentOpacity = 1.0
        }
        
        // Checkmark subtle rotation
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.25)) {
            checkmarkRotation = 360
        }
        
        // Subtle pulse effect
        withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
            pulseScale = 1.15
            pulseOpacity = 0.3
        }
        
        withAnimation(.easeIn(duration: 0.4).delay(0.8)) {
            pulseOpacity = 0
        }
        
        // Auto dismiss after showing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.4)) {
                capsuleScale = 0.9
                capsuleOpacity = 0
                contentOpacity = 0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isPresented = false
            }
        }
    }
}

#Preview {
    AuthSuccessCheckmarkView(isPresented: .constant(true))
}

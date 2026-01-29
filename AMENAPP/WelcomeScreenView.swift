//
//  WelcomeScreenView.swift
//  AMENAPP
//
//  Minimal black & white welcome screen with smooth animations
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct WelcomeScreenView: View {
    @Binding var isPresented: Bool
    var user: UserModel? = nil  // Optional user for personalized greeting
    
    // Animation states
    @State private var amenOpacity: Double = 0
    @State private var amenScale: CGFloat = 0.92
    @State private var dotOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var taglineOffset: CGFloat = 10
    
    var body: some View {
        ZStack {
            // Pure black background
            Color.black
                .ignoresSafeArea()
            
            // Content - Centered
            VStack(spacing: 0) {
                Spacer()
                
                // "AMEN" with period
                HStack(spacing: 0) {
                    Text("AMEN")
                        .font(.system(size: 64, weight: .ultraLight, design: .rounded))
                        .tracking(8)
                        .foregroundColor(.white)
                    
                    Text(".")
                        .font(.system(size: 64, weight: .ultraLight, design: .rounded))
                        .foregroundColor(.white)
                        .opacity(dotOpacity)
                }
                .opacity(amenOpacity)
                .scaleEffect(amenScale)
                
                Spacer()
                    .frame(height: 24)
                
                // Tagline
                Text("Social Media, Re-ordered")
                    .font(.system(size: 15, weight: .light))
                    .tracking(2.5)
                    .foregroundColor(.white.opacity(0.75))
                    .opacity(taglineOpacity)
                    .offset(y: taglineOffset)
                
                Spacer()
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // Phase 1: "AMEN" fades in and scales to normal (0.0-0.8s)
        withAnimation(.easeOut(duration: 0.8)) {
            amenOpacity = 1.0
            amenScale = 1.0
        }
        
        // Phase 2: Period appears (0.6-0.9s) - quick pop
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.6)) {
            dotOpacity = 1.0
        }
        
        // Phase 3: Tagline fades in and slides up (0.9-1.4s)
        withAnimation(.easeOut(duration: 0.5).delay(0.9)) {
            taglineOpacity = 1.0
            taglineOffset = 0
        }
        
        // Phase 4: Hold for a moment, then exit (1.8-2.4s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.6)) {
                amenOpacity = 0
                dotOpacity = 0
                taglineOpacity = 0
                amenScale = 1.05
            }
        }
        
        // Dismiss (2.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            isPresented = false
        }
    }
}

// MARK: - Preview

#Preview("Minimal Welcome") {
    WelcomeScreenView(isPresented: .constant(true))
}


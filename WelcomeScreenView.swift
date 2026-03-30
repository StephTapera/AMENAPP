//
//  WelcomeScreenView.swift
//  AMENAPP
//
//  Optimized welcome screen with fast logo animation
//

import SwiftUI

struct WelcomeScreenView: View {
    @Binding var isPresented: Bool
    
    // Animation states
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.8
    @State private var taglineOpacity: Double = 0
    @State private var hasAnimated = false  // Prevent duplicate animations
    
    var body: some View {
        ZStack {
            // Pure white background
            Color.white
                .ignoresSafeArea()
            
            // Content
            VStack(spacing: 24) {
                Spacer()
                
                // Logo - single instance, optimized
                Image("amen-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)
                
                // Tagline
                Text("Social Media, Re-ordered")
                    .font(.system(size: 14, weight: .light))
                    .tracking(2)
                    .foregroundColor(.black.opacity(0.6))
                    .opacity(taglineOpacity)
                
                Spacer()
            }
        }
        .onAppear {
            guard !hasAnimated else { return }
            hasAnimated = true
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // Fast fade in with scale (0.0-0.4s)
        withAnimation(.easeOut(duration: 0.4)) {
            logoOpacity = 1.0
            logoScale = 1.0
        }
        
        // Tagline fades in (0.2-0.5s)
        withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
            taglineOpacity = 1.0
        }
        
        // Hold briefly then fade out (0.8-1.2s)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            withAnimation(.easeInOut(duration: 0.4)) {
                logoOpacity = 0
                taglineOpacity = 0
            }
            
            // Dismiss quickly (1.3s total)
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s more = 1.3s total
            isPresented = false
        }
    }
}

// MARK: - Preview

#Preview("Minimal Welcome") {
    WelcomeScreenView(isPresented: .constant(true))
}


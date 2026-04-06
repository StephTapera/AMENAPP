// SplashView.swift
// AMENAPP
//
// First screen shown on every cold launch (unauthenticated).
// Pure white. AMEN logo mark + wordmark. Animated entrance → held → fade out.
//
// Animation sequence (Threads-inspired):
//   0.00s  — logo fades in + gentle scale + subtle rotation settle
//   0.35s  — wordmark fades up with smooth ease
//   1.10s  — entire view fades out with refined scale
//
// No nav bar. Status bar hidden.

import SwiftUI

struct SplashView: View {
    var onComplete: () -> Void

    // Logo
    @State private var logoScale:   CGFloat = 0.88
    @State private var logoOpacity: Double  = 0
    @State private var logoRotation: Double = -3  // Subtle rotation for dynamic feel

    // Wordmark
    @State private var wordmarkOpacity: Double  = 0
    @State private var wordmarkOffset:  CGFloat = 8
    @State private var wordmarkScale: CGFloat = 0.96

    // Exit
    @State private var exitOpacity: Double  = 1
    @State private var exitScale:   CGFloat = 1

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 10) {
                Image("amen-logo")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 44, height: 48)
                    .scaleEffect(logoScale)
                    .rotationEffect(.degrees(logoRotation))
                    .opacity(logoOpacity)

                Text("AMEN")
                    .font(.systemScaled(26, weight: .black, design: .default))
                    .tracking(8)
                    .foregroundStyle(Color.black)
                    .opacity(wordmarkOpacity)
                    .scaleEffect(wordmarkScale)
                    .offset(y: wordmarkOffset)
            }
        }
        .opacity(exitOpacity)
        .scaleEffect(exitScale)
        .statusBar(hidden: true)
        .onAppear { runAnimation() }
    }

    private func runAnimation() {
        // Step 1 — logo entrance (smooth spring with subtle rotation settle)
        withAnimation(Motion.adaptive(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0.3))) {
            logoScale   = 1.0
            logoRotation = 0
            logoOpacity = 1
        }

        // Step 2 — wordmark fade up (delayed, smooth)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.78))) {
                wordmarkOpacity = 1
                wordmarkScale = 1.0
                wordmarkOffset  = 0
            }
        }

        // Step 3 — exit (Threads-style: quick fade with subtle scale)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeInOut(duration: 0.3)) {
                exitOpacity = 0
                exitScale   = 1.05
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onComplete()
            }
        }
    }
}

// SplashView.swift
// AMENAPP
//
// First screen shown on every cold launch (unauthenticated).
// Pure white. AMEN logo mark + wordmark. Animated entrance → held → fade out.
//
// Animation sequence:
//   0.15s  — logo + wordmark scale 0.82→1.0, opacity 0→1 (spring)
//   0.85s  — wordmark shifts up and settles (already part of spring carry)
//   2.00s  — entire view fades out + scales to 1.04 → calls onComplete()
//
// No nav bar. Status bar hidden.

import SwiftUI

struct SplashView: View {
    var onComplete: () -> Void

    // Logo
    @State private var logoScale:   CGFloat = 0.82
    @State private var logoOpacity: Double  = 0

    // Wordmark
    @State private var wordmarkOpacity: Double  = 0
    @State private var wordmarkOffset:  CGFloat = 6

    // Exit
    @State private var exitOpacity: Double  = 1
    @State private var exitScale:   CGFloat = 1

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 14) {
                Image("amen-logo")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.black)
                    .scaledToFit()
                    .frame(width: 90, height: 96)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                Text("AMEN")
                    .font(.system(size: 26, weight: .black, design: .default))
                    .tracking(8)
                    .foregroundStyle(Color.black)
                    .opacity(wordmarkOpacity)
                    .offset(y: wordmarkOffset)
            }
        }
        .opacity(exitOpacity)
        .scaleEffect(exitScale)
        .statusBar(hidden: true)
        .onAppear { runAnimation() }
    }

    private func runAnimation() {
        // Step 1 — logo entrance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                logoScale   = 1.0
                logoOpacity = 1
            }
        }

        // Step 3 — wordmark fade up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.3)) {
                wordmarkOpacity = 1
                wordmarkOffset  = 0
            }
        }

        // Step 4 — exit (Threads-paced: hold just long enough to read, then cut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeIn(duration: 0.25)) {
                exitOpacity = 0
                exitScale   = 1.04
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                onComplete()
            }
        }
    }
}

// SelahPauseOverlay.swift
// AMENAPP
// Full-screen mindful pause shown by AmenWellbeingService after extended/rapid scrolling.

import SwiftUI

struct SelahPauseOverlay: View {
    @ObservedObject var wellbeing: AmenWellbeingService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var opacity: Double = 0

    var body: some View {
        if wellbeing.shouldShowSelahPause {
            ZStack {
                // Frosted backdrop
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // Selah wordmark
                    VStack(spacing: 12) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.white)
                            .symbolRenderingMode(.hierarchical)

                        Text("Selah")
                            .font(.system(size: 38, weight: .light, design: .serif))
                            .foregroundStyle(.white)

                        Text("Pause. Breathe. Be still.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    // Scripture
                    VStack(spacing: 6) {
                        Text("\u{201C}Be still and know that I am God.\u{201D}")
                            .font(.body.italic())
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Text("Psalm 46:10")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()

                    // Actions
                    VStack(spacing: 16) {
                        NavigationLink(destination: SelahView(
                            message: BereanMessage(content: "", role: .assistant, timestamp: Date()),
                            originalQuery: ""
                        )) {
                            Text("Open Selah")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(.white.opacity(0.2))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
                        }

                        Button {
                            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.25)) {
                                wellbeing.dismissSelahPause()
                            }
                        } label: {
                            Text("Continue Browsing")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                }
            }
            .opacity(opacity)
            .onAppear {
                withAnimation(reduceMotion ? .none : .easeIn(duration: 0.4)) {
                    opacity = 1
                }
            }
            .transition(.opacity)
            .zIndex(100)
        }
    }
}

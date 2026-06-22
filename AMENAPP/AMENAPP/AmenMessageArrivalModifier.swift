// AmenMessageArrivalModifier.swift
// AMENAPP
//
// Spring-driven slide-up + scale arrival animation for incoming/outgoing message rows.
// Only fires for messages created within the last 10 seconds, so LazyVStack
// scroll-into-view for history items never triggers the animation.

import SwiftUI

// Package-internal: exposed for unit tests
func isRecentAmenMessage(timestamp: Date, window: TimeInterval = 10) -> Bool {
    Date().timeIntervalSince(timestamp) < window
}

struct AmenMessageArrivalModifier: ViewModifier {
    let messageTimestamp: Date
    let isEnabled: Bool

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldAnimate: Bool {
        isEnabled && isRecentAmenMessage(timestamp: messageTimestamp)
    }

    func body(content: Content) -> some View {
        if shouldAnimate {
            content
                .offset(y: appeared ? 0 : 12)
                .scaleEffect(appeared ? 1.0 : 0.96, anchor: .bottom)
                .opacity(appeared ? 1.0 : 0.0)
                .onAppear {
                    let animation: Animation = reduceMotion
                        ? .easeOut(duration: 0.18)
                        : .spring(response: 0.38, dampingFraction: 0.72)
                    withAnimation(animation) {
                        appeared = true
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    func amenMessageArrival(timestamp: Date, isEnabled: Bool = true) -> some View {
        modifier(AmenMessageArrivalModifier(messageTimestamp: timestamp, isEnabled: isEnabled))
    }
}

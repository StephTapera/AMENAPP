// AmenChatTypingIndicator.swift
// AMENAPP
//
// Liquid Glass typing pill for the chat view.
// Replaces the inline LiquidGlassTypingIndicator when
// AMENFeatureFlags.messagingTypingIndicatorEnabled is true.
//
// Supports: "Alex is typing…" / "Alex and Sam are typing…" / "4 people are typing…"
// Reduce Motion: shows static label text instead of animated dots.

import SwiftUI

// Package-internal: exposed for unit tests
func amenTypingLabel(for names: [String]) -> String {
    switch names.count {
    case 0:  return "Typing\u{2026}"
    case 1:  return "\(names[0]) is typing\u{2026}"
    case 2:  return "\(names[0]) and \(names[1]) are typing\u{2026}"
    default: return "\(names.count) people are typing\u{2026}"
    }
}

struct AmenChatTypingIndicator: View {
    let names: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeDot: Int = 0
    private let dotTimer = Timer.publish(every: 0.33, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            pillContent
                .background(glassBackground)

            Spacer(minLength: 52)
        }
        .accessibilityLabel(amenTypingLabel(for: names))
        .onReceive(dotTimer) { _ in
            guard !reduceMotion else { return }
            activeDot = (activeDot + 1) % 3
        }
    }

    @ViewBuilder
    private var pillContent: some View {
        if reduceMotion {
            Text(amenTypingLabel(for: names))
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        } else {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color(.systemGray2))
                        .frame(width: 7, height: 7)
                        .scaleEffect(activeDot == i ? 1.3 : 1.0)
                        .offset(y: activeDot == i ? -3 : 0)
                        .animation(
                            .spring(response: 0.28, dampingFraction: 0.50),
                            value: activeDot
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }

    private var glassBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
    }
}

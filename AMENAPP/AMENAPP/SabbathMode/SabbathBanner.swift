// SabbathBanner.swift
// AMENAPP — SabbathMode
//
// Thin persistent banner shown when SabbathState == .steppedOut.
// Persists at the top of every screen until midnight.
// Text only — never a count, number, or comparative metric.
// BANNED tokens: gold, purple, dark gradients, serif fonts.

import SwiftUI

struct SabbathBanner: View {
    let steppedOutAt: Date

    var body: some View {
        Text("You stepped out of Sabbath · Returns next week")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.06))
            .accessibilityLabel("You stepped out of Sabbath. Sabbath will resume next week.")
    }
}

#Preview {
    VStack {
        SabbathBanner(steppedOutAt: Date())
        Spacer()
    }
}

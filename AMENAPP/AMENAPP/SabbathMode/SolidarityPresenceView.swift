// SolidarityPresenceView.swift
// AMENAPP — SabbathMode
//
// Text-only solidarity indicator. NEVER renders a count, number, or percentage.
// showCount is permanently false (SabbathConfig.ts solidarity.showCount: false).
// If text is nil/empty, renders nothing.

import SwiftUI

struct SolidarityPresenceView: View {
    /// Optional custom text. If nil or empty, view renders nothing.
    var text: String = "Others in your family are resting too"

    var body: some View {
        // INVARIANT: solidarity.showCount is always false — never render a number.
        // Render nothing if solidarity is disabled or text is empty.
        guard SabbathModeDefaults.Solidarity.enabled, !text.isEmpty else {
            return AnyView(EmptyView())
        }
        return AnyView(
            Text(text)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .accessibilityLabel(text)
        )
    }
}

#Preview {
    SolidarityPresenceView()
}

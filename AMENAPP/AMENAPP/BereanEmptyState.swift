// BereanEmptyState.swift
// AMEN App — Berean AI empty state.
// Shown when there are no sessions and no pulse content.
//
// Signature (frozen):
//   BereanEmptyState(onOpenPulse: () -> Void)
//
// Design: BereanPulseCard centered on screen with a tertiary-color caption below.
// Generous top padding keeps the card visually centered in the available space.

import SwiftUI

// MARK: - BereanEmptyState

struct BereanAssistantEmptyState: View {

    let onOpenPulse: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {

                // Top spacer — roughly one-third of available height
                Spacer()
                    .frame(height: max(0, (proxy.size.height - contentHeight) * 0.36))

                // Main card
                BereanAssistantPulseCard(pulse: .today, onOpen: onOpenPulse)
                    .padding(.horizontal, DesignTokens.spacingL)

                // Caption
                Text("Ask anything about your faith journey")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(.tertiaryLabel))
                    .multilineTextAlignment(.center)
                    .padding(.top, DesignTokens.spacingM)
                    .padding(.horizontal, DesignTokens.spacingXL)
                    .accessibilityHint("Tap the card above to open your daily Berean Pulse")

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
    }

    // Approximate rendered height: icon tile 54 + vertical padding 32 + caption 36 + gap 16
    private var contentHeight: CGFloat { 138 }
}

// MARK: - Preview

#Preview("Empty State — Light") {
    ZStack {
        Color(red: 0.971, green: 0.971, blue: 0.969)
            .ignoresSafeArea()
        BereanAssistantEmptyState(onOpenPulse: {})
    }
}

#Preview("Empty State — Dark") {
    ZStack {
        Color(.systemBackground)
            .ignoresSafeArea()
        BereanAssistantEmptyState(onOpenPulse: {})
    }
    .preferredColorScheme(.dark)
}

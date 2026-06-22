// BereanReaderCard.swift
// AMEN — Berean Reading Surface: BereanReaderCard component (W1)
// Flag: bereanGlassComponents (dev-only)
//
// Wraps canonical LiquidGlassCard (LiquidGlass/LiquidGlassCard.swift) with
// bereanIvory tint. The canonical card already handles livingGlassMaterial
// and ReduceTransparency via LiquidGlassMaterial.swift.
// This wrapper adds optional header text and tap routing.

import SwiftUI

/// Berean reading surface card with optional header and tap action.
/// ReduceTransparency fallback: solid bereanIvory + bereanTan stroke.
struct BereanReaderCard<Content: View>: View {

    let header: String?
    let onTap: (() -> Void)?
    let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    init(
        header: String? = nil,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.header = header
        self.onTap = onTap
        self.content = content
    }

    var body: some View {
        Group {
            if reduceTransparency {
                solidCard
            } else {
                glassCard
            }
        }
        .accessibilityElement(children: .contain)
        .onTapGesture { onTap?() }
    }

    private var solidCard: some View {
        innerContent
            .background(colorScheme == .dark ? Color(.systemGray6) : Color.bereanIvory)
            .clipShape(RoundedRectangle(cornerRadius: BereanMetrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BereanMetrics.cardRadius, style: .continuous)
                    .strokeBorder(Color.bereanTan, lineWidth: BereanMetrics.strokeWidth)
            )
            .shadow(
                color: Color.bereanInk.opacity(BereanMetrics.shadowOpacity),
                radius: BereanMetrics.shadowRadius, y: 3
            )
    }

    private var glassCard: some View {
        LiquidGlassCard(contextTint: .bereanIvory) {
            innerContent
        }
    }

    private var innerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header)
                    .font(BereanType.subheadline())
                    .foregroundStyle(Color.bereanInk.opacity(0.65))
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Default") {
    BereanReaderCard(header: "Today's Reflection") {
        Text("In the beginning was the Word…")
            .font(BereanReaderType.body)
            .foregroundStyle(Color.bereanInk)
    }
    .padding()
    .background(Color.bereanIvory)
}

#Preview("No header") {
    BereanReaderCard {
        Text("A card without a header.")
            .font(BereanReaderType.body)
            .foregroundStyle(Color.bereanInk)
            .padding()
    }
    .padding()
}

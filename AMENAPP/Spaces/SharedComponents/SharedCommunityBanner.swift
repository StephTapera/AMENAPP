// SharedCommunityBanner.swift
// AMENAPP — Spaces v2 Shared Components (Agent C)
//
// Glass pill banner showing cross-community sharing signal.
// Driven by single denormalized fields — no Firestore reads inside.
// Import this — never re-implement. See CONTRACT_C.md for full API.

import SwiftUI

/// Glass pill banner showing cross-community sharing signal.
/// Driven by single denormalized fields — no Firestore reads inside.
/// Import this — never re-implement.
struct SharedCommunityBanner: View {

    /// Mode drives the copy and semantic meaning of the banner.
    enum Mode {
        /// "Shared with [Community]."
        case sharedWith(communityName: String)
        /// "N members are from [Community]."
        case membersFrom(count: Int, communityName: String)

        var labelText: String {
            switch self {
            case .sharedWith(let name):
                return "Shared with \(name)."
            case .membersFrom(let count, let name):
                return "\(count) \(count == 1 ? "member is" : "members are") from \(name)."
            }
        }
    }

    let mode: Mode

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 6) {
            LinkedGlyph(size: .small)

            Text(mode.labelText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if reduceTransparency {
                Capsule(style: .continuous)
                    .fill(AmenTheme.Colors.surfaceChip)
            } else {
                Capsule(style: .continuous)
                    .fill(LiquidGlassTokens.blurThin)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    }
            }
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mode.labelText)
    }
}

#if DEBUG
#Preview("SharedCommunityBanner Modes") {
    VStack(spacing: 12) {
        SharedCommunityBanner(mode: .sharedWith(communityName: "Hillside Community"))
        SharedCommunityBanner(mode: .membersFrom(count: 7, communityName: "Grace Fellowship"))
        SharedCommunityBanner(mode: .membersFrom(count: 1, communityName: "Cornerstone"))
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}
#endif

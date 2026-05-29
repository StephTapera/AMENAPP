// GroupGradientArtView.swift
// AMENAPP — Discussions
//
// Deterministic gradient + monogram fallback art for groups that have no logo.
// Seeded by groupId using DJB2 (not Swift's hashValue, which is process-scoped).
// Maps to 4 gradient pairs built on AMEN brand tokens.

import SwiftUI

// MARK: - DJB2 hash (stable across runs / processes)

private func djb2Hash(_ string: String) -> UInt64 {
    var hash: UInt64 = 5381
    for byte in string.utf8 {
        hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
    }
    return hash
}

// MARK: - Gradient pairs (AMEN tokens only)

private struct GradientPair {
    let start: Color
    let end: Color
    let tint: Color
}

private let gradientPairs: [GradientPair] = [
    // amenGold → amenBronze
    GradientPair(
        start: Color(red: 0.83, green: 0.69, blue: 0.22),
        end:   Color(red: 0.80, green: 0.50, blue: 0.20),
        tint:  Color(red: 0.60, green: 0.44, blue: 0.00)
    ),
    // amenPurple → amenBlue
    GradientPair(
        start: Color(red: 0.44, green: 0.26, blue: 0.80),
        end:   Color(red: 0.04, green: 0.52, blue: 1.00),
        tint:  Color(red: 0.44, green: 0.26, blue: 0.80)
    ),
    // amenBlue → amenBlack
    GradientPair(
        start: Color(red: 0.04, green: 0.52, blue: 1.00),
        end:   Color(red: 0.06, green: 0.06, blue: 0.07),
        tint:  Color(red: 0.04, green: 0.52, blue: 1.00)
    ),
    // amenBlack → amenPurple
    GradientPair(
        start: Color(red: 0.06, green: 0.06, blue: 0.07),
        end:   Color(red: 0.44, green: 0.26, blue: 0.80),
        tint:  Color(red: 0.44, green: 0.26, blue: 0.80)
    ),
]

// MARK: - Public API

/// Returns the stable accent tint for a groupId (used to bleed into hero background).
func groupAccentTint(for groupId: String) -> Color {
    gradientPairs[Int(djb2Hash(groupId) % UInt64(gradientPairs.count))].tint
}

// MARK: - View

/// Full-bleed gradient art with a centered monogram.
/// Drop-in replacement for a remote image when `coverImageURL` is nil.
struct GroupGradientArtView: View {
    let groupId: String
    let groupName: String
    var size: CGFloat = 80

    private var pair: GradientPair {
        gradientPairs[Int(djb2Hash(groupId) % UInt64(gradientPairs.count))]
    }

    private var monogram: String {
        String(groupName.first ?? "G").uppercased()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [pair.start, pair.end],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(monogram)
                .font(.system(size: size * 0.40, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.90))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .shadow(color: pair.end.opacity(0.30), radius: 8, x: 0, y: 4)
    }
}

/// Hero-sized (full-width) version — fills a container and bleeds to the edges.
struct GroupGradientHeroView: View {
    let groupId: String
    let groupName: String

    private var pair: GradientPair {
        gradientPairs[Int(djb2Hash(groupId) % UInt64(gradientPairs.count))]
    }

    private var monogram: String {
        String(groupName.first ?? "G").uppercased()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [pair.start, pair.end],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)

            Text(monogram)
                .font(.system(size: 80, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.18))
        }
    }
}

// MARK: - Preview

#Preview("Gradient Art") {
    HStack(spacing: 12) {
        ForEach(["groupA", "groupB", "groupC", "groupD"], id: \.self) { id in
            GroupGradientArtView(groupId: id, groupName: id, size: 64)
        }
    }
    .padding()
}

//
//  AmbientPreviewGallery.swift
//  AMEN — Adaptive Ambient UI System (Phase 3 — verification gate)
//
//  Five fixtures, each exercising a different code path of the Adaptive Ambient system.
//  Fixtures are generated programmatically (gradients) so the gallery has NO network or
//  bundle-asset dependency. This is the SwiftUI-native replacement for the React prototype
//  gate: verification happens against these previews, not a JSX sim.
//
//  To exercise the full 8-way trait matrix per fixture, toggle in the canvas:
//  light/dark × { default, Reduce Transparency, Increase Contrast, Reduce Motion }.
//

import SwiftUI

// MARK: - Programmatic fixture images (no assets, no network)

enum AmbientFixture {
    /// A diagonal two-stop gradient rendered to a UIImage for palette extraction.
    static func gradient(_ a: UIColor, _ b: UIColor, size: CGFloat = 400) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [a.cgColor, b.cgColor] as CFArray
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: [0, 1]) else {
                a.setFill(); cg.fill(rect); return
            }
            cg.drawLinearGradient(grad, start: .zero,
                                  end: CGPoint(x: size, y: size), options: [])
        }
    }

    static let darkPortrait = gradient(UIColor(white: 0.10, alpha: 1),
                                       UIColor(red: 0.18, green: 0.10, blue: 0.28, alpha: 1))   // low-key
    static let warmWorship  = gradient(UIColor(red: 0.86, green: 0.55, blue: 0.18, alpha: 1),
                                       UIColor(red: 0.55, green: 0.20, blue: 0.08, alpha: 1))   // golden
    static let brightAiry   = gradient(UIColor(red: 0.93, green: 0.95, blue: 0.99, alpha: 1),
                                       UIColor(red: 0.78, green: 0.86, blue: 0.96, alpha: 1))   // light
    static let saturatedRoom = gradient(UIColor(red: 0.10, green: 0.45, blue: 0.85, alpha: 1),
                                        UIColor(red: 0.55, green: 0.10, blue: 0.65, alpha: 1))  // vivid banner
}

// MARK: - Shared demo scaffold

/// Drives a scope from a single fixture image and renders representative chrome + a reading plane.
private struct AmbientGalleryScreen: View {
    let title: String
    let fixture: UIImage?
    let sourceID: String

    var body: some View {
        AmbientScope { coordinator in
            AmbientGalleryBody(title: title, fixture: fixture,
                               sourceID: sourceID, coordinator: coordinator)
        }
    }
}

private struct AmbientGalleryBody: View {
    let title: String
    let fixture: UIImage?
    let sourceID: String
    @ObservedObject var coordinator: AmbientCoordinator
    @Environment(\.ambientPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AdaptiveAmbientBackground(bleedImage: fixture, bleedHeight: 280)
            ScrollView {
                VStack(spacing: 18) {
                    AdaptiveProfileHeader(
                        heroImage: fixture,
                        displayName: title,
                        username: "amen.fixture",
                        bio: "Ambient absorbs the content's color so the chrome recedes.",
                        statusPill: AdaptiveStatusPill(text: "Online", systemImage: "circle.fill")
                    )

                    HStack(spacing: 12) {
                        AdaptiveStatusPill(text: "At church", systemImage: "building.columns")
                        AdaptiveGlassContainer(tintAlpha: 0.2) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                        }
                    }

                    // Reading plane (C6): post/comment text never gets a chroma background.
                    AdaptiveContentCard(isReadingPlane: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reading plane").font(.headline)
                                .foregroundStyle(.primary)
                            Text("Long-form text stays neutral. Max tint here is 0.04 × intensity, "
                                 + "so scripture and comments remain fully legible regardless of media.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            coordinator.drive(with: fixture,
                              key: .init(id: sourceID, revision: "1"),
                              scheme: scheme, reduceMotion: reduceMotion)
        }
    }
}

// MARK: - The five fixtures

#Preview("1 · Dark profile") {
    AmbientGalleryScreen(title: "Dark profile",
                         fixture: AmbientFixture.darkPortrait, sourceID: "fixture/dark")
}

#Preview("2 · Warm media viewer") {
    AmbientGalleryScreen(title: "Warm worship",
                         fixture: AmbientFixture.warmWorship, sourceID: "fixture/warm")
}

#Preview("3 · Light post") {
    AmbientGalleryScreen(title: "Bright & airy",
                         fixture: AmbientFixture.brightAiry, sourceID: "fixture/light")
}

#Preview("4 · Colorful room") {
    AmbientGalleryScreen(title: "Saturated room",
                         fixture: AmbientFixture.saturatedRoom, sourceID: "fixture/room")
}

#Preview("5 · Neutral fallback (C5)") {
    // nil media ⇒ fail-closed to canonical neutral Liquid Glass.
    AmbientGalleryScreen(title: "Neutral fallback",
                         fixture: nil, sourceID: "fixture/neutral")
}

//
//  AdaptiveProfileHeader.swift
//  AMEN — Adaptive Ambient UI System (Phase 2B)
//
//  Hero bleeds into top background; collapses into tinted glass nav on scroll.
//  Name/bio/stats sit on guaranteed-contrast text colors. Bottom-anchored scrim only —
//  never a full-face overlay (Rules §4, face avoidance).
//

import SwiftUI

public struct AdaptiveProfileHeader: View {
    @Environment(\.ambientPalette) private var palette
    @Environment(\.ambientIntensity) private var intensity

    let heroImage: UIImage?
    let displayName: String
    let username: String
    let bio: String
    var statusPill: AdaptiveStatusPill?

    public init(heroImage: UIImage?, displayName: String, username: String,
                bio: String, statusPill: AdaptiveStatusPill? = nil) {
        self.heroImage = heroImage; self.displayName = displayName
        self.username = username; self.bio = bio; self.statusPill = statusPill
    }

    public var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                if let heroImage {
                    Image(uiImage: heroImage)
                        .resizable().scaledToFill()
                        .frame(height: 260).frame(maxWidth: .infinity).clipped()
                        // Bottom-anchored scrim only — never a full-face overlay.
                        .overlay(
                            LinearGradient(
                                colors: [.clear, palette.background.opacity(0.85 * max(intensity, 0.4))],
                                startPoint: .center, endPoint: .bottom)
                        )
                } else {
                    palette.background.frame(height: 140)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName).font(.title.bold()).foregroundStyle(palette.textPrimary)
                    Text("@\(username)").font(.subheadline).foregroundStyle(palette.textSecondary)
                }
                .padding(20)
            }

            HStack(spacing: 12) {
                if let statusPill { statusPill }
                Spacer()
                AdaptiveGlassContainer(tintAlpha: 0.22) {
                    Text("Follow").font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 20).padding(.vertical, 9)
                }
            }
            .padding(.horizontal, 20)

            Text(bio)
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
        }
        .background(AdaptiveAmbientBackground(bleedImage: heroImage, bleedHeight: 320))
    }
}

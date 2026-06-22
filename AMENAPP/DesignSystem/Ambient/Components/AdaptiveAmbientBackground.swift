//
//  AdaptiveAmbientBackground.swift
//  AMEN — Adaptive Ambient UI System (Phase 2B)
//
//  Full-screen ambient wash behind media/immersive surfaces (the "recipe" effect).
//  Blurred media bleed at top → palette.background gradient. One blur layer max (perf §6).
//  Reduce Transparency / intensity == 0 ⇒ no bleed, flat background (C3).
//

import SwiftUI

public struct AdaptiveAmbientBackground: View {
    @Environment(\.ambientPalette) private var palette
    @Environment(\.ambientIntensity) private var intensity
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var bleedImage: UIImage?           // optional hero/media to bleed
    var bleedHeight: CGFloat

    public init(bleedImage: UIImage? = nil, bleedHeight: CGFloat = 420) {
        self.bleedImage = bleedImage; self.bleedHeight = bleedHeight
    }

    public var body: some View {
        ZStack(alignment: .top) {
            palette.background.ignoresSafeArea()
            if let bleedImage, !reduceTransparency, intensity > 0 {
                Image(uiImage: bleedImage)
                    .resizable().scaledToFill()
                    .frame(height: bleedHeight).frame(maxWidth: .infinity)
                    .clipped()
                    .blur(radius: 60, opaque: true)
                    .opacity(0.55 * intensity)
                    .overlay(
                        LinearGradient(colors: [.clear, palette.background],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
        }
    }
}

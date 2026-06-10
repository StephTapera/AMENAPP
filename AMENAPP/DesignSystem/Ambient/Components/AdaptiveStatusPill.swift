//
//  AdaptiveStatusPill.swift
//  AMEN — Adaptive Ambient UI System (Phase 2B)
//
//  Small glass status chip (e.g. "Online", "At church"). Text on guaranteed-contrast color.
//

import SwiftUI

public struct AdaptiveStatusPill: View {
    @Environment(\.ambientPalette) private var palette
    let text: String
    let systemImage: String

    public init(text: String, systemImage: String = "circle.fill") {
        self.text = text; self.systemImage = systemImage
    }

    public var body: some View {
        AdaptiveGlassContainer(tintAlpha: 0.25) {
            Label(text, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .labelStyle(.titleAndIcon)
                .imageScale(.small)
                .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }
}

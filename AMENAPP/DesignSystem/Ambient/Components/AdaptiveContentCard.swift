//
//  AdaptiveContentCard.swift
//  AMEN — Adaptive Ambient UI System (Phase 2B)
//
//  White-card-on-neutral by default; absorbs at most a whisper of ambient tint.
//  C6 guard: reading planes (scripture, post body, comments) are hard-capped at 0.04 × intensity.
//

import SwiftUI

public struct AdaptiveContentCard<Content: View>: View {
    @Environment(\.ambientPalette) private var palette
    @Environment(\.ambientIntensity) private var intensity
    @Environment(\.colorScheme) private var scheme

    var isReadingPlane: Bool           // true ⇒ tint hard-capped (C6)
    @ViewBuilder var content: () -> Content

    public init(isReadingPlane: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.isReadingPlane = isReadingPlane; self.content = content
    }

    public var body: some View {
        let cap = isReadingPlane ? 0.04 : 0.10
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(scheme == .dark ? Color(uiColor: .secondarySystemBackground) : .white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(palette.dominant.opacity(cap * intensity))
                    )
            )
            .shadow(color: palette.shadow.opacity(0.5), radius: 10, y: 3)
    }
}

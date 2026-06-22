// AmenSmartPillRow.swift
// AMENAPP
//
// Horizontally scrolling row of up to 3 smart pills above the composer (Phase 4A).

import SwiftUI

struct AmenSmartPillRow: View {
    let pills: [AmenSmartPillDescriptor]
    let onTap: (AmenSmartPillType) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if pills.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pills) { pill in
                        AmenSmartPill(
                            title: pill.type.label,
                            systemImage: pill.type.systemImage,
                            variant: .regular,
                            accessibilityHint: pill.type.accessibilityHint
                        ) {
                            onTap(pill.type)
                        }
                        .disabled(pill.state == .disabled || pill.state == .loading)
                        .transition(
                            .scale(scale: 0.7, anchor: .bottom)
                            .combined(with: .opacity)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.16)
                    : .spring(response: 0.32, dampingFraction: 0.72),
                value: pills.map(\.id)
            )
        }
    }
}

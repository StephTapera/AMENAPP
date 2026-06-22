// LiquidGlassToolbar.swift
// AMEN — Berean Reading Surface: BereanActionToolbar component (W1)
//
// All actions inside one GlassEffectContainer for batched blur.
// Overflow items beyond maxVisible collapse into a "More" Menu.
// ReduceTransparency: solid bereanIvory bar.

import SwiftUI

/// Ordered action set for the Berean reading surface.
/// Cluster all related toolbar actions here so glass blur batches correctly.
struct BereanActionToolbar: View {

    let items: [BereanToolbarItem]
    private let maxVisible: Int = 5

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let visible = Array(items.prefix(maxVisible))
        let overflow = Array(items.dropFirst(maxVisible))

        Group {
            if reduceTransparency {
                toolbarContent(visible: visible, overflow: overflow)
                    .background(Color.bereanIvory)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.bereanTan, lineWidth: BereanMetrics.strokeWidth)
                    )
            } else {
                GlassEffectContainer(spacing: 0) {
                    toolbarContent(visible: visible, overflow: overflow)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .animation(
            .berean(BereanSpring.toolbarRise, reduceMotion: reduceMotion),
            value: items.count
        )
    }

    @ViewBuilder
    private func toolbarContent(visible: [BereanToolbarItem], overflow: [BereanToolbarItem]) -> some View {
        HStack(spacing: 0) {
            ForEach(visible) { item in
                Button(action: item.action) {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 17, weight: .regular))
                        Text(item.label)
                            .font(BereanType.caption())
                    }
                    .foregroundStyle(Color.bereanInk)
                    .frame(minWidth: BereanMetrics.minTapTarget, minHeight: BereanMetrics.minTapTarget)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(item.label)

                if item.id != visible.last?.id || !overflow.isEmpty {
                    Rectangle()
                        .fill(Color.bereanTan.opacity(0.4))
                        .frame(width: BereanMetrics.strokeWidth, height: 28)
                }
            }

            if !overflow.isEmpty {
                Menu {
                    ForEach(overflow) { item in
                        Button(action: item.action) {
                            Label(item.label, systemImage: item.icon)
                        }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17))
                        Text("More")
                            .font(BereanType.caption())
                    }
                    .foregroundStyle(Color.bereanInk)
                    .frame(minWidth: BereanMetrics.minTapTarget, minHeight: BereanMetrics.minTapTarget)
                }
                .accessibilityLabel("More actions")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack(spacing: 16) {
        BereanActionToolbar(items: [
            BereanToolbarItem(id: "save", icon: "bookmark", label: "Save", action: {}),
            BereanToolbarItem(id: "share", icon: "square.and.arrow.up", label: "Share", action: {}),
            BereanToolbarItem(id: "pray", icon: "hands.and.sparkles.fill", label: "Pray", action: {}),
            BereanToolbarItem(id: "explain", icon: "text.magnifyingglass", label: "Explain", action: {}),
        ])

        BereanActionToolbar(items: [
            BereanToolbarItem(id: "toggle", icon: "mic.fill", label: "Start", action: {}),
            BereanToolbarItem(id: "save", icon: "note.text.badge.plus", label: "Save", action: {}),
            BereanToolbarItem(id: "convert", icon: "arrow.triangle.2.circlepath", label: "Convert", action: {}),
            BereanToolbarItem(id: "end", icon: "stop.circle", label: "End", action: {}),
        ])
    }
    .padding()
    .background(Color.bereanIvory)
}

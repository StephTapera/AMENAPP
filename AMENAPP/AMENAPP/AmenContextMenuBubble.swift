// AmenContextMenuBubble.swift
// AMENAPP
//
// Full-screen overlay for the Liquid Glass context menu.
// Dims the background and floats a glass-style action panel
// positioned above or below the tapped message bubble.
// Driven by AmenMessageContextMenuPresenter.shared.

import SwiftUI

struct AmenContextMenuBubble: View {
    @ObservedObject var presenter: AmenMessageContextMenuPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let menuWidth: CGFloat = 252

    var body: some View {
        if presenter.isPresented {
            GeometryReader { proxy in
                ZStack {
                    // Dimmed backdrop — tap dismisses
                    Color.black.opacity(0.38)
                        .ignoresSafeArea()
                        .onTapGesture { presenter.dismiss() }

                    // Floating action panel
                    menuPanel
                        .position(menuPosition(anchor: presenter.anchorFrame, screen: proxy.size))
                        .amenContextMenuBloom(isPresented: presenter.isPresented)
                }
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    private var menuPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(presenter.actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(reduceTransparency ? 0.20 : 0.12))
                        .frame(height: 0.5)
                        .padding(.horizontal, 16)
                }
                actionRow(action)
            }
        }
        .frame(width: menuWidth)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    }

    @ViewBuilder
    private func actionRow(_ action: AmenContextMenuAction) -> some View {
        Button {
            guard action.isEnabled else { return }
            presenter.dismiss()
            // Let dismiss animation play before firing the handler
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                action.handler?()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 22, alignment: .center)
                Text(action.label)
                    .font(.system(size: 16))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
            .foregroundStyle(rowColor(action))
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
    }

    private func rowColor(_ action: AmenContextMenuAction) -> Color {
        if !action.isEnabled { return Color(.secondaryLabel) }
        if action.isDestructive { return .red }
        return Color(.label)
    }

    @ViewBuilder
    private var glassBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.97))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Color.white.opacity(0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )
        }
    }

    private func menuPosition(anchor: CGRect, screen: CGSize) -> CGPoint {
        let rowHeight: CGFloat = 50
        let estimatedMenuHeight = CGFloat(presenter.actions.count) * rowHeight
        let margin: CGFloat = 12

        // Horizontal: center over anchor, clamped within screen edges
        let x = min(max(anchor.midX, menuWidth / 2 + 16), screen.width - menuWidth / 2 - 16)

        // Vertical: below anchor when in top 60% of screen, above otherwise
        let rawY: CGFloat
        if anchor.maxY < screen.height * 0.60 {
            rawY = anchor.maxY + margin + estimatedMenuHeight / 2
        } else {
            rawY = anchor.minY - margin - estimatedMenuHeight / 2
        }
        let y = min(max(rawY, estimatedMenuHeight / 2 + 8), screen.height - estimatedMenuHeight / 2 - 8)

        return CGPoint(x: x, y: y)
    }
}

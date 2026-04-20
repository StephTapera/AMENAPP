// CrisisExpandableSection.swift
// AMENAPP
//
// Reusable expandable card component for Crisis Support sections.
// Premium collapse/expand with animated chevron, height+opacity reveal,
// and consistent liquid-glass-adjacent card styling.
//

import SwiftUI

// MARK: - Expandable Section Card

struct CrisisExpandableSection<Content: View>: View {
    let section: CrisisSection
    let isOpen: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Header tap target
            Button(action: {
                if reduceMotion {
                    onToggle()
                } else {
                    withAnimation(CrisisAnimationTokens.sectionExpand) {
                        onToggle()
                    }
                }
            }) {
                HStack(spacing: 14) {
                    // Icon well
                    let accent = section.accentColorHex
                    ZStack {
                        Circle()
                            .fill(Color(
                                red: accent.bg.0,
                                green: accent.bg.1,
                                blue: accent.bg.2
                            ))
                        Image(systemName: section.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(
                                red: accent.icon.0,
                                green: accent.icon.1,
                                blue: accent.icon.2
                            ))
                    }
                    .frame(width: 46, height: 46)

                    // Title + subtitle
                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(section.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Animated chevron
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .animation(
                            reduceMotion ? nil : CrisisAnimationTokens.sectionExpand,
                            value: isOpen
                        )
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(section.title), \(isOpen ? "collapse" : "expand")")
            .accessibilityAddTraits(.isButton)

            // Expandable content
            if isOpen {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, 18)

                    content()
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 18)
                }
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top).animation(.spring(response: 0.30, dampingFraction: 0.84))),
                            removal: .opacity
                        )
                )
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.06), radius: 18, y: 6)
    }
}

// MARK: - Resource Row

/// A single tappable resource row inside an expanded section.
struct CrisisResourceRow: View {
    let resource: CrisisResource
    let onAction: () -> Void

    var body: some View {
        Button(action: onAction) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(resource.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(resource.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(resource.channel == .call ? "Call" : resource.channel == .text ? "Text" : "Open")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.7))
                            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                    )
            }
            .padding(14)
            .background(tintBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(resource.title) — \(resource.channel.rawValue)")
    }

    private var tintBackground: some View {
        let colors: (Double, Double, Double) = {
            switch resource.tint {
            case .red:    return (1.00, 0.94, 0.94)
            case .purple: return (0.97, 0.93, 1.00)
            case .orange: return (1.00, 0.96, 0.90)
            case .blue:   return (0.93, 0.96, 1.00)
            case .green:  return (0.93, 0.98, 0.94)
            }
        }()
        return RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(red: colors.0, green: colors.1, blue: colors.2))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 0.6)
            )
    }
}

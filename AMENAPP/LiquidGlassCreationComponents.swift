// LiquidGlassCreationComponents.swift
// AMEN Creator — Liquid Glass Design System
// Reusable components for the creation studio

import SwiftUI

// MARK: - Glass Card

struct GlassCreationCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16
    var strokeOpacity: Double = 0.12
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(Color.black.opacity(strokeOpacity), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Glass Button

struct GlassCreationButton: View {
    let label: String
    let icon: String?
    var style: GlassButtonStyle = .primary
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    enum GlassButtonStyle {
        case primary, secondary, destructive

        var background: Color {
            switch self {
            case .primary:     return .black
            case .secondary:   return .clear
            case .destructive: return Color.red.opacity(0.1)
            }
        }

        var foreground: Color {
            switch self {
            case .primary:     return .white
            case .secondary:   return .primary
            case .destructive: return .red
            }
        }

        var border: Color {
            switch self {
            case .primary:     return .clear
            case .secondary:   return Color.black.opacity(0.15)
            case .destructive: return Color.red.opacity(0.25)
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(style.foreground).scaleEffect(0.85)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(label)
                    .font(.custom("OpenSans-SemiBold", size: 15))
            }
            .foregroundStyle(isDisabled ? .secondary : style.foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isDisabled ? Color.gray.opacity(0.1) : style.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(style.border, lineWidth: 1)
                    )
            )
        }
        .disabled(isDisabled || isLoading)
    }
}

// MARK: - Glass Icon Button

struct GlassIconButton: View {
    let icon: String
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 12
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isSelected ? Color.black : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .strokeBorder(
                                    Color.black.opacity(isSelected ? 0 : 0.15),
                                    lineWidth: 1
                                )
                        )
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}

// MARK: - Refinement Chip

struct CreationRefinementChipView: View {
    let chip: CreationRefinementChip
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: chip.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(chip.label)
                    .font(.custom("OpenSans-SemiBold", size: 13))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Segment Pill

struct SegmentKindPill: View {
    let kind: CreationSegmentKind
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(kind.displayName)
                .font(.custom("OpenSans-SemiBold", size: 11))
        }
        .foregroundStyle(isSelected ? .white : kind.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isSelected ? kind.color : kind.color.opacity(0.1))
        )
    }
}

// MARK: - Duration Badge

struct DurationBadge: View {
    let seconds: Double

    var label: String {
        let s = Int(seconds)
        return s < 60 ? "\(s)s" : "\(s/60)m \(s%60)s"
    }

    var body: some View {
        Text(label)
            .font(.custom("OpenSans-Bold", size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.gray.opacity(0.1))
            )
    }
}

// MARK: - Tone Badge

struct ToneBadge: View {
    let tone: CreationSceneTone

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tone.icon)
                .font(.system(size: 11))
            Text(tone.displayName)
                .font(.custom("OpenSans-SemiBold", size: 11))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.gray.opacity(0.08))
                .overlay(
                    Capsule().strokeBorder(Color.gray.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Loading Shimmer

struct CreationLoadingShimmer: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.08),
                        Color.gray.opacity(0.18),
                        Color.gray.opacity(0.08),
                    ],
                    startPoint: .leading,
                    endPoint: UnitPoint(x: phase, y: 0)
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 2.0
                }
            }
    }
}

// MARK: - Studio Header

struct CreationStudioHeader: View {
    let title: String
    var subtitle: String?
    let onBack: () -> Void
    var trailingAction: (() -> Void)?
    var trailingLabel: String?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 1))
                    )
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 17))
                    .lineLimit(1)
                if let sub = subtitle {
                    Text(sub)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let action = trailingAction, let label = trailingLabel {
                Button(action: action) {
                    Text(label)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.black)
                        )
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }
}

// MARK: - Empty State

struct CreationEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 18))
                Text(message)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            if let label = actionLabel, let act = action {
                Button(action: act) {
                    Text(label)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.black))
                }
            }
        }
        .padding(32)
    }
}

// MARK: - Safety Banner

struct CreationSafetyBanner: View {
    let status: CreationSafetyState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: status == .approved ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 16))
                .foregroundStyle(status.color)

            Text(status == .approved ? "Content approved for posting" : status.label)
                .font(.custom("OpenSans-SemiBold", size: 13))

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(status.color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(status.color.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// BereanContextLensView.swift
// AMEN App — Berean intelligence context lens.
// Floats above the composer cluster to show the AI's current mode, intent,
// source readiness, tone, and a processing ring — without cluttering the
// message area. Glass material only; the conversation canvas stays solid.

import SwiftUI

// MARK: - Lens Models

enum BereanLensSourceReadiness {
    case ready, loading, limited

    var label: String {
        switch self {
        case .ready:   return "Sources ready"
        case .loading: return "Loading context"
        case .limited: return "Limited sources"
        }
    }
    var icon: String {
        switch self {
        case .ready:   return "checkmark.circle.fill"
        case .loading: return "arrow.trianglehead.clockwise"
        case .limited: return "exclamationmark.triangle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .ready:   return Color(red: 0.41, green: 0.69, blue: 0.54)
        case .loading: return Color.orange.opacity(0.85)
        case .limited: return Color.secondary
        }
    }
}

enum BereanLensTone: String {
    case warm      = "Warm"
    case neutral   = "Neutral"
    case scholarly = "Scholarly"
    case prayerful = "Prayerful"

    var icon: String {
        switch self {
        case .warm:      return "heart.fill"
        case .neutral:   return "minus"
        case .scholarly: return "book.closed.fill"
        case .prayerful: return "hands.sparkles.fill"
        }
    }
}

// MARK: - BereanContextLensView

struct BereanContextLensView: View {
    let mode: BereanInteractionMode
    let intent: String
    let sourceReadiness: BereanLensSourceReadiness
    let tone: BereanLensTone
    let isProcessing: Bool
    var onCollapse: (() -> Void)? = nil

    @State private var appeared = false
    @State private var spinAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            modeRing
            centerStack
            if let onCollapse {
                collapseButton(onCollapse)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(lensBackground)
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0) : .spring(response: 0.42, dampingFraction: 0.72)) {
                appeared = true
            }
            if isProcessing && !reduceMotion {
                startSpinAnimation()
                startPulseAnimation()
            }
        }
        .onChange(of: isProcessing) { _, processing in
            if processing && !reduceMotion {
                startSpinAnimation()
                startPulseAnimation()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Berean \(mode.rawValue) mode. \(intent). \(sourceReadiness.label). Tone: \(tone.rawValue).")
    }

    // MARK: - Sub-views

    private var modeRing: some View {
        ZStack {
            Circle()
                .fill(mode.accentColor.opacity(0.10))
                .frame(width: 36, height: 36)

            if isProcessing {
                Circle()
                    .stroke(Color.black.opacity(0.06), lineWidth: 2)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(
                        mode.accentColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(spinAngle))
            }

            Image(systemName: mode.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(mode.accentColor)
                .scaleEffect(pulseScale)
        }
    }

    private var centerStack: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(mode.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black)

                readinessBadge

                Spacer(minLength: 0)

                toneBadge
            }

            Text(intent)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.black.opacity(0.50))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var readinessBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: sourceReadiness.icon)
                .font(.system(size: 9, weight: .medium))
                .symbolEffect(.pulse, isActive: isProcessing)
            Text(sourceReadiness.label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(sourceReadiness.tint)
    }

    private var toneBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: tone.icon)
                .font(.system(size: 9))
            Text(tone.rawValue)
                .font(.system(size: 10))
        }
        .foregroundStyle(Color.black.opacity(0.38))
    }

    private func collapseButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.35))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide context lens")
    }

    private var lensBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.regularMaterial)
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.5)
            }
    }

    // MARK: - Animations

    private func startSpinAnimation() {
        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
            spinAngle = 360
        }
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            pulseScale = 1.12
        }
    }
}

// MARK: - Convenience factory

extension BereanContextLensView {
    /// Create from the current BereanChatViewModel state.
    static func fromConversationState(
        mode: BereanInteractionMode,
        isThinking: Bool,
        messageCount: Int
    ) -> BereanContextLensView {
        let intent: String
        if isThinking {
            intent = "Searching scripture and memory…"
        } else if messageCount == 0 {
            intent = "Ready to guide your study"
        } else {
            intent = mode.lensIntent
        }

        return BereanContextLensView(
            mode: mode,
            intent: intent,
            sourceReadiness: isThinking ? .loading : .ready,
            tone: mode.defaultTone,
            isProcessing: isThinking
        )
    }
}

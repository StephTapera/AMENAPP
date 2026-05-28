// CommsGlassSystem.swift
// AMEN Comms OS — Intelligence-Reactive Liquid Glass (Phase 1 / Agent 1)
//
// Glass intensity, tint, and border react to intelligence signals.
// Urgent items firm the surface; calm items soften and allow more bleed.
// Degrades cleanly under Reduce Transparency, Reduce Motion, Increased Contrast.

import SwiftUI

// MARK: - Intelligence Signal

struct CommsIntelligenceSignal: Equatable {
    let urgency: CommsSignalUrgency
    let confidence: Double   // 0.0 – 1.0
    let hasUnresolved: Bool

    static let neutral = CommsIntelligenceSignal(urgency: .low,  confidence: 1.0, hasUnresolved: false)
    static let active  = CommsIntelligenceSignal(urgency: .medium, confidence: 0.8, hasUnresolved: false)
    static let urgent  = CommsIntelligenceSignal(urgency: .high,  confidence: 0.9, hasUnresolved: true)
    static let critical = CommsIntelligenceSignal(urgency: .critical, confidence: 0.95, hasUnresolved: true)
}

enum CommsSignalUrgency: Int, Equatable, Comparable {
    case low = 0, medium = 1, high = 2, critical = 3
    static func < (lhs: CommsSignalUrgency, rhs: CommsSignalUrgency) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Bridge from ConversationUrgency

extension CommsIntelligenceSignal {
    init(from urgency: ConversationUrgency, confidence: Double = 1.0, hasUnresolved: Bool = false) {
        let mapped: CommsSignalUrgency
        switch urgency {
        case .low:      mapped = .low
        case .medium:   mapped = .medium
        case .high:     mapped = .high
        case .critical: mapped = .critical
        }
        self.init(urgency: mapped, confidence: confidence, hasUnresolved: hasUnresolved)
    }
}

// MARK: - Signal → Visual Properties

private extension CommsIntelligenceSignal {
    var material: Material {
        switch urgency {
        case .low:      return .ultraThinMaterial
        case .medium:   return .thinMaterial
        case .high:     return .regularMaterial
        case .critical: return .regularMaterial
        }
    }

    var tintColor: Color {
        switch urgency {
        case .low:      return .white
        case .medium:   return Color(.systemBlue).opacity(0.08)
        case .high:     return Color(.systemOrange).opacity(0.12)
        case .critical: return Color(.systemRed).opacity(0.16)
        }
    }

    var tintOpacity: Double {
        switch urgency {
        case .low: return 0.06; case .medium: return 0.10
        case .high: return 0.14; case .critical: return 0.20
        }
    }

    var borderColor: Color {
        switch urgency {
        case .low:      return .white
        case .medium:   return .blue
        case .high:     return .orange
        case .critical: return .red
        }
    }

    var baseBorderOpacity: Double {
        switch urgency {
        case .low: return 0.22; case .medium: return 0.30
        case .high: return 0.38; case .critical: return 0.46
        }
    }

    var shadowColor: Color {
        switch urgency {
        case .low, .medium: return .black.opacity(0.07)
        case .high:         return .orange.opacity(0.12)
        case .critical:     return .red.opacity(0.15)
        }
    }

    var shadowRadius: CGFloat {
        switch urgency {
        case .low: return 8; case .medium: return 12; case .high: return 16; case .critical: return 20
        }
    }

    var shadowY: CGFloat {
        switch urgency {
        case .low: return 2; case .medium: return 4; case .high: return 6; case .critical: return 8
        }
    }
}

// MARK: - ViewModifier

struct CommsGlassModifier: ViewModifier {
    let signal: CommsIntelligenceSignal
    let cornerRadius: CGFloat
    let isPressed: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.colorSchemeContrast)             private var contrast

    private var effectiveBorderOpacity: Double {
        contrast == .increased ? 0.65 : signal.baseBorderOpacity
    }

    func body(content: Content) -> some View {
        content
            .background { background }
            .overlay { border }
            .overlay { specularHighlight }
            .shadow(color: signal.shadowColor, radius: signal.shadowRadius, x: 0, y: signal.shadowY)
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.97 : 1))
            .animation(
                reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.36, dampingFraction: 0.74),
                value: signal.urgency
            )
    }

    @ViewBuilder
    private var background: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(signal.material)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(signal.tintColor.opacity(signal.tintOpacity))
                }
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                signal.borderColor.opacity(effectiveBorderOpacity),
                lineWidth: contrast == .increased ? 1.0 : 0.75
            )
    }

    private var specularHighlight: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.35), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 0.5
            )
    }
}

// MARK: - View Extension

extension View {
    func commsGlass(
        signal: CommsIntelligenceSignal = .neutral,
        cornerRadius: CGFloat = 14,
        isPressed: Bool = false
    ) -> some View {
        modifier(CommsGlassModifier(signal: signal, cornerRadius: cornerRadius, isPressed: isPressed))
    }
}

// MARK: - Comms Glass Card

struct CommsGlassCard<Content: View>: View {
    let signal: CommsIntelligenceSignal
    var cornerRadius: CGFloat = 14
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            .padding(14)
            .commsGlass(signal: signal, cornerRadius: cornerRadius)
            .animation(
                reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8),
                value: signal.urgency
            )
    }
}

// MARK: - Comms Glass Pill

struct CommsGlassPill: View {
    let label: String
    var icon: String? = nil
    var count: Int? = nil
    let signal: CommsIntelligenceSignal
    let action: () -> Void

    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.caption2.weight(.semibold)) }
                Text(displayLabel).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .commsGlass(signal: signal, cornerRadius: 100, isPressed: isPressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(displayLabel)
    }

    private var displayLabel: String {
        if let count, count > 0 { return "\(label) (\(count))" }
        return label
    }

    private var foregroundColor: Color {
        switch signal.urgency {
        case .low:      return .secondary
        case .medium:   return .blue
        case .high:     return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Comms Glass Context Bar

struct CommsGlassContextBar<Content: View>: View {
    let isVisible: Bool
    let signal: CommsIntelligenceSignal
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if isVisible {
            content()
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background {
                    if reduceTransparency {
                        Color(.systemBackground).opacity(0.98)
                    } else {
                        Rectangle().fill(.ultraThinMaterial)
                            .overlay {
                                Rectangle().fill(signal.tintColor.opacity(signal.tintOpacity * 0.5))
                            }
                    }
                }
                .transition(
                    reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
                )
                .animation(
                    reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.8),
                    value: isVisible
                )
        }
    }
}

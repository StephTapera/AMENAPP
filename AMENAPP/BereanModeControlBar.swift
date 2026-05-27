// BereanModeControlBar.swift
// AMEN App — Floating Liquid Glass mode selector for the Berean composer cluster.
// Provides four interaction modes (Ask, Reason, Create, Reflect) in a compact
// pill capsule above the composer. Auxiliary icons for translate, smart action,
// and collapse sit in a divider-separated trailing group.

import SwiftUI

// MARK: - Interaction Mode

enum BereanInteractionMode: String, CaseIterable, Identifiable {
    case ask     = "Ask"
    case reason  = "Reason"
    case create  = "Create"
    case reflect = "Reflect"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ask:     return "bubble.left.fill"
        case .reason:  return "brain.head.profile"
        case .create:  return "paintbrush.pointed.fill"
        case .reflect: return "moon.stars.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .ask:     return Color(red: 0.43, green: 0.58, blue: 0.86)
        case .reason:  return Color(red: 0.39, green: 0.66, blue: 0.54)
        case .create:  return Color(red: 0.79, green: 0.63, blue: 0.27)
        case .reflect: return Color(red: 0.62, green: 0.49, blue: 0.79)
        }
    }

    /// Ambient description shown in the Context Lens when this mode is active.
    var lensIntent: String {
        switch self {
        case .ask:     return "Scripture-first answers to your questions"
        case .reason:  return "Deep analysis and discernment"
        case .create:  return "Spiritual content and reflection writing"
        case .reflect: return "Prayer, contemplation, and stillness"
        }
    }

    /// Default tone for the Context Lens when this mode is active.
    var defaultTone: BereanLensTone {
        switch self {
        case .ask:     return .neutral
        case .reason:  return .scholarly
        case .create:  return .warm
        case .reflect: return .prayerful
        }
    }

    /// Placeholder text shown in the composer for this mode.
    var composerPlaceholder: String {
        switch self {
        case .ask:     return "Ask about this passage…"
        case .reason:  return "Reason through this with me…"
        case .create:  return "Create a reflection on…"
        case .reflect: return "Help me reflect on…"
        }
    }

    /// Maps to the underlying personality mode injected into the AI system prompt.
    var personalityMode: BereanPersonalityMode {
        switch self {
        case .ask:     return .askBerean
        case .reason:  return .discernment
        case .create:  return .creator
        case .reflect: return .prayerCompanion
        }
    }
}

// MARK: - BereanModeControlBar

struct BereanModeControlBar: View {
    @Binding var selectedMode: BereanInteractionMode
    var onTranslate: (() -> Void)? = nil
    var onSmartAction: (() -> Void)? = nil
    var onCollapse: (() -> Void)? = nil

    @Namespace private var modeNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            modePills
            auxiliaryGroup
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .background(barBackground)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Mode pills

    private var modePills: some View {
        HStack(spacing: 3) {
            ForEach(BereanInteractionMode.allCases) { mode in
                modePill(mode)
            }
        }
    }

    @ViewBuilder
    private func modePill(_ mode: BereanInteractionMode) -> some View {
        let isSelected = selectedMode == mode

        Button {
            withAnimation(reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.32, dampingFraction: 0.74)) {
                selectedMode = mode
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(mode.rawValue)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.black : Color.black.opacity(0.45))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(0.88))
                        .shadow(color: Color.black.opacity(0.07), radius: 3, x: 0, y: 1)
                        .matchedGeometryEffect(id: "modeSelection", in: modeNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.rawValue) mode")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Auxiliary controls

    @ViewBuilder
    private var auxiliaryGroup: some View {
        let hasAny = onTranslate != nil || onSmartAction != nil || onCollapse != nil
        if hasAny {
            HStack(spacing: 0) {
                Divider()
                    .frame(height: 18)
                    .opacity(0.28)
                    .padding(.horizontal, 6)

                HStack(spacing: 2) {
                    if let onTranslate {
                        auxiliaryButton(icon: "globe", label: "Translate", action: onTranslate)
                    }
                    if let onSmartAction {
                        auxiliaryButton(icon: "wand.and.stars", label: "Smart action", action: onSmartAction)
                    }
                    if let onCollapse {
                        auxiliaryButton(icon: "chevron.down", label: "Collapse", action: onCollapse)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func auxiliaryButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.42))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Background

    private var barBackground: some View {
        Capsule()
            .fill(.regularMaterial)
            .shadow(color: Color.black.opacity(0.07), radius: 9, x: 0, y: 2)
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.62), lineWidth: 0.5)
            }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var mode: BereanInteractionMode = .ask

    VStack(spacing: 24) {
        BereanModeControlBar(
            selectedMode: $mode,
            onTranslate: {},
            onSmartAction: {},
            onCollapse: {}
        )
        .padding(.horizontal, 16)

        BereanModeControlBar(selectedMode: $mode)
            .padding(.horizontal, 16)
    }
    .padding(.vertical, 40)
    .background(Color(red: 0.96, green: 0.96, blue: 0.94))
}

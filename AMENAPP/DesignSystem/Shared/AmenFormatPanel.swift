// AmenFormatPanel.swift
// AMEN — DesignSystem/Shared
//
// Generic B/I/U keyboard formatting toolbar.
// Consumed by ChurchNoteFormattingBar (which adds church-notes-specific
// highlight and block sections as its trailing content).
// Future surfaces (post composer after editor migration, DM composer) can
// adopt AmenFormatPanel directly.
//
// Glass rendering: GlassEffectContainer groups the three buttons into one
// glass surface so they share a single material layer (no glass-on-glass).
// Fallback (reduceTransparency): solid filled background per button.
//
// Keyboard attachment: use amenFormatPanel(isEnabled:activeState:...) view
// modifier which places the panel in ToolbarItemGroup(placement: .keyboard).

import SwiftUI

// MARK: - Active state

/// The bold/italic/underline state for the format panel.
/// Callers own and mutate this; the panel is purely display + callbacks.
public struct AmenFormatActiveState: Equatable {
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderline: Bool

    public init(isBold: Bool = false, isItalic: Bool = false, isUnderline: Bool = false) {
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
    }

    public static let inactive = AmenFormatActiveState()
}

// MARK: - Panel view

/// Scrollable horizontal B/I/U toolbar, 44 pt tall.
/// Wraps the three buttons in a single GlassEffectContainer so they share
/// one glass layer. Pass `trailingContent` for domain-specific extensions
/// (e.g. highlight pills in ChurchNoteFormattingBar).
public struct AmenFormatPanel<Trailing: View>: View {
    public let activeState: AmenFormatActiveState
    public let onBold: () -> Void
    public let onItalic: () -> Void
    public let onUnderline: () -> Void
    public let trailingContent: (() -> Trailing)?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        activeState: AmenFormatActiveState,
        onBold: @escaping () -> Void,
        onItalic: @escaping () -> Void,
        onUnderline: @escaping () -> Void,
        @ViewBuilder trailingContent: @escaping () -> Trailing
    ) {
        self.activeState = activeState
        self.onBold = onBold
        self.onItalic = onItalic
        self.onUnderline = onUnderline
        self.trailingContent = trailingContent
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if reduceTransparency {
                    solidBIU
                } else {
                    glassBIU
                }
                if trailingContent != nil {
                    panelDivider
                    trailingContent!()
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 44)
        .background(reduceTransparency ? Color(.systemBackground) : Color.clear)
    }

    @ViewBuilder
    private var glassBIU: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                formatButton(icon: "bold",      label: "Bold",
                             isActive: activeState.isBold,      action: onBold)
                formatButton(icon: "italic",    label: "Italic",
                             isActive: activeState.isItalic,    action: onItalic)
                formatButton(icon: "underline", label: "Underline",
                             isActive: activeState.isUnderline, action: onUnderline)
            }
        }
    }

    @ViewBuilder
    private var solidBIU: some View {
        HStack(spacing: 2) {
            solidFormatButton(icon: "bold",      label: "Bold",
                              isActive: activeState.isBold,      action: onBold)
            solidFormatButton(icon: "italic",    label: "Italic",
                              isActive: activeState.isItalic,    action: onItalic)
            solidFormatButton(icon: "underline", label: "Underline",
                              isActive: activeState.isUnderline, action: onUnderline)
        }
    }

    private func formatButton(icon: String, label: String,
                              isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.systemScaled(16, weight: .medium))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .amenGlassEffect()
        .animation(reduceMotion ? nil : .snappy, value: isActive)
    }

    private func solidFormatButton(icon: String, label: String,
                                   isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.systemScaled(16, weight: .medium))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(width: 40, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color.primary.opacity(0.10) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var panelDivider: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 2)
    }
}

// MARK: - No-trailing convenience init

extension AmenFormatPanel where Trailing == EmptyView {
    public init(
        activeState: AmenFormatActiveState,
        onBold: @escaping () -> Void,
        onItalic: @escaping () -> Void,
        onUnderline: @escaping () -> Void
    ) {
        self.activeState = activeState
        self.onBold = onBold
        self.onItalic = onItalic
        self.onUnderline = onUnderline
        self.trailingContent = nil
    }
}

// MARK: - Keyboard toolbar modifier

public extension View {
    /// Attaches AmenFormatPanel to the keyboard toolbar.
    /// When `isEnabled` is false the modifier is a no-op.
    func amenFormatPanel(
        isEnabled: Bool,
        activeState: AmenFormatActiveState,
        onBold: @escaping () -> Void,
        onItalic: @escaping () -> Void,
        onUnderline: @escaping () -> Void
    ) -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if isEnabled {
                    AmenFormatPanel(
                        activeState: activeState,
                        onBold: onBold,
                        onItalic: onItalic,
                        onUnderline: onUnderline
                    )
                }
            }
        }
    }
}

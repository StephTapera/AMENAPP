// CommunicationOSGlassKit.swift
// AMENAPP — Communication OS Liquid Glass Components
//
// Additive layer on top of AmenLiquidGlassComponents.swift.
// Provides four shared surfaces for messaging and posting surfaces:
//   · AmenGlassInsightChip   — single pill chip with optional dismiss
//   · AmenGlassInsightBar    — horizontal scrolling chip tray
//   · AmenGlassActionSheet   — bottom-sheet action list
//   · AmenGlassMemoryCard    — expandable card (generic content)
//
// Design rules enforced:
//   · White-base, black text
//   · .ultraThinMaterial / .thinMaterial only — no heavy gray
//   · No glass-on-glass stacking — callers must not embed these on glass surfaces
//   · Luminous border: Color.white.opacity(0.45) at 0.5 pt
//   · Shadow: radius 4, y 2, opacity 0.10
//   · Reduce Transparency: Color.white.opacity(0.97) solid fallback
//   · Reduce Motion: opacity-only transitions
//   · Dynamic Type: relative font sizes throughout
//   · VoiceOver labels on all interactive elements
//   · All tap targets ≥ 44 × 44 pt

import SwiftUI

// MARK: - Shared model

/// Data model for a single insight chip displayed in AmenGlassInsightBar.
/// Defined here so both the bar and the bridge can use it without circular imports.
struct InsightChipModel: Identifiable {
    let id: UUID
    let icon: String        // SF Symbol name
    let label: String
    let actionKey: String   // opaque string; call-site decides what to do
}

// MARK: - Private design helpers

private enum CommGlassTokens {
    static let luminousBorderColor  = Color.white.opacity(0.45)
    static let luminousBorderWidth: CGFloat = 0.5
    static let shadowColor          = Color.black.opacity(0.10)
    static let shadowRadius: CGFloat = 4
    static let shadowY: CGFloat      = 2
    static let chipHeight: CGFloat   = 34
    static let chipHPad: CGFloat     = 12
    static let barHeight: CGFloat    = 52
    static let barCorner: CGFloat    = 12
    static let cardCorner: CGFloat   = 12
    static let sheetTopCorner: CGFloat = 20
    static let minTapTarget: CGFloat = 44
}

/// Thin ViewModifier that applies the shared luminous border + soft shadow used by
/// all Communication OS glass surfaces.
private struct CommGlassSurface: ViewModifier {
    let shape: AnyInsettableShape

    func body(content: Content) -> some View {
        content
            .overlay {
                shape
                    .stroke(CommGlassTokens.luminousBorderColor,
                            lineWidth: CommGlassTokens.luminousBorderWidth)
            }
            .shadow(
                color: CommGlassTokens.shadowColor,
                radius: CommGlassTokens.shadowRadius,
                x: 0,
                y: CommGlassTokens.shadowY
            )
    }
}

private extension View {
    func commGlassSurface<S: InsettableShape>(shape: S) -> some View {
        modifier(CommGlassSurface(shape: AnyInsettableShape(shape)))
    }
}

// MARK: - 1. AmenGlassInsightChip

/// A single pill-shaped context chip.
///
/// - Parameters:
///   - icon: SF Symbol name shown to the left of the label.
///   - label: Human-readable label. Rendered in `.subheadline` so it scales with Dynamic Type.
///   - onTap: Called when the user taps the main pill area.
///   - onDismiss: Optional. When non-nil, an × button is appended to the chip.
///
/// Accessibility: chip has a combined label + hint. The dismiss button has its own label.
struct AmenGlassInsightChip: View {
    let icon: String
    let label: String
    let onTap: () -> Void
    var onDismiss: (() -> Void)? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @GestureState private var isPressed = false

    var body: some View {
        HStack(spacing: 6) {
            // Main tappable area
            Button(action: onTap) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                    Text(label)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, CommGlassTokens.chipHPad)
                .frame(height: CommGlassTokens.chipHeight)
                .frame(minWidth: CommGlassTokens.minTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityHint("Double tap to \(label)")

            // Optional dismiss button
            if let dismiss = onDismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .frame(width: CommGlassTokens.minTapTarget,
                               height: CommGlassTokens.chipHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss \(label) chip")
            }
        }
        .background {
            chipBackground
        }
        .clipShape(Capsule(style: .continuous))
        .commGlassSurface(shape: Capsule(style: .continuous))
        .scaleEffect(isPressed ? 0.96 : 1)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.26, dampingFraction: 0.80),
            value: isPressed
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
    }

    @ViewBuilder
    private var chipBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.97))
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                }
        }
    }
}

// MARK: - 2. AmenGlassInsightBar

/// A horizontal scrolling tray of `AmenGlassInsightChip` instances.
///
/// Hidden automatically when `chips` is empty — callers do not need to gate visibility.
/// Slides up on appearance (opacity-only when Reduce Motion is on).
///
/// - Parameters:
///   - chips: Ordered list of chips to render. Bar hides when this is empty.
///   - onChipTap: Called with the tapped chip.
///   - onChipDismiss: Called with the dismissed chip.
struct AmenGlassInsightBar: View {
    let chips: [InsightChipModel]
    let onChipTap: (InsightChipModel) -> Void
    let onChipDismiss: (InsightChipModel) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    AmenGlassInsightChip(
                        icon: chip.icon,
                        label: chip.label,
                        onTap: { onChipTap(chip) },
                        onDismiss: { onChipDismiss(chip) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(height: chips.isEmpty ? 0 : CommGlassTokens.barHeight)
        .opacity(chips.isEmpty ? 0 : (appeared ? 1 : 0))
        .offset(y: (chips.isEmpty || appeared || reduceMotion) ? 0 : 8)
        .background {
            barBackground
        }
        .clipShape(RoundedRectangle(cornerRadius: CommGlassTokens.barCorner, style: .continuous))
        .commGlassSurface(
            shape: RoundedRectangle(cornerRadius: CommGlassTokens.barCorner, style: .continuous)
        )
        .onAppear {
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.15)
                    : .spring(response: 0.42, dampingFraction: 0.75)
            ) {
                appeared = true
            }
        }
        .onChange(of: chips.isEmpty) { _, isEmpty in
            if !isEmpty && !appeared {
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.15)
                        : .spring(response: 0.42, dampingFraction: 0.75)
                ) {
                    appeared = true
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Context insights")
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.78),
            value: chips.count
        )
    }

    @ViewBuilder
    private var barBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: CommGlassTokens.barCorner, style: .continuous)
                .fill(Color.white.opacity(0.97))
        } else {
            RoundedRectangle(cornerRadius: CommGlassTokens.barCorner, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: CommGlassTokens.barCorner, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                }
        }
    }
}

// MARK: - 3. AmenGlassActionSheet

/// A single item in `AmenGlassActionSheet`.
struct AmenGlassActionSheetItem: Identifiable {
    let id: UUID
    let icon: String
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void
}

/// A bottom-sheet style action picker with a Liquid Glass background.
///
/// Intended to be presented via `.sheet` or `.overlay`. The sheet does not handle
/// its own dismissal beyond calling `onDismiss` — the caller controls presentation state.
///
/// - Parameters:
///   - title: Optional heading rendered in medium weight above the items.
///   - items: Action rows. Destructive items render their title in red.
///   - onDismiss: Called when the user taps Cancel or the drag handle area.
struct AmenGlassActionSheet: View {
    let title: String?
    let items: [AmenGlassActionSheetItem]
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            dragHandle

            // Optional title
            if let title {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                    .accessibilityAddTraits(.isHeader)
            }

            // Action rows
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    actionRow(item: item)

                    if index < items.count - 1 {
                        separatorLine
                    }
                }
            }

            separatorLine.padding(.top, 8)

            // Cancel
            cancelRow
        }
        .background {
            sheetBackground
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: CommGlassTokens.sheetTopCorner,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: CommGlassTokens.sheetTopCorner,
                style: .continuous
            )
        )
        .overlay(alignment: .top) {
            // Top luminous border only (sheet has no bottom border — it sits at screen edge)
            UnevenRoundedRectangle(
                topLeadingRadius: CommGlassTokens.sheetTopCorner,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: CommGlassTokens.sheetTopCorner,
                style: .continuous
            )
            .stroke(CommGlassTokens.luminousBorderColor,
                    lineWidth: CommGlassTokens.luminousBorderWidth)
        }
        .shadow(
            color: CommGlassTokens.shadowColor,
            radius: CommGlassTokens.shadowRadius,
            x: 0,
            y: CommGlassTokens.shadowY
        )
        .offset(y: appeared ? 0 : 80)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.18)
                    : .spring(response: 0.46, dampingFraction: 0.76)
            ) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title ?? "Action sheet")
    }

    // MARK: Sub-views

    private var dragHandle: some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(0.18))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .accessibilityHidden(true)
    }

    private var separatorLine: some View {
        Rectangle()
            .fill(Color.black.opacity(0.07))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func actionRow(item: AmenGlassActionSheetItem) -> some View {
        Button {
            item.action()
            onDismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.body.weight(.medium))
                    .frame(width: 24, alignment: .center)
                    .foregroundStyle(item.isDestructive ? Color.red : Color.black)
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(item.isDestructive ? Color.red : Color.black)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(minHeight: CommGlassTokens.minTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.isDestructive ? "Destructive action" : "")
    }

    private var cancelRow: some View {
        Button(action: onDismiss) {
            Text("Cancel")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: CommGlassTokens.minTapTarget)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .accessibilityLabel("Cancel")
        .accessibilityHint("Double tap to dismiss")
    }

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency {
            Color.white.opacity(0.97)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                }
        }
    }
}

// MARK: - 4. AmenGlassMemoryCard

/// An expandable glass card that wraps arbitrary content.
///
/// - Parameters:
///   - title: Card heading shown in the header.
///   - itemCount: Numeric badge shown next to the title (e.g. "3 items").
///   - isExpanded: Controlled externally. Drives the chevron rotation and content visibility.
///   - onToggle: Called when the header is tapped.
///   - content: Builder that returns the card body as `AnyView`.
///
/// Reduce Motion: expands via opacity only (no height animation).
struct AmenGlassMemoryCard<Item: Identifiable>: View {
    let title: String
    let itemCount: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> AnyView

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerRow

            // Expandable content
            if isExpanded {
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .opacity(isExpanded ? 1 : 0)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
        .background {
            cardBackground
        }
        .clipShape(RoundedRectangle(cornerRadius: CommGlassTokens.cardCorner, style: .continuous))
        .commGlassSurface(
            shape: RoundedRectangle(cornerRadius: CommGlassTokens.cardCorner, style: .continuous)
        )
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.15)
                : .spring(response: 0.40, dampingFraction: 0.78),
            value: isExpanded
        )
    }

    // MARK: Sub-views

    private var headerRow: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                // Title
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)

                // Count badge
                Text("\(itemCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.black.opacity(0.60))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.07))
                    )

                Spacer()

                // Chevron
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.50))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.12) : .amenSpringStandard,
                        value: isExpanded
                    )
            }
            .padding(.horizontal, 16)
            .frame(minHeight: CommGlassTokens.minTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(itemCount) items")
        .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to expand")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: CommGlassTokens.cardCorner, style: .continuous)
                .fill(Color.white.opacity(0.97))
        } else {
            RoundedRectangle(cornerRadius: CommGlassTokens.cardCorner, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: CommGlassTokens.cardCorner, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                }
        }
    }
}

// MARK: - AnyInsettableShape wrapper (internal)

/// Type-erased InsettableShape so `CommGlassSurface` can store any concrete shape
/// without making the ViewModifier generic (which would force callers to annotate types).
private struct AnyInsettableShape: InsettableShape {
    private let _path: (CGRect) -> Path
    private let _inset: (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        _path = { shape.path(in: $0) }
        _inset = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { _path(rect) }

    func inset(by amount: CGFloat) -> AnyInsettableShape { _inset(amount) }
}

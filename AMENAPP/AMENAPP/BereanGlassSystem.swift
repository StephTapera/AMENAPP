// BereanGlassSystem.swift
// AMEN App — Shared Berean Liquid Glass design token system.
//
// Three precision implementations for distinct surface densities and contexts.
// Inject via .bereanGlass(_:) environment modifier or pass directly.
//
// Usage:
//   SomeView()
//     .bereanGlass(.lensed)   // Landing, Voice
//     .bereanGlass(.contextual) // Home, Chat List (default)
//     .bereanGlass(.compressed) // Chat, Composer

import SwiftUI

// MARK: - Berean Glass Implementation

enum BereanGlass {

    // ── Three precision presets ───────────────────────────────────────────

    enum Impl: String, CaseIterable, Hashable {
        /// Most premium. Strongest blur + depth. Best for Landing, Voice, Home hero.
        case lensed
        /// Best default. Adaptive, balanced hierarchy. Best for Chat, Chats list, Home.
        case contextual
        /// Most practical. Tightest spacing, lightest blur. Best for dense Chat, Composer.
        case compressed

        // White overlay fill opacities (applied on top of ultraThinMaterial)
        var shellFill: Double      { switch self { case .lensed: 0.28; case .contextual: 0.24; case .compressed: 0.18 } }
        var cardFill: Double       { switch self { case .lensed: 0.34; case .contextual: 0.28; case .compressed: 0.22 } }
        var faintFill: Double      { switch self { case .lensed: 0.18; case .contextual: 0.14; case .compressed: 0.10 } }
        var pillFill: Double       { switch self { case .lensed: 0.42; case .contextual: 0.34; case .compressed: 0.26 } }
        var borderOpacity: Double  { switch self { case .lensed: 0.40; case .contextual: 0.35; case .compressed: 0.28 } }
        var shadowOpacity: Double  { switch self { case .lensed: 0.16; case .contextual: 0.12; case .compressed: 0.10 } }
        var shadowRadius: CGFloat  { switch self { case .lensed: 22;   case .contextual: 14;   case .compressed: 10   } }
        var cornerRadius: CGFloat  { switch self { case .lensed: 28;   case .contextual: 24;   case .compressed: 20   } }

        var label: String { rawValue.capitalized }
        var description: String {
            switch self {
            case .lensed:      "Floating adaptive panels, stronger translucency, cinematic depth."
            case .contextual:  "Subtle tint shifts, cleaner hierarchy, safer for full-app use."
            case .compressed:  "Tighter spacing, reduced blur, faster-feeling transitions."
            }
        }

        /// Recommended implementation per Berean surface
        static func recommended(for surface: Surface) -> Impl {
            switch surface {
            case .home:      .contextual
            case .chat:      .compressed
            case .chatsList: .contextual
            case .landing:   .lensed
            case .voice:     .lensed
            case .composer:  .contextual
            }
        }
    }

    enum Surface: String, CaseIterable {
        case home      = "BereanHomeView"
        case chat      = "BereanChatView"
        case chatsList = "BereanChatsListView"
        case landing   = "BereanLandingView"
        case voice     = "BereanVoiceView"
        case composer  = "BereanComposerBar"
    }
}

// MARK: - Environment Key

private struct BereanGlassImplKey: EnvironmentKey {
    static let defaultValue: BereanGlass.Impl = .contextual
}

extension EnvironmentValues {
    var bereanGlass: BereanGlass.Impl {
        get { self[BereanGlassImplKey.self] }
        set { self[BereanGlassImplKey.self] = newValue }
    }
}

extension View {
    func bereanGlass(_ impl: BereanGlass.Impl) -> some View {
        environment(\.bereanGlass, impl)
    }
}

// MARK: - BereanGlassCard

/// The primary glass card surface. Used for section cards, conversation rows, hero blocks.
struct BereanGlassCard<Content: View>: View {
    @Environment(\.bereanGlass) private var impl
    var cornerRadius: CGFloat? = nil
    var padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(glassBackground(fill: impl.cardFill, radius: cornerRadius ?? impl.cornerRadius))
            .overlay(glassBorder(radius: cornerRadius ?? impl.cornerRadius, opacity: impl.borderOpacity))
            .shadow(color: .black.opacity(impl.shadowOpacity), radius: impl.shadowRadius, y: impl.shadowRadius * 0.3)
    }
}

// MARK: - BereanTopBar

/// Sticky floating glass navigation bar — shared across all Berean surfaces.
struct BereanTopBar: View {
    @Environment(\.bereanGlass) private var impl
    let title: String
    var subtitle: String? = nil
    var leadingContent: AnyView? = nil
    var trailingContent: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let leading = leadingContent {
                leading
            }

            VStack(alignment: leadingContent == nil && trailingContent == nil ? .center : .leading,
                   spacing: 2) {
                Text(title)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)
                if let sub = subtitle {
                    Text(sub)
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity,
                   alignment: leadingContent == nil && trailingContent == nil ? .center : .leading)

            if let trailing = trailingContent {
                trailing
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(glassBackground(fill: impl.pillFill, radius: 24))
        .overlay(glassBorder(radius: 24, opacity: impl.borderOpacity))
        .shadow(color: .black.opacity(impl.shadowOpacity * 0.7), radius: 10, y: 3)
    }
}

// MARK: - BereanModeChip

/// Selectable mode/filter chip. Active = black fill. Inactive = faint glass.
struct BereanModeChip: View {
    @Environment(\.bereanGlass) private var impl
    let label: String
    var icon: String? = nil
    var isActive: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.systemScaled(12, weight: .medium))
                }
                Text(label)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.78))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? Color.black : Color.white.opacity(impl.faintFill))
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(isActive ? 0 : 1)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isActive ? Color.clear : Color.white.opacity(impl.borderOpacity),
                                lineWidth: 0.75
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - BereanContextStrip

/// Thin floating strip that updates by context — sits below top bar.
/// Examples: "In Romans study", "Prayer mode active", "Sermon transcript attached"
struct BereanContextStrip: View {
    @Environment(\.bereanGlass) private var impl
    let label: String
    var icon: String? = "circle.fill"
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.systemScaled(7, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.45))
                }
                Text(label)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.primary.opacity(0.65))
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(10, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.35))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).fill(Color.white.opacity(impl.faintFill)))
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(impl.borderOpacity), lineWidth: 0.6))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - BereanDiscernmentPicker

/// Segmented mode selector: Explain / Study / Compare / Pray / Apply / Discern
struct BereanDiscernmentPicker: View {
    @Environment(\.bereanGlass) private var impl
    @Binding var selected: BereanDiscernmentMode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(BereanDiscernmentMode.allCases, id: \.self) { mode in
                    BereanModeChip(
                        label: mode.label,
                        icon: mode.icon,
                        isActive: selected == mode
                    ) {
                        withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.78))) {
                            selected = mode
                        }
                        HapticManager.impact(style: .light)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

enum BereanDiscernmentMode: String, CaseIterable {
    case explain, study, compare, pray, apply, discern

    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .explain:  "text.bubble"
        case .study:    "book.pages"
        case .compare:  "arrow.left.arrow.right"
        case .pray:     "hands.sparkles"
        case .apply:    "checkmark.circle"
        case .discern:  "shield.lefthalf.filled"
        }
    }
}

// MARK: - BereanSmartFollowUpChips

/// Context-aware follow-up chip row. Fades in after AI response, fades if ignored.
struct BereanSmartFollowUpChips: View {
    @Environment(\.bereanGlass) private var impl
    let chips: [String]
    var onSelect: (String) -> Void = { _ in }
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let defaults: [String] = [
        "Show me the context",
        "Compare translations",
        "Turn this into prayer",
        "What do commentators say",
        "Give me the hard truth"
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(chips.enumerated()), id: \.offset) { idx, chip in
                    Button {
                        onSelect(chip)
                    } label: {
                        Text(chip)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.primary.opacity(0.80))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule(style: .continuous).fill(Color.white.opacity(impl.faintFill)))
                                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(impl.borderOpacity), lineWidth: 0.6))
                            )
                    }
                    .buttonStyle(.plain)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.8).delay(Double(idx) * 0.05),
                        value: appeared
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - BereanReflectionCard

/// "Sit with this" card — appears after deep answers. Spiritual accountability moment.
struct BereanReflectionCard: View {
    @Environment(\.bereanGlass) private var impl
    let verse: String
    let question: String
    let prayer: String
    var onSave: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BereanGlassCard(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.stars")
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.60))
                        Text("Sit with this")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.primary.opacity(0.70))
                    }
                    Spacer()
                    if let dismiss = onDismiss {
                        Button(action: dismiss) {
                            Image(systemName: "xmark")
                                .font(.systemScaled(11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(.ultraThinMaterial).overlay(Circle().fill(Color.white.opacity(0.50))))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Verse
                VStack(alignment: .leading, spacing: 4) {
                    Text("Key verse")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                    Text(verse)
                        .font(.systemScaled(15, weight: .regular, design: .serif))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Question
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reflect")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                    Text(question)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.primary.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Prayer
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pray")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                    Text(prayer)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.primary.opacity(0.70))
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Actions
                HStack(spacing: 10) {
                    if let save = onSave {
                        Button(action: save) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.systemScaled(12, weight: .medium))
                                Text("Save to notes")
                                    .font(AMENFont.semiBold(12))
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule(style: .continuous).fill(Color.white.opacity(impl.pillFill)))
                                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(impl.borderOpacity), lineWidth: 0.6))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text("Revisit later")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scaleEffect(appeared ? 1.0 : 0.96)
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.40, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }
}

// MARK: - BereanGlassUtilButton

/// Small glass circle icon button — top-bar utilities (search, mic, history).
struct BereanGlassUtilButton: View {
    @Environment(\.bereanGlass) private var impl
    let icon: String
    var size: CGFloat = 36
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.systemScaled(15, weight: .medium))
                .foregroundStyle(.primary.opacity(0.78))
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(impl.pillFill)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(impl.borderOpacity), lineWidth: 0.75))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Private Helpers

private func glassBackground(fill: Double, radius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white.opacity(fill))
        )
}

private func glassBorder(radius: CGFloat, opacity: Double) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .strokeBorder(
            LinearGradient(
                colors: [Color.white.opacity(opacity), Color.white.opacity(opacity * 0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 0.75
        )
}

import SwiftUI

// MARK: - Spiritual OS Shared Components
// All Phase 2 agents import from this file only — never copy internals.
// Signatures frozen in SharedComponents.contract.md.
// Lead populates real implementations; agents build on top of stubs.

// ── Motion helper ──────────────────────────────────────────────────────────────

extension Animation {
    static func soAdaptive(
        reduceMotion: Bool,
        response: Double = LiquidGlassTokens.motionNormal
    ) -> Animation {
        reduceMotion
            ? .easeOut(duration: LiquidGlassTokens.motionFast)
            : .spring(response: response, dampingFraction: 0.82)
    }
}

// ── GlassCard ─────────────────────────────────────────────────────────────────

struct GlassCard<Content: View>: View {
    var tint: Color? = nil
    var elevated: Bool = false
    var isPressed: Bool = false
    var scrollDepth: CGFloat = 0
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LiquidGlassCard(
            contextTint: tint,
            elevated: elevated,
            pressed: isPressed,
            scrollDepth: scrollDepth,
            content: content
        )
    }
}

// ── GlassBarPlacement ─────────────────────────────────────────────────────────

enum GlassBarPlacement {
    case bottom, top, floating
}

// ── GlassBar ──────────────────────────────────────────────────────────────────

struct GlassBar<Content: View>: View {
    var placement: GlassBarPlacement = .bottom
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .livingGlassMaterial(tint: tint, elevated: false)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.55))
                    .frame(height: 0.5)
            }
    }
}

// ── GlassSheet ────────────────────────────────────────────────────────────────

struct GlassSheet<Content: View>: View {
    var title: String
    var tint: Color? = nil
    var showDismissButton: Bool = true
    var onDismiss: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.amenSlate.opacity(0.35))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 8)

            // Glass header bar
            GlassBar(placement: .top, tint: tint) {
                HStack {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.amenBlack)
                    Spacer()
                    if showDismissButton {
                        Button(action: { onDismiss?() }) {
                            Image(systemName: "chevron.down")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color.amenSlate)
                        }
                        .accessibilityLabel("Dismiss")
                    }
                }
            }

            content()
        }
        .background(Color.amenCream)
    }
}

// ── GlassChipSize ─────────────────────────────────────────────────────────────

enum GlassChipSize {
    case compact, regular, large

    var horizontalPadding: CGFloat { switch self { case .compact: 8; case .regular: 12; case .large: 16 } }
    var verticalPadding: CGFloat   { switch self { case .compact: 4; case .regular: 7;  case .large: 10 } }
    var fontSize: Font             { switch self { case .compact: .caption2; case .regular: .subheadline; case .large: .body } }
}

// ── GlassChip ─────────────────────────────────────────────────────────────────

struct GlassChip: View {
    var label: String
    var icon: String? = nil
    var tint: Color? = nil
    var size: GlassChipSize = .regular
    var isActive: Bool = false
    var action: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resolvedTint: Color { tint ?? .amenGold }

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(size.fontSize.weight(.medium))
                        .symbolRenderingMode(.hierarchical)
                }
                Text(label)
                    .font(size.fontSize)
            }
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .foregroundStyle(isActive ? resolvedTint : Color.amenBlack.opacity(0.8))
            .background {
                Capsule()
                    .fill(isActive
                          ? resolvedTint.opacity(colorScheme == .dark ? 0.25 : 0.15)
                          : LiquidGlassTokens.blurThin)
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isActive ? resolvedTint.opacity(0.6) : Color.white.opacity(0.35),
                                lineWidth: isActive ? 1.5 : 0.5
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .animation(.soAdaptive(reduceMotion: reduceMotion, response: LiquidGlassTokens.motionFast), value: isActive)
    }
}

// ── HeroCard supporting types ─────────────────────────────────────────────────

struct HeroCardEvent {
    let title: String
    let date: Date
    let icon: String
}

struct HeroCardAction {
    let label: String
    let icon: String
    let action: () -> Void
}

// ── HeroCard ──────────────────────────────────────────────────────────────────

struct HeroCard: View {
    var title: String
    var subtitle: String? = nil
    var coverImageURL: URL? = nil
    var tint: Color
    var memberAvatars: [URL]
    var memberCount: Int
    var nextEvent: HeroCardEvent? = nil
    var actions: [HeroCardAction]
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Cover / tint background
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.7), Color.amenBlack],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Bottom scrim
                LinearGradient(
                    colors: [Color.clear, Color.amenBlack.opacity(0.6)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 10) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }

                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.white)

                    MemberAvatarRow(avatarURLs: memberAvatars, memberCount: memberCount)

                    if let event = nextEvent {
                        GlassChip(
                            label: "\(event.title)",
                            icon: event.icon,
                            tint: .amenBlue,
                            size: .compact,
                            isActive: true
                        )
                    }

                    // Actions — 2-up chip grid
                    let grid = actions.prefix(4).chunked(into: 2)
                    ForEach(Array(grid.enumerated()), id: \.offset) { _, pair in
                        HStack(spacing: 8) {
                            ForEach(Array(pair.enumerated()), id: \.offset) { _, heroAction in
                                GlassChip(label: heroAction.label, icon: heroAction.icon, tint: tint, isActive: false) {
                                    heroAction.action()
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous))
        .livingGlassMaterial(tint: tint, elevated: true)
        .shadow(
            color: LiquidGlassTokens.shadowFloating.color,
            radius: LiquidGlassTokens.shadowFloating.radius,
            y: LiquidGlassTokens.shadowFloating.y
        )
    }
}

// ── TimelineRowBadge ──────────────────────────────────────────────────────────

enum TimelineRowBadge {
    case tag(String, Color)
    case count(Int)
    case dot(Color)
}

// ── TimelineRow ───────────────────────────────────────────────────────────────

struct TimelineRow: View {
    var icon: String
    var iconTint: Color = .amenGold
    var title: String
    var subtitle: String? = nil
    var timestamp: Date? = nil
    var badge: TimelineRowBadge? = nil
    var isCompleted: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(alignment: .top, spacing: 12) {
                // Icon + vertical connector
                VStack(spacing: 0) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : icon)
                        .font(.body)
                        .foregroundStyle(isCompleted ? Color.amenGold : iconTint)
                        .frame(width: 24, height: 24)
                    Rectangle()
                        .fill(Color.amenGold.opacity(0.25))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title)
                            .font(.subheadline.weight(isCompleted ? .regular : .medium))
                            .foregroundStyle(isCompleted ? Color.amenSlate : Color.amenBlack)
                            .strikethrough(isCompleted, color: .amenSlate)
                        Spacer()
                        if let badge {
                            badgeView(badge)
                        }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.amenSlate)
                    }
                    if let timestamp {
                        Text(timestamp.relativeFormatted)
                            .font(.caption2)
                            .foregroundStyle(Color.amenSlate.opacity(0.7))
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func badgeView(_ badge: TimelineRowBadge) -> some View {
        switch badge {
        case .tag(let label, let color):
            GlassChip(label: label, tint: color, size: .compact, isActive: true)
        case .count(let n):
            GlassChip(label: "\(n)", tint: .amenSlate, size: .compact)
        case .dot(let color):
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
    }
}

// ── AssistantBar ──────────────────────────────────────────────────────────────

struct AssistantBar: View {
    var placeholder: String
    var contextSurface: SOSurface
    var onSubmit: (String) -> Void
    var onCamera: () -> Void
    var onVoice: () -> Void
    var quickPrompts: [String]

    @State private var isFocused = false
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 6) {
            if isFocused && !quickPrompts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickPrompts.prefix(3), id: \.self) { prompt in
                            GlassChip(label: prompt, tint: .amenPurple, size: .compact) {
                                onSubmit(prompt)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            GlassBar(placement: .floating, tint: .amenPurple.opacity(0.3)) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.body)
                        .foregroundStyle(Color.amenPurple)

                    TextField(placeholder, text: $inputText)
                        .font(.subheadline.italic())
                        .foregroundStyle(Color.amenSlate)
                        .onTapGesture { withAnimation { isFocused = true } }
                        .onSubmit {
                            guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            onSubmit(inputText)
                            inputText = ""
                            isFocused = false
                        }

                    Spacer()

                    Button(action: onCamera) {
                        Image(systemName: "camera.fill")
                            .font(.body)
                            .foregroundStyle(Color.amenPurple)
                    }
                    .accessibilityLabel("Open camera for verse detection")

                    Button(action: onVoice) {
                        Image(systemName: "mic.fill")
                            .font(.body)
                            .foregroundStyle(Color.amenPurple)
                    }
                    .accessibilityLabel("Start voice session")
                }
            }
            .clipShape(Capsule())
        }
    }
}

// ── MemberAvatarRow ───────────────────────────────────────────────────────────

struct MemberAvatarRow: View {
    var avatarURLs: [URL]
    var memberCount: Int
    var size: CGFloat = 32
    var overlap: CGFloat = 10
    var borderColor: Color = .white

    private let maxVisible = 5

    var body: some View {
        HStack(spacing: -(overlap)) {
            ForEach(Array(avatarURLs.prefix(maxVisible).enumerated()), id: \.offset) { index, url in
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.amenSlate.opacity(0.3))
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(borderColor, lineWidth: 2))
                .zIndex(Double(maxVisible - index))
            }

            if memberCount > maxVisible {
                GlassChip(
                    label: "+\(memberCount - maxVisible)",
                    tint: .amenSlate,
                    size: .compact
                )
            }
        }
    }
}

// ── Date relative formatter ────────────────────────────────────────────────────

private extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}

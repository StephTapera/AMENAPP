import SwiftUI

// MARK: - Feature Flags

enum LiquidGlassEffectsFlags {
    static let scrollResponsiveSearch = true
    static let successChips = true
    static let floatingStatusPill = true
    static let jumpToLatestPill = true
    static let composerCompression = true
    static let hideOnScrollChips = true
    static let reactionSheet = true
    static let buttonHighlightSweep = true
    static let badgeMorphDot = true
    static let stickyHeaderSoften = true
}

// MARK: - Motion Helpers

enum LiquidGlassMotion {
    static let short = Animation.easeOut(duration: 0.18)
    static let medium = Animation.easeOut(duration: 0.25)
    static let softSpring = Animation.spring(response: 0.32, dampingFraction: 0.85)
}

struct ReduceMotionGuard: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let enabled: Bool

    func body(content: Content) -> some View {
        if reduceMotion || !enabled {
            content
        } else {
            content
                .animation(LiquidGlassMotion.medium, value: UUID())
        }
    }
}

// MARK: - 1) Scroll-Responsive Glass Modifier

struct ScrollResponsiveGlassModifier: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        let clamped = min(max(progress, 0), 1)
        return content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.70 + 0.10 * clamped))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.04 + 0.06 * clamped), lineWidth: 0.5)
                    )
            )
            .scaleEffect(1.0 - 0.015 * clamped)
            .opacity(1.0 - 0.05 * clamped)
    }
}

extension View {
    func scrollResponsiveGlass(progress: CGFloat, enabled: Bool = LiquidGlassEffectsFlags.scrollResponsiveSearch) -> some View {
        if enabled {
            return AnyView(self.modifier(ScrollResponsiveGlassModifier(progress: progress)))
        }
        return AnyView(self)
    }
}

// MARK: - 2) Success Chip Presenter

struct SuccessChip: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let systemIcon: String?
}

final class SuccessChipCenter: ObservableObject {
    @Published private(set) var chips: [SuccessChip] = []

    func show(_ text: String, icon: String? = "checkmark") {
        guard LiquidGlassEffectsFlags.successChips else { return }
        let chip = SuccessChip(text: text, systemIcon: icon)
        chips.append(chip)
        if chips.count > 2 { chips.removeFirst(chips.count - 2) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.chips.removeAll { $0.id == chip.id }
        }
    }
}

struct SuccessChipPresenter: ViewModifier {
    @ObservedObject var center: SuccessChipCenter

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            VStack(spacing: 6) {
                ForEach(center.chips) { chip in
                    HStack(spacing: 6) {
                        if let icon = chip.systemIcon {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(chip.text)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(Color.white.opacity(0.70)))
                            .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    )
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.top, 6)
        }
    }
}

extension View {
    func successChips(_ center: SuccessChipCenter) -> some View {
        modifier(SuccessChipPresenter(center: center))
    }
}

// MARK: - 3) Floating Status Pill

struct FloatingStatusPillView: View {
    let text: String
    let systemIcon: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemIcon {
                Image(systemName: systemIcon)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.70)))
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

// MARK: - 4) Jump to Latest Pill

struct JumpToLatestPill: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                Text("Latest")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.black)
            )
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

// MARK: - 5) Composer Compression

struct ComposerCompressionModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        let scale: CGFloat = isActive ? 0.985 : 1.0
        let opacity: CGFloat = isActive ? 0.96 : 1.0
        return content
            .scaleEffect(scale)
            .opacity(opacity)
    }
}

extension View {
    func composerCompression(_ isActive: Bool, enabled: Bool = LiquidGlassEffectsFlags.composerCompression) -> some View {
        if enabled {
            return AnyView(self.modifier(ComposerCompressionModifier(isActive: isActive)))
        }
        return AnyView(self)
    }
}

// MARK: - 6) Auto-Hiding Chip Row

struct AutoHidingChipRowModifier: ViewModifier {
    let isHidden: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isHidden ? 0 : 1)
            .offset(y: isHidden ? 6 : 0)
            .frame(height: isHidden ? 0 : nil)
            .clipped()
    }
}

extension View {
    func autoHideChips(_ hide: Bool, enabled: Bool = LiquidGlassEffectsFlags.hideOnScrollChips) -> some View {
        if enabled {
            return AnyView(self.modifier(AutoHidingChipRowModifier(isHidden: hide)))
        }
        return AnyView(self)
    }
}

// MARK: - 7) Soft Reaction Sheet (anchor overlay)

struct SoftReactionSheet: View {
    let actions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(actions, id: \.self) { action in
                Button(action: { onSelect(action) }) {
                    Text(action)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.72)))
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
        )
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
    }
}

// MARK: - 8) Button Highlight Sweep

struct HighlightSweepModifier: ViewModifier {
    @State private var animate = false
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    if isActive {
                        Rectangle()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: geo.size.width * 0.25)
                            .rotationEffect(.degrees(12))
                            .offset(x: animate ? geo.size.width * 1.2 : -geo.size.width)
                            .onAppear {
                                withAnimation(.easeOut(duration: 0.35)) { animate = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { animate = false }
                            }
                    }
                }
            )
            .mask(content)
    }
}

extension View {
    func highlightSweep(trigger: Bool, enabled: Bool = LiquidGlassEffectsFlags.buttonHighlightSweep) -> some View {
        if enabled {
            return AnyView(self.modifier(HighlightSweepModifier(isActive: trigger)))
        }
        return AnyView(self)
    }
}

// MARK: - 9) Morphing Badge

struct MorphingBadgeView: View {
    let count: Int
    let useDot: Bool

    var body: some View {
        let showDot = useDot && count > 0
        ZStack {
            if showDot {
                Circle()
                    .fill(Color.black)
                    .frame(width: 8, height: 8)
            } else if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.black)
                    )
            }
        }
        .animation(LiquidGlassMotion.medium, value: showDot)
        .accessibilityLabel("\(count) notifications")
    }
}

// MARK: - 10) Sticky Header Soften

struct SoftStickyHeaderModifier: ViewModifier {
    let isActive: Bool
    let intensity: CGFloat

    func body(content: Content) -> some View {
        let clamped = min(max(intensity, 0), 1)
        return content
            .opacity(isActive ? 1.0 - 0.12 * clamped : 1.0)
            .background(
                Color.white.opacity(isActive ? 0.85 : 1.0)
            )
    }
}

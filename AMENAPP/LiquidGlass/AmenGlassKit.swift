import SwiftUI

// MARK: - AmenFloatingGlassBackButton
// Floating pill back button for full-screen sheets and media viewers.
// Enforces 44pt minimum tap target; press scale respects Reduce Motion.

struct AmenFloatingGlassBackButton: View {
    let action: () -> Void
    var label: String = "Back"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @GestureState private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minWidth: 44, minHeight: 44)
            .background { pillBackground }
            .shadow(
                color: LiquidGlassTokens.shadowFloating.color,
                radius: LiquidGlassTokens.shadowFloating.radius,
                y: LiquidGlassTokens.shadowFloating.y
            )
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.96 : 1))
            .animation(
                reduceMotion
                    ? .easeOut(duration: LiquidGlassTokens.motionFast)
                    : .spring(response: 0.22, dampingFraction: 0.88),
                value: isPressed
            )
        }
        .buttonStyle(.plain)
        .gesture(DragGesture(minimumDistance: 0).updating($isPressed) { _, s, _ in s = true })
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var pillBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous).fill(Color(.systemBackground))
                .overlay { Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.18), lineWidth: 1) }
        } else {
            Capsule(style: .continuous).fill(LiquidGlassTokens.blurRegular)
                .overlay { Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.44), lineWidth: 0.6) }
        }
    }
}

// MARK: - AmenGlassActionRail
// Horizontal or vertical strip of icon-only action buttons with glass chrome.
// Use for: post quick-actions, media controls, AI panel shortcuts.

struct AmenGlassActionItem: Identifiable {
    let id: String
    let icon: String
    let label: String
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    init(id: String = UUID().uuidString, icon: String, label: String,
         isDestructive: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.id = id; self.icon = icon; self.label = label
        self.isDestructive = isDestructive; self.isDisabled = isDisabled; self.action = action
    }
}

struct AmenGlassActionRail: View {
    let items: [AmenGlassActionItem]
    var axis: Axis = .horizontal
    var spacing: CGFloat = 4

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if axis == .horizontal { HStack(spacing: spacing) { railButtons } }
            else { VStack(spacing: spacing) { railButtons } }
        }
        .padding(axis == .horizontal
            ? EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
            : EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))
        .background { railBackground }
        .shadow(color: LiquidGlassTokens.shadowFloating.color,
                radius: LiquidGlassTokens.shadowFloating.radius,
                y: LiquidGlassTokens.shadowFloating.y)
    }

    @ViewBuilder private var railButtons: some View {
        ForEach(items) { item in
            Button(action: item.action) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(item.isDestructive ? Color.red : AmenTheme.Colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.isDisabled)
            .opacity(item.isDisabled ? 0.38 : 1)
            .accessibilityLabel(item.label)
        }
    }

    @ViewBuilder private var railBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .fill(LiquidGlassTokens.blurElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.34), lineWidth: 0.6)
                }
        }
    }
}

// MARK: - AmenGlassContextMenu
// Wraps SwiftUI Menu with a light haptic on open. iOS 26+ provides glass
// chrome automatically; this adds the Amen haptic feedback layer.

struct AmenGlassContextMenu<Label: View, MenuContent: View>: View {
    @ViewBuilder let label: () -> Label
    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        Menu { menuContent() } label: { label() }
            .simultaneousGesture(TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            })
    }
}

// MARK: - AmenGlassMediaChrome
// Inactivity-fading glass control bar for media playback.
// Controls disappear after `inactivityTimeout`; a tap on the media area restores them.

struct AmenGlassMediaChrome<Controls: View>: View {
    var inactivityTimeout: Double = 3.5
    @ViewBuilder let controls: () -> Controls

    @State private var isVisible = true
    @State private var hideTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear.contentShape(Rectangle()).onTapGesture { showControls() }
            controls()
                .padding(.horizontal, 16).padding(.bottom, 20)
                .background(alignment: .bottom) {
                    if !reduceTransparency {
                        LinearGradient(colors: [.clear, .black.opacity(0.54)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 120).allowsHitTesting(false)
                    }
                }
                .opacity(isVisible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: LiquidGlassTokens.motionNormal), value: isVisible)
        }
        .onAppear { scheduleHide() }
        .onDisappear { hideTask?.cancel() }
    }

    private func showControls() { isVisible = true; scheduleHide() }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(inactivityTimeout))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { isVisible = false } }
        }
    }
}

// MARK: - AmenGlassLoadingSkeleton
// Shimmer skeleton that replaces harsh gray placeholders.
// Match the size and corner radius of the content it stands in for.

struct AmenGlassLoadingSkeleton: View {
    var cornerRadius: CGFloat = LiquidGlassTokens.cornerRadiusMedium
    var height: CGFloat = 60

    @State private var shimmerOffset: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(reduceTransparency ? AnyShapeStyle(Color(.systemFill)) : AnyShapeStyle(LiquidGlassTokens.blurThin))
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(LinearGradient(colors: [.clear, .white.opacity(0.28), .clear],
                                                 startPoint: .leading, endPoint: .trailing))
                            .offset(x: shimmerOffset * geo.size.width)
                            .blendMode(.screen)
                    }
                    .clipped()
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.26), lineWidth: 0.6)
            }
            .frame(height: height)
            .onAppear {
                guard !reduceMotion else { return }
                shimmerOffset = -1
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { shimmerOffset = 2 }
            }
    }
}

// MARK: - AmenMotionProfile
// Semantic motion profile — choose the easing personality for a surface.
// `.action` is the default fast spring; `.gentle` is for slow content reveals.

enum AmenMotionProfile {
    case action   // Snappy spring for interactive controls
    case gentle   // Slow ease for content reveals and onboarding
    case feedback // Quick bounce for confirmation micro-interactions

    func animation() -> Animation {
        switch self {
        case .action:   return .spring(response: 0.30, dampingFraction: 0.82)
        case .gentle:   return .spring(response: 0.55, dampingFraction: 0.88)
        case .feedback: return .spring(response: 0.22, dampingFraction: 0.70)
        }
    }
}

// MARK: - AmenMotionProfile Environment Key
// Passes the active motion profile through the view hierarchy so sheets,
// composers, and overlays all pick up the right easing automatically.

struct AmenMotionProfileKey: EnvironmentKey {
    static let defaultValue: AmenMotionProfile = .action
}

extension EnvironmentValues {
    var amenMotionProfile: AmenMotionProfile {
        get { self[AmenMotionProfileKey.self] }
        set { self[AmenMotionProfileKey.self] = newValue }
    }
}

// MARK: - AmenGlassSmartSheet
// Intent-aware sheet: injects motion profile, applies glass background.
// Prefer over plain `.sheet()` for all Amen surfaces.

struct AmenGlassSmartSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let profile: AmenMotionProfile
    @ViewBuilder let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            sheetContent()
                .environment(\.amenMotionProfile, profile)
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(28)
        }
    }
}

extension View {
    func amenSmartSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        profile: AmenMotionProfile = .action,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(AmenGlassSmartSheet(isPresented: isPresented, profile: profile, sheetContent: content))
    }
}

// MARK: - AmenGlassCapsuleButton (alias)
typealias AmenGlassCapsuleButton = AmenLiquidGlassPillButton

// MARK: - AmenGlassComposerBar
// General-purpose glass composer bar: text input + configurable action buttons.
// NOT the Living Entries composer (see LiquidGlassComposerBar for that).
// Supports pill (collapsed) ↔ full panel (expanded) morph via amenGlassComposerExpansion.

struct AmenGlassComposerAction: Identifiable {
    let id: String
    let icon: String
    let label: String
    let action: () -> Void

    init(id: String = UUID().uuidString, icon: String, label: String, action: @escaping () -> Void) {
        self.id = id; self.icon = icon; self.label = label; self.action = action
    }
}

struct AmenGlassComposerBar: View {
    @Binding var text: String
    @Binding var isExpanded: Bool
    var placeholder: String = "Message..."
    var leadingIcon: String? = nil
    var actions: [AmenGlassComposerAction] = []
    var onSubmit: (String) -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded { expandedContent } else { collapsedPill }
        }
        .padding(12)
        .background { composerBackground }
        .shadow(color: LiquidGlassTokens.shadowFloating.color,
                radius: LiquidGlassTokens.shadowFloating.radius,
                y: LiquidGlassTokens.shadowFloating.y)
        .amenGlassComposerExpansion(isExpanded: isExpanded)
    }

    private var collapsedPill: some View {
        Button {
            withAnimation(expandAnimation) { isExpanded = true; isFocused = true }
        } label: {
            HStack(spacing: 10) {
                if let icon = leadingIcon {
                    Image(systemName: icon).font(.body).foregroundStyle(.secondary)
                }
                Text(placeholder).font(.body).foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: "arrow.up.circle.fill").font(.title3).foregroundStyle(AmenTheme.Colors.textPrimary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open message composer")
    }

    private var expandedContent: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain).font(.body)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1...6).focused($isFocused)
                    .accessibilityLabel("Message text")
                Button {
                    withAnimation(expandAnimation) { isExpanded = false; isFocused = false }
                } label: {
                    Image(systemName: "xmark").font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain).accessibilityLabel("Collapse composer")
            }
            HStack(spacing: 8) {
                ForEach(actions) { a in
                    Button(action: a.action) {
                        Image(systemName: a.icon).font(.body)
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain).accessibilityLabel(a.label)
                }
                Spacer()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                Button { onSubmit(trimmed) } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                        .foregroundStyle(trimmed.isEmpty ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(AmenTheme.Colors.textPrimary))
                }
                .buttonStyle(.plain).disabled(trimmed.isEmpty).accessibilityLabel("Send message")
            }
        }
    }

    @ViewBuilder private var composerBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous).fill(Color(.systemBackground))
                .overlay { Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1) }
        } else {
            Capsule(style: .continuous).fill(LiquidGlassTokens.blurRegular)
                .overlay { Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.50), lineWidth: 0.7) }
        }
    }

    private var expandAnimation: Animation {
        reduceMotion ? .easeOut(duration: LiquidGlassTokens.motionFast)
                     : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82)
    }
}

// MARK: - AmenGlassExpandableCard
// Backward-compatible expandable card (iOS 17+) using standard materials.
// For iOS 26+ glassEffect morphing use GlassExpandableCard from LiquidGlassMotion.
// Staged detail reveal: header is always visible; detail fades in after 100ms.

struct AmenGlassExpandableCard<Header: View, Detail: View>: View {
    @Binding var isExpanded: Bool
    var cornerRadius: CGFloat = LiquidGlassTokens.cornerRadiusMedium
    @ViewBuilder let header: () -> Header
    @ViewBuilder let detail: () -> Detail

    @State private var showDetail = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header().contentShape(Rectangle()).onTapGesture { toggle() }
            if isExpanded && showDetail {
                detail()
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    .padding(.top, 12)
            }
        }
        .padding(16)
        .background { cardBackground }
        .shadow(color: .black.opacity(isExpanded ? 0.10 : 0.04),
                radius: isExpanded ? 18 : 5, y: isExpanded ? 8 : 2)
        .scaleEffect(isExpanded ? 1.01 : 1.0)
        .animation(cardAnimation, value: isExpanded)
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 100))
                    withAnimation(cardAnimation) { showDetail = true }
                }
            } else {
                withAnimation(cardAnimation) { showDetail = false }
            }
        }
    }

    private func toggle() { withAnimation(cardAnimation) { isExpanded.toggle() } }

    private var cardAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.82)
    }

    @ViewBuilder private var cardBackground: some View {
        let r = cornerRadius + (isExpanded ? 4 : 0)
        if reduceTransparency {
            RoundedRectangle(cornerRadius: r, style: .continuous).fill(Color(.systemBackground))
                .overlay { RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1) }
        } else {
            RoundedRectangle(cornerRadius: r, style: .continuous).fill(LiquidGlassTokens.blurRegular)
                .overlay { RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Color.white.opacity(0.38), lineWidth: 0.7) }
        }
    }
}

// MARK: - Background Luminance
// Scheme-based luminance classification driving material tier selection.
// Updates only on appear and color scheme change — never per-frame.

enum AmenBackgroundLuminance { case light, neutral, dark, media }

func amenMaterialFor(_ luminance: AmenBackgroundLuminance) -> Material {
    switch luminance {
    case .dark, .media: return .thinMaterial
    case .light:        return .ultraThinMaterial
    case .neutral:      return LiquidGlassTokens.blurRegular
    }
}

private struct AmenBackgroundLuminanceModifier: ViewModifier {
    @Binding var luminance: AmenBackgroundLuminance
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.onAppear { update() }.onChange(of: colorScheme) { _, _ in update() }
    }

    private func update() { luminance = colorScheme == .dark ? .dark : .light }
}

extension View {
    func amenLuminanceDetect(_ luminance: Binding<AmenBackgroundLuminance>) -> some View {
        modifier(AmenBackgroundLuminanceModifier(luminance: luminance))
    }
}

// MARK: - Liquid Glass Motion System

enum AmenLiquidGlassSurfaceRole: String, Hashable {
    case navigation, feedCard, presenceCluster, prayerCircle, safetyBadge, aiSummary, composer, badge
}

struct AmenMotionSignals {
    var contentDensity: CGFloat = 0.5
    var activeUserCount: Int = 0
    var typingUserCount: Int = 0
    var prayingUserCount: Int = 0
    var viewerCount: Int = 0
    var hasUnsafeContent: Bool = false
    var glassSurfaceCount: Int = 4
}

enum AmenTrustMotionState: String, Hashable, CaseIterable, Identifiable {
    case verified, needsReview, unsafe
    var id: String { rawValue }

    var signals: AmenMotionSignals {
        switch self {
        case .verified:    return AmenMotionSignals(hasUnsafeContent: false)
        case .needsReview: return AmenMotionSignals(hasUnsafeContent: false)
        case .unsafe:      return AmenMotionSignals(hasUnsafeContent: true)
        }
    }
}

struct AmenLiquidGlassSocialMotionContext {
    var contentDensity: CGFloat = 0.5
    var emotionalIntensity: CGFloat = 0.0
    var isActive: Bool = false
    var isSafe: Bool = true
    var isExpanded: Bool = false
}

struct AmenLiquidGlassMorphContainer<Content: View>: View {
    var spacing: CGFloat = 16
    @Namespace private var namespace
    @ViewBuilder let content: (Namespace.ID) -> Content

    var body: some View {
        VStack(spacing: spacing) {
            content(namespace)
        }
    }
}

extension View {
    func amenMotionSignals(_ signals: AmenMotionSignals) -> some View { self }
    func amenRuntimeMotionMonitored() -> some View { self }
    func amenLiquidGlassSocialMotion(_ role: AmenLiquidGlassSurfaceRole, context: AmenLiquidGlassSocialMotionContext) -> some View { self }
    func amenGlassMorphID(_ id: String, namespace: Namespace.ID, role: AmenLiquidGlassSurfaceRole) -> some View { self }
}

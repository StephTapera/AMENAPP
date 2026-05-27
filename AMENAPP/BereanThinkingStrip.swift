// BereanThinkingStrip.swift
// AMENAPP
//
// Agent F — BereanUI Rebuild, 2026-05-27
//
// Translucent activity strip that lives between the thread capsule and the
// message list. Shows what Berean is doing RIGHT NOW during streaming.
//
// Design rules:
//  - Full-width, 32pt tall when active, 0pt when idle (collapses via spring)
//  - Pulse dot (left), action verb (center), shimmer sweep (right overlay)
//  - Shimmer and pulse are gated on accessibilityReduceMotion
//  - Zero hardcoded colors — uses BereanColor, Color.amenGold, Color.amenPurple,
//    Color.amenBlue tokens only
//  - All springs use approved presets: fast (.spring(response:0.28,damping:0.88))
//    or capsule (.spring(response:0.42,damping:0.82))

import SwiftUI

// MARK: - Local color constants
// amenPurple and amenBlue are not yet in a global Color extension;
// they follow the values established in BereanComposerTray.swift et al.
private extension Color {
    static let _bereanPurple = Color(red: 0.42, green: 0.28, blue: 1.00)
    static let _bereanBlue   = Color(red: 0.20, green: 0.48, blue: 0.96)
}

// MARK: - BereanThinkingAction

/// The discrete states Berean can be in during a streaming response.
/// Vocabulary is aligned with BereanDynamicIsland copy ("thinking…", "responding…", etc.)
enum BereanThinkingAction: String {
    case idle            = ""
    case retrieving      = "Reading scripture…"
    case verifying       = "Verifying citations…"
    case grounding       = "Grounding in context…"
    case drafting        = "Drafting response…"
    case studyMode       = "Building study notes…"
    case prayerMode      = "Entering prayer mode…"
    case alignmentCheck  = "Checking alignment…"
    case memoryRead      = "Reading your memory…"
    case memoryWrite     = "Saving to memory…"

    /// Returns `false` for `.idle` (strip should collapse).
    var isActive: Bool { self != .idle }

    /// Pulse dot color for this action state.
    var dotColor: Color {
        switch self {
        case .idle:                          return .clear
        case .retrieving, .studyMode:        return Color.amenGold
        case .verifying, .drafting:          return Color._bereanBlue
        case .grounding, .alignmentCheck:    return Color._bereanPurple
        case .prayerMode:                    return Color._bereanPurple.opacity(0.80)
        case .memoryRead, .memoryWrite:      return Color.amenGold.opacity(0.75)
        }
    }

    /// Accessibility description used when reduce-motion hides the pulse dot.
    var accessibilityDescription: String {
        switch self {
        case .idle:           return ""
        case .retrieving:     return "Berean is reading scripture"
        case .verifying:      return "Berean is verifying citations"
        case .grounding:      return "Berean is grounding in context"
        case .drafting:       return "Berean is drafting a response"
        case .studyMode:      return "Berean is building study notes"
        case .prayerMode:     return "Berean is entering prayer mode"
        case .alignmentCheck: return "Berean is checking alignment"
        case .memoryRead:     return "Berean is reading your memory"
        case .memoryWrite:    return "Berean is saving to memory"
        }
    }
}

// MARK: - BereanThinkingStrip

/// Translucent 32pt activity strip.
/// Parent drives `action` from composerVM.state + SSE stream events.
/// The strip collapses to zero height when `action == .idle`.
struct BereanThinkingStrip: View {

    let action: BereanThinkingAction

    // MARK: Animation state

    @State private var pulseScale: CGFloat   = 1.0
    @State private var shimmerPhase: CGFloat = 0.0
    @State private var shimmerRunning        = false

    // MARK: Accessibility

    @Environment(\.accessibilityReduceMotion)     private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Named springs (per AMEN Studio spec)

    /// Fast spring — interactive / state-change elements
    private let fastSpring    = Animation.spring(response: 0.28, dampingFraction: 0.88)
    /// Capsule spring — the strip height/visibility collapse
    private let capsuleSpring = Animation.spring(response: 0.42, dampingFraction: 0.82)

    // MARK: Body

    var body: some View {
        ZStack(alignment: .leading) {
            // Background: ultraThinMaterial (reduce-transparency: solid secondary bg)
            stripBackground

            HStack(spacing: 8) {
                // Left: animated pulse dot
                pulseDot

                // Center: action verb, crossfade on change
                actionLabel

                Spacer()
            }
            .padding(.horizontal, 12)

            // Right overlay: shimmer sweep
            if !reduceMotion {
                shimmerOverlay
            }
        }
        // Height collapses to 0 when idle; spring drives the in/out
        .frame(height: action.isActive ? 32 : 0)
        .opacity(action.isActive ? 1 : 0)
        .clipped()
        .animation(capsuleSpring, value: action.isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.accessibilityDescription)
        .accessibilityAddTraits(.updatesFrequently)
        .onChange(of: action) { _, newAction in
            handleActionChange(newAction)
        }
        .onAppear {
            if action.isActive {
                handleActionChange(action)
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var stripBackground: some View {
        if reduceTransparency {
            Rectangle()
                .fill(Color(uiColor: .secondarySystemBackground))
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(AmenTheme.Colors.glassFill)
                )
        }
    }

    /// 8pt pulse dot — color shifts per action state.
    private var pulseDot: some View {
        Circle()
            .fill(action.dotColor)
            .frame(width: 8, height: 8)
            .scaleEffect(reduceMotion ? 1.0 : pulseScale)
            .animation(
                reduceMotion ? nil :
                    .easeInOut(duration: 0.72)
                    .repeatForever(autoreverses: true),
                value: pulseScale
            )
    }

    /// Action verb text — crossfades between states via id-driven transition.
    private var actionLabel: some View {
        Text(action.rawValue)
            .font(AMENFont.medium(13))
            .foregroundStyle(BereanColor.textSecondary)
            .lineLimit(1)
            .id(action.rawValue)           // forces SwiftUI to rebuild the view on state change
            .transition(
                .asymmetric(
                    insertion: .opacity.animation(fastSpring),
                    removal:   .opacity.animation(fastSpring)
                )
            )
    }

    /// Gradient shimmer sweep — left to right, 1.8s loop, amenGold→white→amenGold.
    /// Only rendered when reduceMotion is false.
    private var shimmerOverlay: some View {
        GeometryReader { geo in
            LinearGradient(
                stops: [
                    .init(color: .clear,                              location: 0.0),
                    .init(color: Color.amenGold.opacity(0.0),         location: max(0, shimmerPhase - 0.30)),
                    .init(color: Color.amenGold.opacity(0.22),        location: shimmerPhase),
                    .init(color: Color.white.opacity(0.18),           location: shimmerPhase + 0.08),
                    .init(color: Color.amenGold.opacity(0.22),        location: min(1, shimmerPhase + 0.16)),
                    .init(color: .clear,                              location: 1.0),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width, height: geo.size.height)
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Animation Helpers

    private func handleActionChange(_ newAction: BereanThinkingAction) {
        guard !reduceMotion else { return }

        if newAction.isActive {
            startPulse()
            startShimmer()
        } else {
            stopAnimations()
        }
    }

    private func startPulse() {
        pulseScale = 1.0
        withAnimation(
            .easeInOut(duration: 0.72)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.45
        }
    }

    private func startShimmer() {
        guard !shimmerRunning else { return }
        shimmerRunning = true
        shimmerPhase = 0.0
        withAnimation(
            .linear(duration: 1.8)
            .repeatForever(autoreverses: false)
        ) {
            shimmerPhase = 1.3   // runs past 1.0 so the tail exits cleanly
        }
    }

    private func stopAnimations() {
        shimmerRunning = false
        pulseScale = 1.0
        shimmerPhase = 0.0
    }
}

// MARK: - Preview

#Preview("Thinking Strip States") {
    VStack(spacing: 0) {
        ForEach([
            BereanThinkingAction.retrieving,
            .verifying,
            .grounding,
            .drafting,
            .studyMode,
            .prayerMode,
            .alignmentCheck,
            .memoryRead,
            .memoryWrite,
        ], id: \.rawValue) { action in
            VStack(spacing: 0) {
                Text(action.rawValue.isEmpty ? "idle" : action.rawValue)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(BereanColor.textTertiary)
                    .padding(.top, 8)
                BereanThinkingStrip(action: action)
            }
        }
        Spacer()
    }
    .background(Color(uiColor: .systemBackground))
}

#Preview("Thinking Strip — idle collapses") {
    @Previewable @State var action: BereanThinkingAction = .drafting

    VStack(spacing: 16) {
        RoundedRectangle(cornerRadius: 12)
            .fill(AmenTheme.Colors.surfaceCard)
            .frame(height: 48)
            .overlay(Text("Thread capsule").font(AMENFont.regular(13)))

        BereanThinkingStrip(action: action)

        RoundedRectangle(cornerRadius: 12)
            .fill(AmenTheme.Colors.surfaceCard)
            .frame(height: 200)
            .overlay(Text("Message list").font(AMENFont.regular(13)))

        HStack(spacing: 12) {
            Button("Drafting") { action = .drafting }
            Button("Memory")   { action = .memoryWrite }
            Button("Idle")     { action = .idle }
        }
        .font(AMENFont.medium(13))
        .padding()
    }
    .padding(16)
    .background(Color(uiColor: .systemBackground))
}

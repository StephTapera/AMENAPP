// ChurchDiscoveryPulse.swift
// AMENAPP
//
// Premium pulse / signal animation for Find a Church discovery states.
// Communicates location searching, active discovery, and results-found
// moments without any gimmicky or heavy visual effects.
//
// Architecture:
//   DiscoveryPulseState  — enum driving what the animation shows
//   ChurchDiscoveryPulseView  — reusable, stateless animation component
//   FindChurchDiscoveryCard   — glass card wrapper used in FindChurchView
//                              while churchSearchService.isSearching == true

import SwiftUI

// MARK: - Pulse State

/// Drives the visual state of ChurchDiscoveryPulseView.
enum DiscoveryPulseState: Equatable {
    /// Location is being requested or GPS is acquiring a fix.
    case searchingForLocation
    /// Location is known; nearby churches are being fetched.
    case searchingForChurches
    /// Results arrived — play a single confirmation pulse then settle.
    case churchesFound(count: Int)
    /// Location permission is denied or unavailable.
    case locationUnavailable
    /// No active operation; show an ambient resting state.
    case idle

    var statusLabel: String {
        switch self {
        case .searchingForLocation:  return "Finding your location"
        case .searchingForChurches:  return "Locating nearby churches"
        case .churchesFound(let n):  return n == 1 ? "1 church found nearby" : "\(n) churches found nearby"
        case .locationUnavailable:   return "Location unavailable"
        case .idle:                  return ""
        }
    }

    /// Whether the continuous loop animation should be active.
    var isAnimatingLoop: Bool {
        switch self {
        case .searchingForLocation, .searchingForChurches: return true
        default: return false
        }
    }

    /// Accent color per state — within AMEN's minimal palette.
    var accentColor: Color {
        switch self {
        case .searchingForLocation:  return Color(white: 0.35)
        case .searchingForChurches:  return Color(red: 0.18, green: 0.18, blue: 0.55) // deep indigo
        case .churchesFound:         return Color(red: 0.18, green: 0.50, blue: 0.30) // muted green
        case .locationUnavailable:   return Color(white: 0.6)
        case .idle:                  return Color(white: 0.4)
        }
    }

    /// SF Symbol for the center icon per state.
    var centerIcon: String {
        switch self {
        case .searchingForLocation:  return "location.fill"
        case .searchingForChurches:  return "magnifyingglass"
        case .churchesFound:         return "checkmark"
        case .locationUnavailable:   return "location.slash.fill"
        case .idle:                  return "location"
        }
    }
}

// MARK: - Core Pulse Ring

/// A single expanding, fading ring used by ChurchDiscoveryPulseView.
/// Driven externally by an animatable `phase` value in [0, 1].
private struct PulseRing: View {
    /// 0 = ring at center (scale 0.3, opacity 0.5)
    /// 1 = ring fully expanded (scale 1.0, opacity 0.0)
    let phase: CGFloat
    let baseSize: CGFloat
    let color: Color
    let lineWidth: CGFloat

    private var scale: CGFloat    { 0.3 + phase * 0.7 }
    private var opacity: Double   { Double(max(0, 0.5 - phase * 0.5)) }

    var body: some View {
        Circle()
            .stroke(color.opacity(opacity), lineWidth: lineWidth)
            .frame(width: baseSize, height: baseSize)
            .scaleEffect(scale)
            .allowsHitTesting(false)
    }
}

// MARK: - ChurchDiscoveryPulseView

/// Reusable pulse animation component for church discovery states.
///
/// Usage:
/// ```swift
/// ChurchDiscoveryPulseView(state: .searchingForChurches)
///     .frame(width: 160, height: 160)
/// ```
struct ChurchDiscoveryPulseView: View {
    let state: DiscoveryPulseState

    // Animation phases for 3 staggered rings (values in [0, 1])
    @State private var phase0: CGFloat = 0
    @State private var phase1: CGFloat = 0
    @State private var phase2: CGFloat = 0

    // One-shot confirmation pulse when state → .churchesFound
    @State private var confirmationScale: CGFloat = 1.0
    @State private var confirmationOpacity: Double = 0.0

    // Center icon cross-fade
    @State private var iconOpacity: Double = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Ring geometry
    private let ringSize: CGFloat = 130
    private let ringLineWidth: CGFloat = 1.2
    // Stagger offsets — ring 0 leads, ring 2 trails by 0.6s
    private let stagger: [Double] = [0, 0.5, 1.0]
    private let cycleDuration: Double = 2.0

    var body: some View {
        ZStack {
            // Pulse rings (visible during loop states)
            if state.isAnimatingLoop && !reduceMotion {
                PulseRing(phase: phase0, baseSize: ringSize,
                          color: state.accentColor, lineWidth: ringLineWidth)
                PulseRing(phase: phase1, baseSize: ringSize,
                          color: state.accentColor, lineWidth: ringLineWidth)
                PulseRing(phase: phase2, baseSize: ringSize,
                          color: state.accentColor, lineWidth: ringLineWidth)
            }

            // Confirmation burst ring (one-shot on churchesFound)
            if !reduceMotion {
                Circle()
                    .stroke(state.accentColor.opacity(confirmationOpacity),
                            lineWidth: 1.5)
                    .frame(width: ringSize, height: ringSize)
                    .scaleEffect(confirmationScale)
                    .allowsHitTesting(false)
            }

            // Center icon container
            ZStack {
                // Soft glow behind icon
                Circle()
                    .fill(state.accentColor.opacity(0.08))
                    .frame(width: 52, height: 52)

                Circle()
                    .fill(Color.white)
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.black.opacity(0.07), radius: 10, y: 3)

                Image(systemName: state.centerIcon)
                    .font(.system(size: 18, weight: .medium, design: .default))
                    .foregroundStyle(state.accentColor)
                    .opacity(iconOpacity)
            }
        }
        .frame(width: ringSize, height: ringSize)
        .onAppear { startAnimation() }
        .onChange(of: state) { _, newState in handleStateChange(newState) }
    }

    // MARK: Private

    private func startAnimation() {
        guard state.isAnimatingLoop && !reduceMotion else { return }
        animateRings()
    }

    private func animateRings() {
        // Each ring independently loops with a staggered start delay.
        // Completion callbacks reschedule immediately for a gapless loop.
        scheduleRing(index: 0, delay: stagger[0])
        scheduleRing(index: 1, delay: stagger[1])
        scheduleRing(index: 2, delay: stagger[2])
    }

    private func scheduleRing(index: Int, delay: Double) {
        // Only continue looping while state demands it
        guard state.isAnimatingLoop else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard state.isAnimatingLoop else { return }
            withAnimation(.easeInOut(duration: cycleDuration)) {
                setPhase(index: index, value: 1.0)
            }
            // Reset phase immediately after animation so next cycle starts clean
            DispatchQueue.main.asyncAfter(deadline: .now() + cycleDuration) {
                setPhase(index: index, value: 0.0)
                // Reschedule with no additional delay (stagger handled on first launch only)
                scheduleRing(index: index, delay: 0)
            }
        }
    }

    private func setPhase(index: Int, value: CGFloat) {
        switch index {
        case 0: phase0 = value
        case 1: phase1 = value
        case 2: phase2 = value
        default: break
        }
    }

    private func handleStateChange(_ newState: DiscoveryPulseState) {
        // Cross-fade the center icon when state changes
        withAnimation(.easeInOut(duration: 0.18)) { iconOpacity = 0 }
        withAnimation(.easeInOut(duration: 0.18).delay(0.18)) { iconOpacity = 1 }

        switch newState {
        case .churchesFound:
            // Stop loop rings immediately
            withAnimation(.easeOut(duration: 0.3)) {
                phase0 = 0; phase1 = 0; phase2 = 0
            }
            // Fire one confirmation burst ring
            guard !reduceMotion else { return }
            confirmationScale = 0.3
            confirmationOpacity = 0.55
            withAnimation(.easeOut(duration: 1.0)) {
                confirmationScale = 1.05
                confirmationOpacity = 0
            }

        case .searchingForLocation, .searchingForChurches:
            // (Re)start loop — rings may already be running if transitioning
            // between searching states; scheduleRing guards against duplication
            // via the `state.isAnimatingLoop` guard at top of scheduleRing.
            animateRings()

        default:
            // Settle all phases to zero
            withAnimation(.easeOut(duration: 0.4)) {
                phase0 = 0; phase1 = 0; phase2 = 0
            }
        }
    }
}

// MARK: - FindChurchDiscoveryCard

/// Glass status card shown at the top of Find a Church while loading.
/// Replaces the previous skeleton-only FindChurchLoadingView for the
/// initial search state so users see meaningful discovery feedback.
///
/// The skeleton cards still appear below for content shape context.
struct FindChurchDiscoveryCard: View {
    let state: DiscoveryPulseState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Pulse + label hero area
            VStack(spacing: 18) {
                ChurchDiscoveryPulseView(state: state)

                if !state.statusLabel.isEmpty {
                    Text(state.statusLabel)
                        .font(.system(size: 15, weight: .medium, design: .default))
                        .foregroundStyle(Color(white: 0.25))
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .id(state.statusLabel) // forces re-render/fade on text change
                        .animation(.easeInOut(duration: 0.35), value: state.statusLabel)
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 36)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.92))
                .shadow(color: Color.black.opacity(0.04), radius: 24, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.black.opacity(0.04), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

// MARK: - Enhanced FindChurchLoadingView

/// Replaces the old skeleton-only loading view with the pulse hero card
/// at the top plus skeleton cards below for spatial context.
struct FindChurchLoadingView: View {
    let pulseState: DiscoveryPulseState

    // Convenience init keeps call sites that don't pass a state working.
    init(pulseState: DiscoveryPulseState = .searchingForChurches) {
        self.pulseState = pulseState
    }

    @State private var skeletonVisible = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Discovery pulse hero card
                FindChurchDiscoveryCard(state: pulseState)

                // Skeleton cards — fade in slightly after the hero appears
                // so the eye stays on the pulse first
                if skeletonVisible {
                    LazyVStack(spacing: 16) {
                        ForEach(0..<3, id: \.self) { _ in
                            MinimalChurchCardSkeleton()
                        }
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.5).delay(0.4)) {
                skeletonVisible = true
            }
        }
    }
}

// MARK: - Preview

#Preview("Searching for Location") {
    ChurchDiscoveryPulseView(state: .searchingForLocation)
        .frame(width: 160, height: 160)
        .padding(40)
        .background(Color(white: 0.97))
}

#Preview("Searching for Churches") {
    FindChurchDiscoveryCard(state: .searchingForChurches)
        .padding(.vertical, 20)
        .background(Color(white: 0.96))
}

#Preview("Churches Found") {
    FindChurchDiscoveryCard(state: .churchesFound(count: 12))
        .padding(.vertical, 20)
        .background(Color(white: 0.96))
}

#Preview("Location Unavailable") {
    FindChurchDiscoveryCard(state: .locationUnavailable)
        .padding(.vertical, 20)
        .background(Color(white: 0.96))
}

#Preview("Full Loading View") {
    FindChurchLoadingView(pulseState: .searchingForChurches)
        .background(Color(white: 0.96))
}

// AmenSpacesOnboardingView.swift
// AMENAPP — Spaces Onboarding
//
// Cinematic 3-page first-run onboarding for AMEN Spaces.
// Wabi-inspired: minimal → glass orb cluster → iridescent burst + CTA.
//
// Architecture:
//   TabView(.page) — swipe-driven transitions, @State currentPage
//   No Firebase; caller owns completion via onComplete closure.
//   All animations respect @Environment(\.accessibilityReduceMotion).

import SwiftUI

// MARK: - AmenSpacesOnboardingView

struct AmenSpacesOnboardingView: View {

    // MARK: - Public

    var onComplete: () -> Void

    // MARK: - Private state

    @State private var currentPage = 0
    @State private var orbsVisible = false
    @State private var orbsBurst = false

    // Entrance animation state per page 1 element
    @State private var logoVisible = false
    @State private var headlineVisible = false
    @State private var subVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentPage) {
                page1
                    .tag(0)
                page2
                    .tag(1)
                page3
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Page dots — shown on pages 0 and 1 only
            if currentPage < 2 {
                pageDotsAndHint
                    .padding(.bottom, 48)
            }
        }
        .onChange(of: currentPage) { newPage in
            if newPage == 1 {
                triggerOrbEntrance()
            }
            if newPage == 2 {
                triggerOrbBurst()
            }
        }
    }

    // MARK: - Page 1 — "Where your faith community gathers."

    private var page1: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Hero "A" glyph
                Text("A")
                    .font(.system(size: 120, weight: .black))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .opacity(logoVisible ? 1 : 0)
                    .scaleEffect(reduceMotion ? 1 : (logoVisible ? 1 : 0.7))
                    .padding(.bottom, 28)

                // Headline
                Text("AMEN Spaces.")
                    .font(AMENFont.bold(36))
                    .foregroundStyle(Color(.label))
                    .multilineTextAlignment(.center)
                    .opacity(headlineVisible ? 1 : 0)
                    .scaleEffect(reduceMotion ? 1 : (headlineVisible ? 1 : 0.7))
                    .padding(.bottom, 16)

                // Subheadline
                Text("Your church. Your community.\nEverything in one sacred place.")
                    .font(AMENFont.regular(18))
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .opacity(subVisible ? 1 : 0)
                    .scaleEffect(reduceMotion ? 1 : (subVisible ? 1 : 0.7))
                    .padding(.horizontal, 36)

                Spacer()
                Spacer()
            }
        }
        .onAppear { animatePage1() }
    }

    // MARK: - Page 2 — "One sacred place for everything."

    private var page2: some View {
        ZStack {
            // Background: white with radial gold tint
            Color(.systemBackground).ignoresSafeArea()
            RadialGradient(
                colors: [
                    Color(red: 0.83, green: 0.69, blue: 0.22).opacity(0.08),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 280
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Orb cluster — centered ZStack with explicit offsets
                _SpacesOrbCluster(orbsVisible: orbsVisible)
                    .frame(height: 300)
                    .padding(.bottom, 36)

                // Headline
                Text("Prayer. Worship. Sermons.\nCommunity. Notes.")
                    .font(AMENFont.bold(28))
                    .foregroundStyle(Color(.label))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)

                // Subheadline
                Text("Five pillars of church life,\nbeautifully woven together.")
                    .font(AMENFont.regular(16))
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                Spacer()
                Spacer()
            }
        }
        .onAppear { triggerOrbEntrance() }
    }

    // MARK: - Page 3 — "Your church awaits."

    private var page3: some View {
        ZStack {
            // Iridescent full-bleed gradient background
            _SpacesIridescentBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Burst orbs — fly to edges
                _SpacesBurstOrbs(orbsBurst: orbsBurst)
                    .frame(height: 360)

                // Headline
                Text("Your church awaits.")
                    .font(AMENFont.bold(34))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)

                // Subheadline
                Text("Berean AI, Bible Studies, Prayer groups,\nand your entire church family.")
                    .font(AMENFont.regular(16))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 40)

                // Gold CTA button
                Button { onComplete() } label: {
                    Text("Join your Space")
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(red: 0.83, green: 0.69, blue: 0.22))
                                .shadow(
                                    color: Color(red: 0.83, green: 0.69, blue: 0.22).opacity(0.4),
                                    radius: 20,
                                    y: 8
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

                // Skip / already-member link
                Button("I already have a Space") { onComplete() }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.bottom, 52)
            }
        }
        .onAppear { triggerOrbBurst() }
    }

    // MARK: - Page dots + swipe hint

    private var pageDotsAndHint: some View {
        VStack(spacing: 12) {
            // Dot indicators
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(index == currentPage
                              ? AmenTheme.Colors.amenGold
                              : Color.black.opacity(0.15))
                        .frame(width: index == currentPage ? 8 : 6,
                               height: index == currentPage ? 8 : 6)
                        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                }
            }

            // Swipe hint chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.3))
                .modifier(_PulsingOpacityModifier(reduceMotion: reduceMotion))
        }
    }

    // MARK: - Animation triggers

    private func animatePage1() {
        guard !logoVisible else { return }

        if reduceMotion {
            logoVisible = true
            headlineVisible = true
            subVisible = true
            return
        }

        withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2)) {
            logoVisible = true
        }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.5)) {
            headlineVisible = true
        }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.8)) {
            subVisible = true
        }
    }

    private func triggerOrbEntrance() {
        guard !orbsVisible else { return }
        if reduceMotion {
            orbsVisible = true
            return
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) {
            orbsVisible = true
        }
    }

    private func triggerOrbBurst() {
        guard !orbsBurst else { return }
        if reduceMotion {
            orbsBurst = true
            return
        }
        withAnimation(.spring(response: 0.9, dampingFraction: 0.5)) {
            orbsBurst = true
        }
    }
}

// MARK: - _SpacesOrb (private glass orb component)

private struct _SpacesOrb: View {
    let icon: String
    let label: String
    let size: CGFloat
    let accentColor: Color
    var isVisible: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .fill(accentColor.opacity(0.12))
                    }
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 0.8)
                            .blur(radius: 0.2)
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.8)
                    }
                    .shadow(color: accentColor.opacity(0.15), radius: 20, x: 0, y: 8)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)

                Image(systemName: icon)
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundStyle(accentColor)
            }
            .frame(width: size, height: size)

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(.secondaryLabel))
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.4))
    }
}

// MARK: - _SpacesOrbCluster (page 2 — staggered entrance from center)

private struct _SpacesOrbCluster: View {
    let orbsVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct OrbSpec {
        let icon: String
        let label: String
        let size: CGFloat
        let color: Color
        let offset: CGSize
    }

    private let specs: [OrbSpec] = [
        OrbSpec(icon: "hands.raised",    label: "Prayer",    size: 88,
                color: AmenTheme.Colors.amenGold,
                offset: CGSize(width: -80, height: -60)),
        OrbSpec(icon: "music.note",      label: "Worship",   size: 72,
                color: AmenTheme.Colors.amenPurple,
                offset: CGSize(width: 70, height: -90)),
        OrbSpec(icon: "book.closed.fill",label: "Sermons",   size: 96,
                color: Color(red: 0.20, green: 0.50, blue: 0.90),
                offset: CGSize(width: 0, height: 10)),
        OrbSpec(icon: "person.3.fill",   label: "Community", size: 76,
                color: AmenTheme.Colors.amenGold,
                offset: CGSize(width: -90, height: 80)),
        OrbSpec(icon: "note.text",       label: "Notes",     size: 68,
                color: AmenTheme.Colors.amenPurple,
                offset: CGSize(width: 85, height: 60)),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(specs.enumerated()), id: \.element.label) { index, spec in
                _SpacesOrb(
                    icon: spec.icon,
                    label: spec.label,
                    size: spec.size,
                    accentColor: spec.color,
                    isVisible: orbsVisible
                )
                .offset(spec.offset)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.2)
                        : .spring(response: 0.7, dampingFraction: 0.6)
                              .delay(Double(index) * 0.12),
                    value: orbsVisible
                )
            }
        }
    }
}

// MARK: - _SpacesBurstOrbs (page 3 — fly to edges)

private struct _SpacesBurstOrbs: View {
    let orbsBurst: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct BurstSpec {
        let icon: String
        let label: String
        let size: CGFloat
        let color: Color
        let burstOffset: CGSize
        let rotation: Double
    }

    private let specs: [BurstSpec] = [
        BurstSpec(icon: "hands.raised",     label: "Prayer",    size: 88,
                  color: AmenTheme.Colors.amenGold,
                  burstOffset: CGSize(width: -150, height: -140), rotation: -8),
        BurstSpec(icon: "music.note",       label: "Worship",   size: 72,
                  color: AmenTheme.Colors.amenPurple,
                  burstOffset: CGSize(width: 130, height: -160), rotation: 6),
        BurstSpec(icon: "book.closed.fill", label: "Sermons",   size: 96,
                  color: Color(red: 0.20, green: 0.50, blue: 0.90),
                  burstOffset: CGSize(width: 0, height: -60), rotation: 3),
        BurstSpec(icon: "person.3.fill",    label: "Community", size: 76,
                  color: AmenTheme.Colors.amenGold,
                  burstOffset: CGSize(width: -170, height: 100), rotation: -5),
        BurstSpec(icon: "note.text",        label: "Notes",     size: 68,
                  color: AmenTheme.Colors.amenPurple,
                  burstOffset: CGSize(width: 155, height: 90), rotation: 7),
        BurstSpec(icon: "brain",            label: "Berean AI", size: 72,
                  color: AmenTheme.Colors.amenGold,
                  burstOffset: CGSize(width: 100, height: -110), rotation: -4),
        BurstSpec(icon: "calendar",         label: "Events",    size: 68,
                  color: Color(red: 0.20, green: 0.50, blue: 0.90),
                  burstOffset: CGSize(width: -110, height: 140), rotation: 5),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(specs.enumerated()), id: \.element.label) { index, spec in
                _SpacesOrb(
                    icon: spec.icon,
                    label: spec.label,
                    size: spec.size,
                    accentColor: spec.color,
                    isVisible: orbsBurst
                )
                .rotationEffect(.degrees(orbsBurst ? spec.rotation : 0))
                .offset(orbsBurst ? spec.burstOffset : .zero)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.2)
                        : .spring(response: 0.9, dampingFraction: 0.55)
                              .delay(Double(index) * 0.08),
                    value: orbsBurst
                )
            }
        }
        .clipped()
    }
}

// MARK: - _SpacesIridescentBackground (page 3 full-bleed hero)

private struct _SpacesIridescentBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.05, blue: 0.18),
                    Color(red: 0.25, green: 0.10, blue: 0.45),
                    Color(red: 0.52, green: 0.30, blue: 0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Gold shimmer blob — top-left
            Circle()
                .fill(Color(red: 0.83, green: 0.69, blue: 0.22).opacity(0.35))
                .blur(radius: 80)
                .frame(width: 300, height: 300)
                .offset(x: -80, y: -120)

            // Purple shimmer blob — bottom-right
            Circle()
                .fill(Color(red: 0.52, green: 0.18, blue: 0.80).opacity(0.40))
                .blur(radius: 100)
                .frame(width: 350, height: 350)
                .offset(x: 100, y: 80)
        }
    }
}

// MARK: - _PulsingOpacityModifier (swipe hint chevron)

private struct _PulsingOpacityModifier: ViewModifier {
    let reduceMotion: Bool
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(pulsing ? 0.15 : 0.5)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: 1.1)
                    .repeatForever(autoreverses: true)
                ) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Preview

#Preview("Spaces Onboarding") {
    AmenSpacesOnboardingView(onComplete: {})
}

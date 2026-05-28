// GetReadyView.swift
// AMENAPP
//
// Stable Sunday prep experience with a church-aware hero and journey-based sections.

import SwiftUI
import CoreLocation

private struct GetReadyScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

fileprivate struct GetReadyHeroMotion {
    var progress: CGFloat = 0
    var velocity: CGFloat = 0

    var overlayScale: CGFloat { 1 - (progress * 0.02) }
    var overlayOffset: CGFloat { -(progress * 6) }
    var glassOpacityBoost: Double { Double(progress) * 0.12 + Double(min(velocity, 1)) * 0.08 }
    var readingMode: Bool { velocity < 0.12 }
}

struct GetReadyView: View {
    @StateObject var vm: GetReadyViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var heroMotion = GetReadyHeroMotion()
    @State private var lastScrollSample: CGFloat = 0
    @State private var lastScrollDate = Date()

    private let photoHeight: CGFloat = 288
    private let contentOverlap: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroSection(topInset: geo.safeAreaInsets.top)
                        contentBody
                            .padding(.top, -contentOverlap)
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: GetReadyScrollOffsetKey.self,
                                value: max(0, -proxy.frame(in: .named("getReadyScroll")).minY)
                            )
                        }
                    )
                }
                .coordinateSpace(name: "getReadyScroll")
                .ignoresSafeArea(edges: .top)
                .onPreferenceChange(GetReadyScrollOffsetKey.self, perform: updateHeroMotion)

                closeButton(topInset: geo.safeAreaInsets.top)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .onAppear { vm.onAppear() }
            .sheet(isPresented: $vm.showQuietModeOnboarding) {
                QuietModeOnboardingView { pref in
                    vm.onQuietModeOnboardingCompleted(pref)
                }
            }
        }
    }

    private func updateHeroMotion(_ offset: CGFloat) {
        let capped = min(max(offset / 150, 0), 1)
        let now = Date()
        let deltaTime = max(now.timeIntervalSince(lastScrollDate), 0.016)
        let velocity = min(abs(offset - lastScrollSample) / CGFloat(deltaTime * 800), 1)

        lastScrollSample = offset
        lastScrollDate = now

        // Smooth small ranges only. The photo itself stays static; only the glass overlay reacts.
        heroMotion.progress = (heroMotion.progress * 0.74) + (capped * 0.26)
        heroMotion.velocity = (heroMotion.velocity * 0.7) + (velocity * 0.3)
    }

    private func heroSection(topInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            GetReadyHeroPhotoLayer(plan: vm.plan)
                .frame(height: photoHeight)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, Color(.systemGroupedBackground).opacity(0.7), Color(.systemGroupedBackground)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 128)
                }

            GetReadyGlassBanner(plan: vm.plan, motion: heroMotion)
                .padding(.horizontal, 16)
                .padding(.top, max(topInset, 16) + 10)
                .scaleEffect(heroMotion.overlayScale, anchor: .top)
                .offset(y: heroMotion.overlayOffset)
                .shadow(color: .black.opacity(0.16 + heroMotion.glassOpacityBoost), radius: 28, y: 10)
        }
        .frame(height: photoHeight)
        .clipped()
    }

    private var contentBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Already handled")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text("\(vm.autoHandledItems.filter(\.isReady).count) ready")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                handledPillRow
            }
            .padding(.horizontal, 16)
            .padding(.top, contentOverlap + 18)
            .padding(.bottom, 16)

            Divider().padding(.horizontal, 16)

            VStack(spacing: 10) {
                ForEach($vm.sections) { $section in
                    GetReadyJourneySectionCard(section: $section, vm: vm)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 56)
        }
        .background(contentBackground)
    }

    private var handledPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.autoHandledItems.filter(\.isReady)) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(.systemGreen).opacity(0.88))
                            .accessibilityHidden(true)
                        Text(item.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(.systemGreen).opacity(0.2), lineWidth: 0.5))
                }
            }
        }
    }

    private var contentBackground: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 34,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 34,
            style: .continuous
        )
        .fill(.regularMaterial)
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 34,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 34,
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(0.34), lineWidth: 0.8)
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private func closeButton(topInset: CGFloat) -> some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.top, max(topInset, 18) + 4)
        .accessibilityLabel("Dismiss")
    }
}

// MARK: - Hero

private struct GetReadyHeroPhotoLayer: View {
    let plan: GetReadyPlan

    var body: some View {
        ZStack {
            if let url = plan.heroImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        GetReadyHeroFallback(plan: plan)
                    }
                }
            } else {
                GetReadyHeroFallback(plan: plan)
            }
        }
        .overlay(heroTintOverlay)
    }

    private var heroTintOverlay: some View {
        LinearGradient(
            colors: overlayColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var overlayColors: [Color] {
        switch plan.hero.luminance {
        case .bright:
            return [.black.opacity(0.18), .clear, plan.hero.accent.opacity(0.18)]
        case .balanced:
            return [.black.opacity(0.12), .clear, plan.hero.accent.opacity(0.16)]
        case .dark:
            return [.black.opacity(0.05), .white.opacity(0.06), plan.hero.accent.opacity(0.12)]
        }
    }
}

struct GetReadyGlassBanner: View {
    let plan: GetReadyPlan
    fileprivate let motion: GetReadyHeroMotion

    private var foreground: Color {
        plan.hero.prefersDarkText ? Color.black.opacity(0.92) : Color.white.opacity(0.96)
    }

    private var secondaryForeground: Color {
        plan.hero.prefersDarkText ? Color.black.opacity(0.62) : Color.white.opacity(0.8)
    }

    private var chipBackground: Color {
        plan.hero.prefersDarkText ? Color.white.opacity(0.4) : Color.white.opacity(0.14)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("Get Ready")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryForeground)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Spacer()
                Text(motion.readingMode ? "You're going" : "Sunday plan")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(chipBackground, in: Capsule())
                    .overlay(Capsule().strokeBorder(foreground.opacity(0.12), lineWidth: 0.5))
            }

            HStack(alignment: .center, spacing: 8) {
                Text("You're going")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(foreground)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(secondaryForeground)
                    .accessibilityHidden(true)
            }
            .padding(.top, 4)

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryForeground)
                    .accessibilityHidden(true)
                Text("\(plan.serviceTimeString) · \(plan.churchName)")
                    .font(.subheadline)
                    .foregroundStyle(secondaryForeground)
                    .lineLimit(1)
            }
            .padding(.top, 6)

            HStack(alignment: .firstTextBaseline) {
                if let shortAddress = plan.shortAddress {
                    Text(shortAddress)
                        .font(.caption)
                        .foregroundStyle(secondaryForeground)
                }
                Spacer()
                if plan.focus.isArmed {
                    Text("Focus \(plan.focus.confidenceScore)%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(secondaryForeground)
                }
            }
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let minutes = plan.route.minutesUntilDeparture {
                        glassChip(minutes < 60 ? "Leave in \(minutes)m" : "Leave by \(plan.route.leaveByLabel)", icon: "mappin")
                    }
                    if plan.isFirstVisit {
                        glassChip("First visit", icon: "star.fill")
                    }
                    if plan.hasKidsCheckIn {
                        glassChip("Kids ready", icon: "figure.and.child.holdinghands")
                    }
                    if plan.bringPhysicalBible {
                        glassChip("Bring Bible", icon: "book.closed.fill")
                    }
                    if plan.notePreference == .churchNotes {
                        glassChip("Notes ready", icon: "pencil.and.list.clipboard")
                    }
                    if plan.focus.isArmed {
                        glassChip("Focus mode ready", icon: "moon.stars.fill")
                    }
                }
            }
            .padding(.top, 12)
        }
        .padding(16)
        .background(bannerBackground)
    }

    private func glassChip(_ label: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(secondaryForeground)
                .accessibilityHidden(true)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(chipBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(foreground.opacity(0.14), lineWidth: 0.5))
    }

    private var bannerBackground: some View {
        let tintOpacity = plan.hero.overlayBaseOpacity + motion.glassOpacityBoost
        return RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(plan.hero.prefersDarkText ? 0.42 : 0.16),
                                plan.hero.accent.opacity(tintOpacity),
                                Color.white.opacity(plan.hero.prefersDarkText ? 0.18 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(plan.hero.prefersDarkText ? 0.36 : 0.28), lineWidth: 0.8)
            )
            .mask(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.96), .white.opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
    }
}

// MARK: - Sections

struct GetReadyJourneySectionCard: View {
    @Binding var section: JourneySection
    @ObservedObject var vm: GetReadyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.32, bounce: 0.08)) {
                    section.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 28, height: 28)
                        Image(systemName: section.moment.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)

                    Text(section.moment.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(section.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if section.isExpanded {
                Divider().padding(.horizontal, 16)
                VStack(spacing: 0) {
                    ForEach(Array(section.cards.enumerated()), id: \.element.id) { idx, card in
                        cardView(card)
                        if idx < section.cards.count - 1 {
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func cardView(_ card: JourneyCard) -> some View {
        switch card {
        case let .departure(route, _, churchName, _):
            GetReadyDepartureCard(route: route, churchName: churchName, onOpenMaps: vm.openMaps)
        case let .quietMode(state):
            GetReadyQuietModeCard(state: state, vm: vm)
        case let .coffee(summary):
            GetReadyInfoRow(icon: "cup.and.heat.waves.fill", tint: Color(.systemBrown), title: "Coffee stop", subtitle: summary)
        case let .music(enabled, summary):
            GetReadyInfoRow(icon: "music.note.list", tint: Color(red: 0.18, green: 0.34, blue: 0.74), title: "Worship playlist", subtitle: enabled ? summary : "Set a music preference when you want worship prep.")
        case let .bereanSelah(prompt):
            GetReadyBereanCard(prompt: prompt, passagePreview: vm.plan.berean.passagePreview, prayerPrompt: vm.plan.berean.prayerPrompt)
        case let .scripturePreview(passage):
            GetReadyInfoRow(icon: "book.pages", tint: Color(.systemBrown), title: "This week's passage", subtitle: passage ?? "Preview through Berean")
        case let .memoryVerse(text, reference):
            if text != nil || reference != nil {
                GetReadyMemoryVerseCard(text: text, reference: reference)
            }
        case let .kidsCheckIn(kids, hasIntegration, reminder):
            GetReadyKidsCard(kids: kids, hasIntegration: hasIntegration, reminder: reminder)
        case let .physicalBible(enabled, summary):
            if enabled {
                GetReadyBibleReminderRow(summary: summary)
            }
        case let .churchNotesEntry(churchName, summary):
            GetReadyChurchNotesCard(churchName: churchName, summary: summary)
        case let .firstVisitGuide(churchName, parking, entrance, dressHint):
            GetReadyFirstVisitCard(churchName: churchName, parking: parking, entrance: entrance, dressHint: dressHint)
        case .reflection:
            GetReadyInfoRow(icon: "sparkles", tint: Color(.systemIndigo), title: "Berean reflection", subtitle: "What stuck with you today?")
        case let .fellowship(summary):
            GetReadyInfoRow(icon: "fork.knife", tint: Color(.secondaryLabel), title: "After service", subtitle: summary)
        case .convertNotes:
            GetReadyInfoRow(icon: "arrow.triangle.2.circlepath", tint: Color(.systemGreen), title: "Turn notes into reflection", subtitle: "Convert key points into prayer, testimony, or follow-up.")
        }
    }
}

struct GetReadyDepartureCard: View {
    let route: GetReadyRouteRecommendation
    let churchName: String
    let onOpenMaps: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.28, bounce: 0.08)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(route.headline)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(route.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 10) {
                    if let weather = route.weatherSummary {
                        detailRow(weather, icon: "cloud.rain.fill", tint: Color(.systemBlue))
                    }
                    if let parking = route.parkingNote {
                        detailRow(parking, icon: "car.fill", tint: Color(.systemOrange))
                    }
                    detailRow("\(route.travelMinutes) min drive to \(churchName)", icon: "location.fill", tint: Color(.systemGreen))

                    Button(action: onOpenMaps) {
                        HStack(spacing: 10) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(.systemBlue))
                                .accessibilityHidden(true)
                            Text("Open in Maps")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color(.systemBlue))
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func detailRow(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct GetReadyQuietModeCard: View {
    let state: QuietModeCardState
    @ObservedObject var vm: GetReadyViewModel

    var body: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .notConfigured:
            Button { vm.openQuietModeOnboarding() } label: {
                cardRow(icon: "moon.stars.fill", tint: Color(.systemIndigo), title: "Set up Church Focus", subtitle: "Reduce distractions during service", badge: "Set up")
            }
            .buttonStyle(.plain)
        case let .ready(pref):
            cardRow(icon: pref.icon, tint: Color(.systemIndigo), title: "Church Focus: \(pref.title)", subtitle: pref.subtitle)
        case let .suggesting(name):
            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(.systemIndigo))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Looks like you're at \(name)")
                        .font(.subheadline.weight(.semibold))
                    Text("Enable quiet mode until service ends?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 6) {
                    Button("Enable") { vm.confirmQuietMode() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemIndigo), in: Capsule())
                    Button("Not now") { vm.dismissQuietModeSuggestion() }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        case .active:
            cardRow(icon: "moon.stars.fill", tint: Color(.systemIndigo), title: "Church Focus is active", subtitle: "Distractions are reduced until service ends.", badge: "Live")
        }
    }

    private func cardRow(icon: String, tint: Color, title: String, subtitle: String, badge: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.1), in: Capsule())
            }
        }
        .padding(16)
    }
}

struct GetReadyBereanCard: View {
    let prompt: String
    let passagePreview: String?
    let prayerPrompt: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.28, bounce: 0.08)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "text.book.closed.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(.systemIndigo).opacity(0.84))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("5-minute Selah")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(prompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 10) {
                    detailRow("Begin Selah", "play.circle.fill", Color(.systemIndigo))
                    if let passagePreview {
                        detailRow(passagePreview, "book.pages", Color(.systemBrown))
                    }
                    detailRow("Prayer prompt ready", "hands.sparkles.fill", Color(.systemOrange))
                    Text(prayerPrompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func detailRow(_ text: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

struct GetReadyKidsCard: View {
    let kids: [GetReadyFamilyState.Child]
    let hasIntegration: Bool
    let reminder: String?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.28, bounce: 0.08)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(.systemBlue))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Kids Check-In")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(kids.map(\.name).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 10) {
                    detailRow(hasIntegration ? "Open digital check-in" : "Open Family Card", "qrcode.viewfinder", Color(.systemBlue))
                    if let reminder {
                        detailRow(reminder, "cross.case.fill", Color(.systemRed))
                    }
                    ForEach(kids) { kid in
                        if let allergy = kid.allergySummary {
                            detailRow("\(kid.name): \(allergy)", "exclamationmark.triangle.fill", Color(.systemOrange))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func detailRow(_ text: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

struct GetReadyInfoRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(16)
    }
}

struct GetReadyChurchNotesCard: View {
    let churchName: String
    let summary: String

    var body: some View {
        Button {} label: {
            HStack(spacing: 12) {
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(.systemIndigo))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Church Notes ready")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(summary.isEmpty ? "Template preloaded for \(churchName)" : summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Text("Open")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.systemIndigo))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemIndigo).opacity(0.1), in: Capsule())
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }
}

struct GetReadyMemoryVerseCard: View {
    let text: String?
    let reference: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "text.quote")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Memory verse")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            if let text {
                Text(text)
                    .font(.subheadline)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reference {
                Text(reference)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}

struct GetReadyBibleReminderRow: View {
    let summary: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color(.systemBrown))
                .accessibilityHidden(true)
            Text(summary)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.systemGreen))
                .accessibilityHidden(true)
        }
        .padding(16)
    }
}

struct GetReadyFirstVisitCard: View {
    let churchName: String
    let parking: String?
    let entrance: String?
    let dressHint: String?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.28, bounce: 0.08)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(.systemYellow))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("First visit tips")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("What to expect at \(churchName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 8) {
                    if let parking {
                        tipRow(parking, "car.fill")
                    }
                    if let entrance {
                        tipRow(entrance, "door.right.hand.open")
                    }
                    if let dressHint {
                        tipRow(dressHint, "person.crop.square")
                    }
                    tipRow("Guest team can usually help near the main lobby", "person.badge.key.fill")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func tipRow(_ label: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

// MARK: - Fallback

struct GetReadyHeroFallback: View {
    let plan: GetReadyPlan

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    plan.hero.accent.opacity(0.62),
                    Color(.systemGray5),
                    Color(.systemGray6)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 220, height: 220)
                .offset(x: 110, y: -90)

            VStack(spacing: 10) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .accessibilityHidden(true)
                Text(plan.churchName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                if let shortAddress = plan.shortAddress {
                    Text(shortAddress)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.82))
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Get Ready — First Visit, Family") {
    GetReadyView(vm: GetReadyViewModel(church: Church(
        name: "Elevation Church",
        denomination: "Baptist",
        address: "3200 Wilkinson Blvd, Charlotte, NC",
        distance: "7 mi",
        distanceValue: 7,
        serviceTime: "Sunday 9:30 AM",
        phone: "",
        coordinate: .init(latitude: 35.245, longitude: -80.876),
        website: "elevationchurch.org"
    )))
}
#endif

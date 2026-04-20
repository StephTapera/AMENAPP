// CrisisSupportView.swift
// AMENAPP
//
// Crisis Help & Support screen.
// Visual source of truth: preserves current design exactly — rich burgundy/wine/plum hero,
// serif headline, soft white lower sheet, red emergency card, triage pills, expandable sections.
// State-aware, locale-aware, privacy-first. Adapts layout by crisis state without redesigning.
//

import SwiftUI

// MARK: - Main View

struct CrisisSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CrisisSupportViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let heroHeight: CGFloat = 290
    private let sheetOverlap: CGFloat = 62

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top

            ZStack(alignment: .top) {
                // Background fill (visible below sheet)
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                // ── Hero (behind lower sheet) ────────────────────────────
                heroSection(safeAreaTop: safeTop)
                    .frame(height: heroHeight + safeTop)
                    .frame(maxWidth: .infinity, alignment: .top)

                // ── Lower scrollable sheet ───────────────────────────────
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        // Invisible spacer that reveals the hero underneath
                        Color.clear
                            .frame(height: heroHeight + safeTop - sheetOverlap)

                        // Sheet content panel
                        VStack(spacing: 16) {
                            triageSelector
                            privacyCard
                                .transition(.opacity.animation(CrisisAnimationTokens.privacySettle))
                            adaptiveSections
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 22)
                        .padding(.bottom, 120)
                        .frame(maxWidth: .infinity)
                        .background(
                            Color(UIColor.systemGroupedBackground)
                                .clipShape(
                                    UnevenRoundedRectangle(
                                        topLeadingRadius: 34,
                                        bottomLeadingRadius: 0,
                                        bottomTrailingRadius: 0,
                                        topTrailingRadius: 34
                                    )
                                )
                        )
                    }
                }
                .ignoresSafeArea(edges: .top)

                // ── Back button (always on top) ──────────────────────────
                VStack {
                    HStack {
                        glassBackButton
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, safeTop + 14)
                    Spacer()
                }

                // ── Follow-up prompt ─────────────────────────────────────
                if viewModel.showFollowUpPrompt {
                    VStack {
                        Spacer()
                        followUpBanner
                            .padding(.horizontal, 20)
                            .padding(.bottom, 100)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarHidden(true)
        .onDisappear { viewModel.endSession() }
    }

    // MARK: - Hero Section

    private func heroSection(safeAreaTop: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient background
            heroGradient

            // Radial specular highlights
            GeometryReader { g in
                ZStack {
                    RadialGradient(
                        colors: [.white.opacity(0.22), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: g.size.width * 0.65
                    )
                    RadialGradient(
                        colors: [.white.opacity(0.10), .clear],
                        center: .bottomTrailing,
                        startRadius: 0,
                        endRadius: g.size.width * 0.50
                    )
                }
            }

            // Text content
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: safeAreaTop + 68) // below back button

                // "CRISIS HELP & SUPPORT" label
                Text("CRISIS HELP & SUPPORT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(3.0)
                    .foregroundStyle(.white.opacity(0.66))
                    .padding(.bottom, 14)

                // Serif headline — animates on state change
                VStack(alignment: .leading, spacing: -6) {
                    ForEach(viewModel.crisisState.heroTitleLines, id: \.self) { line in
                        Text(line)
                            .font(.custom("Georgia", size: 52))
                            .foregroundStyle(.white)
                            .lineSpacing(0)
                    }
                }
                .animation(CrisisAnimationTokens.heroTransition, value: viewModel.crisisState)
                .padding(.bottom, 12)

                // Body text
                Text(viewModel.crisisState.heroBody)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(CrisisAnimationTokens.heroTransition, value: viewModel.crisisState)

                Spacer().frame(height: 28)
            }
            .padding(.horizontal, 26)
        }
    }

    private var heroGradient: some View {
        let colors = viewModel.crisisState.heroGradientColors
        return LinearGradient(
            colors: colors.map { Color(red: $0.r, green: $0.g, blue: $0.b) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .animation(CrisisAnimationTokens.heroTransition, value: viewModel.crisisState)
    }

    // MARK: - Glass Back Button

    private var glassBackButton: some View {
        Button(action: { dismiss() }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .stroke(.white.opacity(0.22), lineWidth: 0.7)
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    // MARK: - Triage Selector

    private var triageSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HOW ARE YOU RIGHT NOW?")
                .font(.system(size: 10, weight: .bold))
                .tracking(2.2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(CrisisState.allCases, id: \.self) { state in
                    CrisisTriagePill(
                        label: state.shortLabel,
                        isActive: viewModel.crisisState == state,
                        isDanger: state == .inDanger,
                        onTap: { viewModel.selectState(state) }
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.06), radius: 16, y: 5)
        )
    }

    // MARK: - Privacy Card

    private var privacyCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("This space is private")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Not visible to followers, your church, or community. Berean supports — but never replaces — emergency or professional care.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        )
    }

    // MARK: - Adaptive Sections

    @ViewBuilder
    private var adaptiveSections: some View {
        // Emergency card — always first in "In danger" mode, reduced in others
        if viewModel.crisisState == .inDanger {
            emergencyCard
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                    removal: .opacity
                ))
        } else {
            compactEmergencyPill
        }

        // Ordered expandable sections
        ForEach(viewModel.orderedSections) { section in
            CrisisExpandableSection(
                section: section,
                isOpen: viewModel.isSectionOpen(section),
                onToggle: { viewModel.toggleSection(section) }
            ) {
                sectionContent(for: section)
            }
        }
        .animation(CrisisAnimationTokens.cardReorder, value: viewModel.crisisState)
    }

    // MARK: - Emergency Card (In Danger mode)

    private var emergencyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Emergency support first")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                    Text("Get help now")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                ZStack {
                    Circle().fill(.white.opacity(0.15))
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
            }

            VStack(spacing: 10) {
                ForEach(viewModel.adaptedResources.prefix(3)) { resource in
                    Button {
                        if resource.channel == .call {
                            viewModel.callNumber(resource.target)
                        } else {
                            viewModel.openTextSupport(resource.target)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resource.title)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(resource.subtitle)
                                    .font(.system(size: 12))
                                    .opacity(0.72)
                            }
                            Spacer()
                            Text(resource.channel == .call ? "Call" : "Text")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(.white.opacity(0.20)))
                        }
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(.white.opacity(0.14), lineWidth: 0.6)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.78, green: 0.10, blue: 0.10))
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.12), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 0.8)
            }
        )
        .shadow(color: Color(red: 0.78, green: 0.10, blue: 0.10).opacity(0.28), radius: 24, y: 10)
    }

    // MARK: - Compact Emergency Pill (non-danger modes)

    private var compactEmergencyPill: some View {
        Button {
            viewModel.callNumber(viewModel.localeResources.crisisHotlineNumber)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.78, green: 0.10, blue: 0.10))
                Text(viewModel.localeResources.crisisHotlineLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.78, green: 0.10, blue: 0.10))
                Spacer()
                Text("Call")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(red: 0.78, green: 0.10, blue: 0.10)))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 1.00, green: 0.94, blue: 0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(red: 0.78, green: 0.10, blue: 0.10).opacity(0.15), lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Content Router

    @ViewBuilder
    private func sectionContent(for section: CrisisSection) -> some View {
        switch section {
        case .immediateHelp:
            VStack(spacing: 10) {
                ForEach(viewModel.adaptedResources) { resource in
                    CrisisResourceRow(resource: resource) {
                        if resource.channel == .call {
                            viewModel.callNumber(resource.target.isEmpty
                                                 ? viewModel.localeResources.crisisHotlineNumber
                                                 : resource.target)
                        } else if resource.channel == .text {
                            viewModel.openTextSupport(resource.target)
                        }
                    }
                }
            }

        case .groundingTools:
            CrisisGroundingModule(viewModel: viewModel)

        case .bereanReflect:
            CrisisBereanModule(viewModel: viewModel)

        case .safetyPlan:
            VStack(spacing: 16) {
                CrisisSafetyPlanModule(viewModel: viewModel)
                Divider()
                CrisisTrustedContactModule(viewModel: viewModel)
            }

        case .faithAndPrayer:
            faithAndPrayerContent

        case .recoverySupport:
            recoverySupportContent
        }
    }

    // MARK: - Faith & Prayer Content

    private var faithAndPrayerContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            faithRow(title: "Psalm 46:1", body: "\"God is our refuge and strength, an ever-present help in trouble.\"")
            faithRow(title: "Short Prayer", body: "Lord, I am here. I am struggling. I need you. Guide me to safety and surround me with peace.")
            faithRow(title: "Connect with Your Church", body: "Your church leader is here for you — but only when you choose to reach out. Go to Find a Church to connect.")
        }
    }

    private func faithRow(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .italic(title.hasPrefix("Psalm") || title == "Short Prayer")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 1.00, green: 0.96, blue: 0.90))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(red: 0.70, green: 0.42, blue: 0.05).opacity(0.10), lineWidth: 0.6)
                )
        )
    }

    // MARK: - Recovery Support Content

    private var recoverySupportContent: some View {
        VStack(spacing: 10) {
            recoveryRow(icon: "calendar", title: "Check-In Tomorrow", sub: "Gentle follow-up — your choice, no pressure.")
            recoveryRow(icon: "figure.walk", title: "Physical Care", sub: "Rest, water, small movement. Your body holds stress.")
            recoveryRow(icon: "note.text", title: "Church Notes", sub: "Resume your spiritual journal whenever feels right.")
        }
    }

    private func recoveryRow(icon: String, title: String, sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.80, green: 0.20, blue: 0.40))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(red: 1.00, green: 0.94, blue: 0.96)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Follow-Up Banner

    private var followUpBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You don't have to respond. Just wanted you to know support is here.")
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineSpacing(3)

            HStack(spacing: 10) {
                Button {
                    viewModel.optInToFollowUp()
                } label: {
                    Text("Yes, check in with me")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(CrisisAnimationTokens.bereanReveal) {
                        viewModel.showFollowUpPrompt = false
                    }
                } label: {
                    Text("No thanks")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color(UIColor.secondarySystemGroupedBackground))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.88), .white.opacity(0.70)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
            }
        )
        .shadow(color: .black.opacity(0.12), radius: 30, y: 12)
    }
}

// MARK: - Triage Pill

private struct CrisisTriagePill: View {
    let label: String
    let isActive: Bool
    let isDanger: Bool
    let onTap: () -> Void
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? .white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(pillBackground)
                .scaleEffect(isPressed ? 0.96 : 1.0)
                .animation(
                    reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.72),
                    value: isPressed
                )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var pillBackground: some View {
        if isActive {
            Capsule()
                .fill(isDanger
                      ? Color(red: 0.78, green: 0.10, blue: 0.10)
                      : Color.black)
                .shadow(
                    color: (isDanger
                            ? Color(red: 0.78, green: 0.10, blue: 0.10)
                            : Color.black).opacity(0.22),
                    radius: 10, y: 4
                )
        } else {
            Capsule()
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        }
    }
}

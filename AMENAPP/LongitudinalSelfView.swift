//
//  LongitudinalSelfView.swift
//  AMENAPP
//
//  "My Journey" — full-screen longitudinal spiritual growth view.
//  Surfaces AI-detected growth arcs, year-by-year timeline,
//  milestones, and the user's current season chapter.
//

import SwiftUI

struct LongitudinalSelfView: View {

    @StateObject private var vm = LongitudinalViewModel()
    @State private var showOnboarding = false

    // MARK: - Pulse animation state (analyzing screen)
    @State private var sparkleScale: CGFloat = 1.0

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // ── Background ───────────────────────────────────────────
                journeyBackground

                // Content router
                Group {
                    if vm.isLoading {
                        loadingState
                    } else if !vm.hasProfile && !vm.isAnalyzing {
                        emptyState
                    } else if vm.isAnalyzing {
                        analyzingState
                    } else {
                        journeyContent
                    }
                }
            }
            .navigationTitle("My Journey")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if vm.hasProfile && !vm.isAnalyzing {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task { await vm.requestAIAnalysis() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.systemScaled(15, weight: .medium))
                                .foregroundStyle(.purple)
                        }
                        .disabled(vm.isAnalyzing || vm.isLoading)
                    }
                }
            }
        }
        .task { await vm.load() }
        .fullScreenCover(isPresented: $showOnboarding) {
            LongitudinalOnboardingView(vm: vm)
        }
        .onAppear {
            if !vm.hasSeenOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: vm.hasSeenOnboarding) { _, newValue in
            if !newValue { showOnboarding = true }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var journeyBackground: some View {
        if vm.isAnalyzing || !vm.hasProfile {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.07, blue: 0.20),
                    Color(red: 0.06, green: 0.06, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .overlay(
                RadialGradient(
                    colors: [Color(red: 0.76, green: 0.36, blue: 0.95).opacity(0.20), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 320
                )
                .ignoresSafeArea()
            )
        } else {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.purple)
                .scaleEffect(1.3)
            Text("Loading your journey…")
                .font(AMENFont.regular(15))
                .foregroundColor(.white.opacity(0.70))
        }
    }

    // MARK: - Empty / Permission State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.76, green: 0.36, blue: 0.95).opacity(0.18))
                        .frame(width: 92, height: 92)
                    Image(systemName: "figure.walk.motion")
                        .font(.systemScaled(44, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color(red: 0.80, green: 0.40, blue: 0.98))
                }

                VStack(spacing: 10) {
                    Text("Your Spiritual Journey")
                        .font(AMENFont.bold(24))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("AMEN remembers where you've been. Your posts, prayers, and testimonies paint a picture of how God is shaping you.")
                        .font(AMENFont.regular(14))
                        .foregroundColor(.white.opacity(0.70))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
            .glassEffect(GlassEffectStyle.regular.tint(.white.opacity(0.15)).interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            )
            Spacer()

            Button {
                Task { await vm.grantPermissionAndAnalyze() }
            } label: {
                Text("Begin")
                    .font(AMENFont.semiBold(16))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.78, green: 0.33, blue: 0.97), Color(red: 0.40, green: 0.24, blue: 0.82)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
            .buttonStyle(JourneyPressButtonStyle())
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Analyzing State

    private var analyzingState: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.systemScaled(52, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.purple)
                .scaleEffect(sparkleScale)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.1)
                        .repeatForever(autoreverses: true)
                    ) {
                        sparkleScale = 1.15
                    }
                }
                .onDisappear {
                    sparkleScale = 1.0
                }

            VStack(spacing: 8) {
                Text("Analyzing your journey…")
                    .font(AMENFont.semiBold(20))
                    .foregroundColor(.white)

                Text("This may take a moment")
                    .font(AMENFont.regular(14))
                    .foregroundColor(.white.opacity(0.70))
            }
        }
    }

    // MARK: - Full Journey Content

    private var journeyContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                heroCard
                growthArcsSection
                thisDateSection
                timelineSection
                milestonesSection
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Hero Card (Current Season)

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            // Glass + purple tint background
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.purple.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.purple.opacity(0.18), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 16) {
                // Header row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR CURRENT SEASON")
                            .font(AMENFont.medium(11))
                            .foregroundStyle(Color.purple.opacity(0.70))
                            .kerning(0.6)

                        Text(vm.profile.currentChapter)
                            .font(AMENFont.bold(24))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "book.pages.fill")
                        .font(.systemScaled(28, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.purple.opacity(0.55))
                        .padding(.top, 2)
                }

                Divider()

                // Sharing toggle row
                HStack {
                    Image(systemName: vm.profile.isSharedPublicly ? "globe" : "lock.fill")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)

                    Text(vm.profile.isSharedPublicly ? "Shared" : "Visible to me only")
                        .font(AMENFont.medium(13))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { vm.profile.isSharedPublicly },
                        set: { _ in Task { await vm.togglePublicSharing() } }
                    ))
                    .labelsHidden()
                    .tint(Color.purple)
                }
            }
            .padding(20)
        }
        .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
    }

    // MARK: - Growth Arcs Section

    private var growthArcsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Your Transformations",
                subtitle: "AI-detected shifts in your journey"
            )

            if vm.profile.growthArcs.isEmpty {
                subtlePlaceholder(text: "Your arcs will appear as you post")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(vm.profile.growthArcs) { arc in
                            GrowthArcCardView(arc: arc)
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - This Day Section

    private var thisDateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "This Day in Your Journey", subtitle: nil)

            if let post = vm.thisDayPost {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.systemScaled(22, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.purple)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("ON THIS DAY, YOU WROTE…")
                            .font(AMENFont.medium(11))
                            .foregroundStyle(.secondary)
                            .kerning(0.5)

                        Text("\u{201C}\(post)\u{201D}")
                            .font(AMENFont.regular(14))
                            .italic()
                            .foregroundStyle(.primary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                        )
                )
                .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
            } else {
                subtlePlaceholder(text: "Check back after you've posted for a few months")
            }
        }
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Your Timeline", subtitle: nil)

            let sorted = vm.profile.topicEvolution.sorted { $0.year > $1.year }

            if sorted.isEmpty {
                subtlePlaceholder(text: "Your timeline will fill in over time")
            } else {
                VStack(spacing: 10) {
                    ForEach(sorted) { snapshot in
                        JourneyTimelineCardView(snapshot: snapshot)
                    }
                }
            }
        }
    }

    // MARK: - Milestones Section

    @ViewBuilder
    private var milestonesSection: some View {
        if !vm.profile.milestones.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "Milestones", subtitle: nil)

                VStack(spacing: 0) {
                    ForEach(Array(vm.profile.milestones.enumerated()), id: \.element.id) { index, milestone in
                        MilestoneRowView(milestone: milestone)

                        if index < vm.profile.milestones.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                        )
                )
                .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
            }
        }
    }

    // MARK: - Sub-components

    private func sectionHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AMENFont.semiBold(17))
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func subtlePlaceholder(text: String) -> some View {
        HStack {
            Text(text)
                .font(AMENFont.regular(14))
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
        )
    }
}

// MARK: - Press Button Style

private struct JourneyPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.70), value: configuration.isPressed)
    }
}

// MARK: - Milestone Row

private struct MilestoneRowView: View {

    let milestone: JourneyMilestone

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Icon badge
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: milestone.sfSymbol)
                    .font(.systemScaled(15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.title)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let date = milestone.date {
                    Text(Self.dateFormatter.string(from: date))
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("My Journey") {
    LongitudinalSelfView()
}
#endif

//
//  MentalHealthDetailView.swift
//  AMENAPP
//
//  Support Hub — Mental Health & Wellness
//  Three trust layers: Crisis / Professional / Wellness & Spiritual
//  Adaptive surface: mood-aware verse, Berean Care mode, smart tool ordering,
//  rhythm context, local insight (on-device only), groups intake.
//

import SwiftUI

// MARK: - Mental Health Detail View

struct MentalHealthDetailView: View {
    @State private var selectedTab: WellnessTab = .tools
    @State private var appeared = false
    @Environment(\.dismiss) private var dismiss

    // Wellness adaptive surface state
    @State private var selectedMood: WellnessMood = .other
    @State private var careChoice: WellnessCareChoice? = nil
    @ObservedObject private var insightEngine = WellnessLocalInsightEngine.shared
    @State private var intakeNeed: GroupsIntakeNeed = .grief
    @State private var intakeFormat: GroupsIntakeFormat = .inPerson
    @State private var intakePacing: GroupsIntakePacing = .lowPressure
    @State private var forAFriendExpanded = false
    @State private var showBereanCareSheet = false
    @State private var showSilenceSheet = false
    @State private var showPsalmSheet = false

    enum WellnessTab: String, CaseIterable {
        case tools    = "Tools"
        case counsel  = "Counseling"
        case groups   = "Groups"
        case faith    = "Faith"
        case crisis   = "Crisis"
    }

    // Parchment design tokens
    private let parchment     = Color(red: 0.97, green: 0.95, blue: 0.91)
    private let ink           = Color(red: 0.14, green: 0.12, blue: 0.10)
    private let inkSecondary  = Color(red: 0.42, green: 0.38, blue: 0.34)
    private let tealAccent    = Color(red: 0.12, green: 0.52, blue: 0.50)
    private let crisisRed     = Color(red: 0.82, green: 0.14, blue: 0.16)

    var body: some View {
        ZStack(alignment: .top) {
            parchment.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Full-bleed immersive hero — extends into status bar area
                    heroSection

                    // Pinned "Need help now?" crisis safety card
                    needHelpNowCard
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .opacity(appeared ? 1 : 0)

                    // Promoted "For a Friend" expandable surface
                    promotedForAFriendCard
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .opacity(appeared ? 1 : 0)

                    // Tab switcher
                    tabSwitcher
                        .padding(.top, 24)
                        .opacity(appeared ? 1 : 0)

                    // Tab content
                    tabContent
                        .padding(.top, 20)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)

                    // Footer guardrail — only on wellness tabs
                    if selectedTab == .tools || selectedTab == .faith {
                        wellnessFooterGuardrail
                            .padding(.horizontal, 20)
                            .padding(.top, 28)
                    }

                    Spacer(minLength: 60)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.06)) {
                appeared = true
            }
        }
        .sheet(isPresented: $showBereanCareSheet) {
            BereanAIAssistantView(
                seedMessage: selectedMood.config.careOpeningLine
            )
        }
        .sheet(isPresented: $showSilenceSheet) {
            SilenceOverlayView(
                verse: selectedMood.config.quote,
                reference: selectedMood.config.verse
            )
        }
        .sheet(isPresented: $showPsalmSheet) {
            PsalmFocusView(mood: selectedMood)
        }
    }

    // MARK: Hero

    // Wellness-unique palette — deep teal/forest, not used elsewhere in the app
    private let wellnessDark    = Color(red: 0.06, green: 0.18, blue: 0.20)   // deep ocean teal
    private let wellnessMid     = Color(red: 0.10, green: 0.32, blue: 0.30)   // forest teal
    private let wellnessAccent  = Color(red: 0.22, green: 0.58, blue: 0.52)   // mid teal
    private let wellnessSage    = Color(red: 0.52, green: 0.72, blue: 0.56)   // sage green
    private let wellnessLight   = Color.white.opacity(0.92)
    private let wellnessSub     = Color.white.opacity(0.60)

    private var heroSection: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                // Base — deep teal gradient
                LinearGradient(
                    colors: [wellnessDark, wellnessMid],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Sage bloom from bottom-right
                RadialGradient(
                    colors: [wellnessSage.opacity(0.25), Color.clear],
                    center: UnitPoint(x: 0.85, y: 0.90),
                    startRadius: 10,
                    endRadius: 260
                )

                // Teal accent — top-left
                RadialGradient(
                    colors: [wellnessAccent.opacity(0.30), Color.clear],
                    center: UnitPoint(x: 0.10, y: 0.10),
                    startRadius: 0,
                    endRadius: 220
                )

                // Subtle horizontal editorial lines
                VStack(spacing: 28) {
                    ForEach(0..<6, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.03))
                            .frame(height: 1)
                    }
                }
                .frame(maxWidth: .infinity)

                // Content
                VStack(alignment: .leading, spacing: 0) {
                    // Dismiss button
                    HStack {
                        Button { dismiss() } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "xmark")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(wellnessLight)
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, 56)
                    .padding(.bottom, 18)

                    Spacer()

                    // Eyebrow
                    Text("WELLNESS & MENTAL HEALTH")
                        .font(.systemScaled(9, weight: .semibold))
                        .kerning(2.5)
                        .foregroundStyle(wellnessSub)
                        .padding(.bottom, 10)

                    // Large serif headline
                    Text("Mind,\nBody & Soul")
                        .font(.custom("Georgia", size: 38))
                        .fontWeight(.regular)
                        .foregroundStyle(wellnessLight)
                        .lineSpacing(4)
                        .padding(.bottom, 10)

                    // Subtitle
                    Text("Faith-based care at every level of need.")
                        .font(.systemScaled(14, weight: .regular))
                        .foregroundStyle(wellnessSub)
                        .padding(.bottom, 28)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .ignoresSafeArea(edges: .top)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Pinned Crisis Safety Card

    private var needHelpNowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("NEED HELP NOW?")
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(.white)
                    .kerning(0.5)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(crisisRed)

            // Quick-dial rows
            VStack(spacing: 0) {
                CrisisQuickDialRow(
                    icon: "phone.fill",
                    label: "988 Suicide & Crisis Lifeline",
                    action: "Call or Text 988",
                    color: crisisRed,
                    urlString: "tel:988"
                )

                Divider().padding(.leading, 56)

                CrisisQuickDialRow(
                    icon: "message.fill",
                    label: "Crisis Text Line",
                    action: "Text HOME to 741741",
                    color: Color(red: 0.82, green: 0.40, blue: 0.10),
                    urlString: "sms:741741&body=HOME"
                )

                Divider().padding(.leading, 56)

                CrisisQuickDialRow(
                    icon: "cross.case.fill",
                    label: "Emergency Services",
                    action: "Call 911",
                    color: Color(red: 0.14, green: 0.38, blue: 0.72),
                    urlString: "tel:911"
                )
            }
            .background(Color(red: 0.99, green: 0.97, blue: 0.97))

            // For a friend row
            Button {
                selectedTab = .crisis
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.fill.questionmark")
                        .font(.systemScaled(14))
                        .foregroundStyle(crisisRed)
                    Text("Helping someone else? See the \"For a Friend\" guide")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(ink)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(inkSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(red: 1.0, green: 0.95, blue: 0.95))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(crisisRed.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: crisisRed.opacity(0.10), radius: 12, y: 4)
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: - Promoted For a Friend Surface

    private var promotedForAFriendCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.80))) {
                    forAFriendExpanded.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color(red: 0.72, green: 0.22, blue: 0.22).opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.fill.questionmark")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(Color(red: 0.72, green: 0.22, blue: 0.22))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("For a Friend")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(ink)
                        Text("What to say, what not to say, when to call.")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(inkSecondary)
                    }
                    Spacer()
                    Image(systemName: forAFriendExpanded ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(inkSecondary)
                }
                .padding(14)
            }
            .buttonStyle(PlainButtonStyle())

            if forAFriendExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Divider().padding(.horizontal, 14)

                    ForAFriendGuidanceRow(
                        icon: "checkmark.circle.fill",
                        color: Color(red: 0.12, green: 0.52, blue: 0.38),
                        title: "What helps",
                        content: "\"I'm here with you.\" Sit in silence if needed. Ask \"Are you thinking about suicide?\" — it doesn't plant the idea, it opens the door."
                    )

                    ForAFriendGuidanceRow(
                        icon: "xmark.circle.fill",
                        color: Color(red: 0.72, green: 0.22, blue: 0.22),
                        title: "What doesn't help",
                        content: "\"You just need to pray more.\" \"Others have it worse.\" \"God won't give you more than you can handle.\" These dismiss the real weight."
                    )

                    ForAFriendGuidanceRow(
                        icon: "exclamationmark.triangle.fill",
                        color: Color(red: 0.82, green: 0.40, blue: 0.10),
                        title: "If risk feels immediate",
                        content: "Call 988 together. Stay with them. Remove access to means if safe to do so. Don't leave them alone."
                    )

                    ForAFriendGuidanceRow(
                        icon: "heart.fill",
                        color: Color(red: 0.48, green: 0.22, blue: 0.72),
                        title: "Your limits",
                        content: "You are not their therapist. Caring deeply doesn't mean carrying everything. 988 and trained counselors exist so you don't have to do this alone."
                    )

                    // Scripture anchor
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle()
                            .fill(Color(red: 0.48, green: 0.22, blue: 0.72))
                            .frame(width: 2)
                            .cornerRadius(1)
                        Text("\"Carry each other's burdens, and in this way you will fulfill the law of Christ.\" — Galatians 6:2")
                            .font(.custom("Georgia", size: 13))
                            .italic()
                            .foregroundStyle(inkSecondary)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)

                    // Call 988 action button
                    Button {
                        if let url = URL(string: "tel:988") {
                            UIApplication.shared.open(url)
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.systemScaled(13, weight: .semibold))
                            Text("Call 988 with them")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(crisisRed))
                    }
                    .buttonStyle(SquishButtonStyle())
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
        .background(glassCardBackground(cornerRadius: 16))
        .animation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.80)), value: forAFriendExpanded)
    }

    // MARK: Tab Switcher

    private var tabSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(WellnessTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.78))) {
                            selectedTab = tab
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 5) {
                                if tab == .crisis {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.systemScaled(11, weight: .semibold))
                                        .foregroundStyle(selectedTab == tab ? crisisRed : inkSecondary)
                                }
                                Text(tab.rawValue)
                                    .font(.custom(selectedTab == tab ? "OpenSans-SemiBold" : "OpenSans-Regular", size: 14))
                                    .foregroundStyle(selectedTab == tab ? (tab == .crisis ? crisisRed : ink) : inkSecondary)
                            }
                            .padding(.horizontal, 4)

                            Rectangle()
                                .fill(selectedTab == tab ? (tab == .crisis ? crisisRed : tealAccent) : Color.clear)
                                .frame(height: 2)
                                .cornerRadius(1)
                        }
                    }
                    .frame(minWidth: 70)
                    .buttonStyle(SquishButtonStyle())
                }
            }
            .padding(.horizontal, 20)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(inkSecondary.opacity(0.12))
                .frame(height: 1)
        }
    }

    // MARK: Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .tools:    wellnessToolsGrid
        case .counsel:  counselingList
        case .groups:   supportGroupsList
        case .faith:    faithResourcesList
        case .crisis:   crisisDetailTab
        }
    }

    // MARK: Tools Tab — Adaptive Surface

    private var wellnessToolsGrid: some View {
        VStack(spacing: 0) {
            // 1. Mood check-in
            moodCheckInCard
                .padding(.horizontal, 20)

            // 2. Adaptive verse
            adaptiveVerseCard
                .padding(.horizontal, 20)
                .padding(.top, 16)

            // 3. Berean Care mode card
            bereanCareModeCard
                .padding(.horizontal, 20)
                .padding(.top, 16)

            // 4. Smart tool grid — reordered by mood + time of day
            let smartTools = WellnessToolRegistry.ranked(mood: selectedMood, rhythm: WellnessRhythmContext.current)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                ForEach(smartTools) { tool in
                    SmartWellnessToolCard(
                        tool: tool,
                        parchment: parchment,
                        ink: ink,
                        inkSecondary: inkSecondary
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // 5. Rhythm context
            rhythmContextCard
                .padding(.horizontal, 20)
                .padding(.top, 16)

            // 6. Local insight (on-device only)
            if insightEngine.isEnabled {
                localInsightCard
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            // 7. Berean bridge
            bereanWellnessBridge
                .padding(.horizontal, 20)
                .padding(.top, 20)
        }
    }

    // MARK: - Mood Check-In Card

    private var moodCheckInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How are you right now?")
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WellnessMood.allCases) { mood in
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.75))) {
                                selectedMood = mood
                                careChoice = nil
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(mood.rawValue)
                                .font(.custom(selectedMood == mood ? "OpenSans-SemiBold" : "OpenSans-Regular", size: 13))
                                .foregroundStyle(selectedMood == mood ? .white : ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedMood == mood ? tealAccent : Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.07))
                                )
                        }
                        .buttonStyle(SquishButtonStyle())
                        .accessibilityLabel("Mood: \(mood.rawValue)\(selectedMood == mood ? ", selected" : "")")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(glassCardBackground(cornerRadius: 16))
    }

    // MARK: - Adaptive Verse Card

    private var adaptiveVerseCard: some View {
        let config = selectedMood.config
        return HStack(alignment: .top, spacing: 14) {
            Rectangle()
                .fill(tealAccent)
                .frame(width: 3)
                .cornerRadius(2)

            VStack(alignment: .leading, spacing: 6) {
                Text("\"\(config.quote)\"")
                    .font(.custom("Georgia", size: 15))
                    .fontWeight(.regular)
                    .foregroundStyle(ink)
                    .italic()
                    .lineSpacing(4)

                Text("— \(config.verse)")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(inkSecondary)
            }
        }
        .padding(16)
        .background(glassCardBackground(cornerRadius: 16))
        .animation(Motion.adaptive(.easeOut(duration: 0.30)), value: selectedMood)
    }

    // MARK: - Berean Care Mode Card

    private var bereanCareModeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(tealAccent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(tealAccent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Berean Care")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(ink)
                    Text(selectedMood.config.careOpeningLine)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(inkSecondary)
                        .lineSpacing(3)
                        .lineLimit(2)
                }
            }

            // 4 care choices
            HStack(spacing: 8) {
                ForEach(WellnessCareChoice.allCases, id: \.self) { choice in
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.80))) {
                            careChoice = choice
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        // Route to action
                        switch choice {
                        case .talk:
                            showBereanCareSheet = true
                        case .sitInSilence:
                            showSilenceSheet = true
                        case .showPsalm:
                            showPsalmSheet = true
                        case .findSupport:
                            withAnimation(Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.78))) {
                                selectedTab = .counsel
                            }
                        }
                    } label: {
                        Text(choice.rawValue)
                            .font(.custom(careChoice == choice ? "OpenSans-SemiBold" : "OpenSans-Regular", size: 12))
                            .foregroundStyle(careChoice == choice ? .white : ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(careChoice == choice ? tealAccent : Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.07))
                            )
                    }
                    .buttonStyle(SquishButtonStyle())
                    .accessibilityLabel(choice.rawValue)
                }
            }

            // Never-replaces guardrail
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.systemScaled(11))
                    .foregroundStyle(inkSecondary)
                Text("Berean Care does not replace professional mental health care or crisis support.")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(inkSecondary)
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .background(glassCardBackground(cornerRadius: 16))
        .animation(Motion.adaptive(.easeOut(duration: 0.25)), value: selectedMood)
    }

    // MARK: - Rhythm Context Card

    private var rhythmContextCard: some View {
        let rhythm = WellnessRhythmContext.current
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tealAccent.opacity(0.10))
                    .frame(width: 32, height: 32)
                Image(systemName: rhythmIcon(rhythm))
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(tealAccent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(rhythm.rawValue)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(ink)
                Text(rhythm.contextNote)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(inkSecondary)
                    .lineSpacing(3)
            }
        }
        .padding(14)
        .background(glassCardBackground(cornerRadius: 14))
    }

    private func rhythmIcon(_ rhythm: WellnessRhythmContext) -> String {
        switch rhythm {
        case .morning:   return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .night:     return "moon.stars.fill"
        case .sunday:    return "cross.fill"
        case .lent:      return "leaf.fill"
        }
    }

    // MARK: - Local Insight Card (on-device only, never uploaded)

    private var localInsightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(tealAccent)
                Text("On-device only · Never uploaded")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(tealAccent)
                Spacer()
                Toggle("", isOn: $insightEngine.isEnabled)
                    .labelsHidden()
                    .scaleEffect(0.78)
                    .tint(tealAccent)
            }

            Text(insightEngine.currentInsight)
                .font(.custom("Georgia", size: 14))
                .italic()
                .foregroundStyle(inkSecondary)
                .lineSpacing(4)
        }
        .padding(14)
        .background(glassCardBackground(cornerRadius: 14))
    }

    // MARK: - Glass Card Background Helper

    private func glassCardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), Color.white.opacity(0.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.60), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    // MARK: Counseling Tab — Differentiated Trust Tiers

    private var counselingList: some View {
        VStack(spacing: 0) {
            // Tier 1 — Licensed therapy
            counselingTierHeader(
                icon: "person.fill.checkmark",
                title: "Licensed Therapy",
                subtitle: "Credentialed clinicians — insurance accepted",
                color: Color(red: 0.22, green: 0.42, blue: 0.72)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            VStack(spacing: 14) {
                ForEach(MentalHealthResource.counselingResources.filter { !$0.isFree }) { resource in
                    EditorialResourceCard(resource: resource, ink: ink, inkSecondary: inkSecondary, parchment: parchment)
                }
            }
            .padding(.horizontal, 20)

            // Tier 2 — Pastoral (free)
            counselingTierHeader(
                icon: "cross.fill",
                title: "Pastoral Consultation",
                subtitle: "Faith-based counseling · Often free",
                color: Color(red: 0.48, green: 0.22, blue: 0.72)
            )
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 12)

            VStack(spacing: 14) {
                ForEach(MentalHealthResource.counselingResources.filter { $0.isFree }) { resource in
                    EditorialResourceCard(resource: resource, ink: ink, inkSecondary: inkSecondary, parchment: parchment)
                }
            }
            .padding(.horizontal, 20)

            // Tier 3 — Local finder
            counselingTierHeader(
                icon: "location.magnifyingglass",
                title: "Find Local Care",
                subtitle: "Search by specialty, insurance & faith",
                color: Color(red: 0.22, green: 0.48, blue: 0.42)
            )
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 12)

            specialtyFinderCard
                .padding(.horizontal, 20)

            counselingGuardrailNote
                .padding(.horizontal, 20)
                .padding(.top, 20)
        }
    }

    @ViewBuilder
    private func counselingTierHeader(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.systemScaled(18, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(ink)
                Text(subtitle)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(inkSecondary)
            }
            Spacer()
        }
    }

    // MARK: Groups Tab — Intake First

    private var supportGroupsList: some View {
        VStack(spacing: 0) {
            trustLayerHeader(
                icon: "person.3.fill",
                title: "Peer & Community Support",
                subtitle: "Groups where you are not alone",
                color: Color(red: 0.12, green: 0.52, blue: 0.38)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Intake card
            groupsIntakeCard
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            // Match result
            intakeMatchCard
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            // Divider to full directory
            HStack(spacing: 10) {
                Rectangle()
                    .fill(inkSecondary.opacity(0.15))
                    .frame(height: 1)
                Text("All Groups")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(inkSecondary)
                    .kerning(0.4)
                Rectangle()
                    .fill(inkSecondary.opacity(0.15))
                    .frame(height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            VStack(spacing: 14) {
                ForEach(MentalHealthResource.groupResources) { resource in
                    EditorialResourceCard(resource: resource, ink: ink, inkSecondary: inkSecondary, parchment: parchment)
                }
            }
            .padding(.horizontal, 20)

            peerSupportGuardrailNote
                .padding(.horizontal, 20)
                .padding(.top, 20)
        }
    }

    // MARK: - Groups Intake Card

    private var groupsIntakeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Find the right group for you")
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(ink)

            // Question 1 — What are you navigating?
            VStack(alignment: .leading, spacing: 8) {
                Text("What are you navigating?")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(inkSecondary)

                intakePillRow(
                    cases: GroupsIntakeNeed.allCases,
                    selected: intakeNeed,
                    label: { $0.rawValue },
                    onSelect: { intakeNeed = $0 }
                )
            }

            // Question 2 — Format preference
            VStack(alignment: .leading, spacing: 8) {
                Text("Format preference?")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(inkSecondary)

                intakePillRow(
                    cases: GroupsIntakeFormat.allCases,
                    selected: intakeFormat,
                    label: { $0.rawValue },
                    onSelect: { intakeFormat = $0 }
                )
            }

            // Question 3 — Pacing
            VStack(alignment: .leading, spacing: 8) {
                Text("How do you like to engage?")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(inkSecondary)

                intakePillRow(
                    cases: GroupsIntakePacing.allCases,
                    selected: intakePacing,
                    label: { $0.rawValue },
                    onSelect: { intakePacing = $0 }
                )
            }
        }
        .padding(16)
        .background(glassCardBackground(cornerRadius: 16))
    }

    private func intakePillRow<T: Hashable>(
        cases: [T],
        selected: T,
        label: @escaping (T) -> String,
        onSelect: @escaping (T) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cases, id: \.self) { item in
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.80))) {
                            onSelect(item)
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(label(item))
                            .font(.custom(selected == item ? "OpenSans-SemiBold" : "OpenSans-Regular", size: 12))
                            .foregroundStyle(selected == item ? .white : ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(selected == item ? Color(red: 0.12, green: 0.52, blue: 0.38) : Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.07))
                            )
                    }
                    .buttonStyle(SquishButtonStyle())
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var intakeMatchCard: some View {
        let match = GroupsIntakeResult.match(need: intakeNeed, format: intakeFormat, pacing: intakePacing)
        return Button {
            if let url = URL(string: match.url) {
                UIApplication.shared.open(url)
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(red: 0.12, green: 0.52, blue: 0.38).opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.systemScaled(18, weight: .medium))
                        .foregroundStyle(Color(red: 0.12, green: 0.52, blue: 0.38))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Matched: \(match.groupName)")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(ink)
                        Text("Free")
                            .font(.custom("OpenSans-SemiBold", size: 10))
                            .foregroundStyle(Color(red: 0.12, green: 0.52, blue: 0.38))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color(red: 0.12, green: 0.52, blue: 0.38).opacity(0.12)))
                    }
                    Text(match.description)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(inkSecondary)
                        .lineSpacing(3)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(inkSecondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.93, green: 0.97, blue: 0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(red: 0.12, green: 0.52, blue: 0.38).opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(SquishButtonStyle())
        .animation(Motion.adaptive(.easeOut(duration: 0.25)), value: intakeNeed)
        .animation(Motion.adaptive(.easeOut(duration: 0.25)), value: intakeFormat)
        .animation(Motion.adaptive(.easeOut(duration: 0.25)), value: intakePacing)
    }

    // MARK: Faith Tab — Contemplative Practices First

    private var faithResourcesList: some View {
        VStack(spacing: 0) {
            trustLayerHeader(
                icon: "cross.fill",
                title: "Wellness & Spiritual Support",
                subtitle: "Prayer, scripture & meditation",
                color: Color(red: 0.48, green: 0.22, blue: 0.72)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Contemplative practices (gated by flag — default OFF, show if enabled)
            if AMENFeatureFlags.shared.wellnessContemplativePracticesEnabled {
                contemplativePracticesSection
                    .padding(.bottom, 20)
            }

            // Faith orgs — NAMI FaithNet + Mental Health Grace Alliance
            VStack(spacing: 14) {
                ForEach(MentalHealthResource.faithOrgs) { resource in
                    EditorialResourceCard(resource: resource, ink: ink, inkSecondary: inkSecondary, parchment: parchment)
                }
            }
            .padding(.horizontal, 20)

            // Section divider
            HStack(spacing: 10) {
                Rectangle()
                    .fill(inkSecondary.opacity(0.15))
                    .frame(height: 1)
                Text("Apps & Devotionals")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(inkSecondary)
                    .kerning(0.4)
                Rectangle()
                    .fill(inkSecondary.opacity(0.15))
                    .frame(height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 4)

            VStack(spacing: 14) {
                ForEach(MentalHealthResource.faithResources) { resource in
                    EditorialResourceCard(resource: resource, ink: ink, inkSecondary: inkSecondary, parchment: parchment)
                }
            }
            .padding(.horizontal, 20)

            bereanWellnessBridge
                .padding(.horizontal, 20)
                .padding(.top, 20)
        }
    }

    private var contemplativePracticesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(inkSecondary.opacity(0.15))
                    .frame(height: 1)
                Text("Contemplative Practices")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(inkSecondary)
                    .kerning(0.4)
                Rectangle()
                    .fill(inkSecondary.opacity(0.15))
                    .frame(height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                ContemplativePracticeCard(
                    icon: "moon.stars.fill",
                    title: "Examen",
                    subtitle: "Review the day with God",
                    accent: Color(red: 0.28, green: 0.38, blue: 0.62)
                )
                ContemplativePracticeCard(
                    icon: "book.fill",
                    title: "Lectio Divina",
                    subtitle: "Sacred reading, slow and open",
                    accent: Color(red: 0.72, green: 0.46, blue: 0.22)
                )
                ContemplativePracticeCard(
                    icon: "circle.dotted",
                    title: "Centering Prayer",
                    subtitle: "20 minutes, one word, open hands",
                    accent: Color(red: 0.48, green: 0.22, blue: 0.72)
                )
                ContemplativePracticeCard(
                    icon: "moon.fill",
                    title: "Compline",
                    subtitle: "Night prayer before rest",
                    accent: Color(red: 0.22, green: 0.38, blue: 0.52)
                )
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Crisis Tab (dedicated, expanded)

    private var crisisDetailTab: some View {
        VStack(spacing: 0) {
            // Trust layer header — red
            trustLayerHeader(
                icon: "exclamationmark.triangle.fill",
                title: "Crisis & Immediate Help",
                subtitle: "24/7 support lines and urgent care",
                color: crisisRed
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            VStack(spacing: 14) {
                ForEach(MentalHealthResource.crisisResources) { resource in
                    EditorialResourceCard(resource: resource, ink: ink, inkSecondary: inkSecondary, parchment: parchment)
                }
            }
            .padding(.horizontal, 20)

            // "For a Friend" expanded card
            forAFriendCard
                .padding(.horizontal, 20)
                .padding(.top, 24)

            // Safety plan card
            safetyPlanCard
                .padding(.horizontal, 20)
                .padding(.top, 14)

            // Crisis tab footer note
            crisisFooterNote
                .padding(.horizontal, 20)
                .padding(.top, 24)
        }
    }

    // MARK: - Reusable Section Components

    @ViewBuilder
    private func trustLayerHeader(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.systemScaled(18, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(ink)
                Text(subtitle)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(inkSecondary)
            }
            Spacer()
        }
    }

    private var bereanWellnessBridge: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tealAccent.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.systemScaled(18, weight: .medium))
                    .foregroundStyle(tealAccent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Ask Berean")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(ink)
                Text("Private wellness support + scripture")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(inkSecondary)
            }
            Spacer()
            Image(systemName: "arrow.right")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(tealAccent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.93, green: 0.97, blue: 0.96))
        )
        .onTapGesture {
            showBereanCareSheet = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private var specialtyFinderCard: some View {
        Button {
            if let url = URL(string: "https://www.psychologytoday.com/us/therapists") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(red: 0.22, green: 0.42, blue: 0.72).opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "location.magnifyingglass")
                        .font(.systemScaled(18, weight: .medium))
                        .foregroundStyle(Color(red: 0.22, green: 0.42, blue: 0.72))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Find care near me")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(ink)
                    Text("Search by specialty, insurance & faith preference")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(inkSecondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(inkSecondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.95, green: 0.97, blue: 1.0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(red: 0.22, green: 0.42, blue: 0.72).opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(SquishButtonStyle())
    }

    // Expanded "For a Friend" card in crisis tab
    private var forAFriendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "person.fill.questionmark")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(crisisRed)
                Text("Helping Someone Else?")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(ink)
            }

            ForAFriendGuidanceRow(
                icon: "checkmark.circle.fill",
                color: Color(red: 0.12, green: 0.52, blue: 0.38),
                title: "What helps",
                content: "\"I'm here with you.\" Sit in silence if needed. Ask \"Are you thinking about suicide?\" — it opens the door, it doesn't plant the idea."
            )

            ForAFriendGuidanceRow(
                icon: "xmark.circle.fill",
                color: crisisRed,
                title: "What doesn't help",
                content: "\"You just need to pray more.\" \"Others have it worse.\" These phrases dismiss the real weight of what someone is carrying."
            )

            ForAFriendGuidanceRow(
                icon: "exclamationmark.triangle.fill",
                color: Color(red: 0.82, green: 0.40, blue: 0.10),
                title: "If risk is immediate",
                content: "Call 988 together. Stay with them. Remove access to means if safe to do so. Don't leave them alone."
            )

            ForAFriendGuidanceRow(
                icon: "heart.fill",
                color: Color(red: 0.48, green: 0.22, blue: 0.72),
                title: "Your limits",
                content: "You are not their therapist. Caring doesn't mean carrying everything. 988 and trained counselors exist so you don't have to do this alone."
            )

            // Scripture anchor
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color(red: 0.48, green: 0.22, blue: 0.72))
                    .frame(width: 2)
                    .cornerRadius(1)
                Text("\"Carry each other's burdens, and in this way you will fulfill the law of Christ.\" — Galatians 6:2")
                    .font(.custom("Georgia", size: 13))
                    .italic()
                    .foregroundStyle(inkSecondary)
                    .lineSpacing(4)
            }

            HStack(spacing: 10) {
                ForAFriendActionButton(
                    icon: "phone.fill",
                    label: "Call 988",
                    color: crisisRed,
                    urlString: "tel:988"
                )
                ForAFriendActionButton(
                    icon: "globe",
                    label: "988lifeline.org",
                    color: Color(red: 0.14, green: 0.38, blue: 0.72),
                    urlString: "https://988lifeline.org/help-someone-else/"
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 1.0, green: 0.96, blue: 0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(crisisRed.opacity(0.20), lineWidth: 1)
                )
        )
    }

    private var safetyPlanCard: some View {
        Button {
            if let url = URL(string: "https://www.samhsa.gov/find-help/disaster-distress-helpline/crisis-resources") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(red: 0.22, green: 0.42, blue: 0.46).opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "list.clipboard.fill")
                        .font(.systemScaled(18, weight: .medium))
                        .foregroundStyle(Color(red: 0.22, green: 0.42, blue: 0.46))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Crisis Safety Plan")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(ink)
                    Text("SAMHSA — Build a personal safety plan")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(inkSecondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(inkSecondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.93, green: 0.96, blue: 0.97))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(red: 0.22, green: 0.42, blue: 0.46).opacity(0.20), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(SquishButtonStyle())
    }

    // MARK: - Guardrail Notes

    private var wellnessFooterGuardrail: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.systemScaled(13))
                .foregroundStyle(inkSecondary)
                .padding(.top, 1)
            Text("These tools support wellness and spiritual growth. They are not a substitute for professional mental health care. If you're in crisis, tap the red card above or call 988.")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(inkSecondary)
                .lineSpacing(3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.05))
        )
    }

    private var counselingGuardrailNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.systemScaled(13))
                .foregroundStyle(inkSecondary)
                .padding(.top, 1)
            Text("Directory listings are for informational purposes. AMEN does not endorse or verify individual providers. Always review credentials and insurance coverage directly with the provider.")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(inkSecondary)
                .lineSpacing(3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.05))
        )
    }

    private var peerSupportGuardrailNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.systemScaled(13))
                .foregroundStyle(inkSecondary)
                .padding(.top, 1)
            Text("Peer support is not a replacement for licensed therapy or crisis intervention. If you or someone you know needs immediate help, call or text 988.")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(inkSecondary)
                .lineSpacing(3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.05))
        )
    }

    private var crisisFooterNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.systemScaled(13))
                .foregroundStyle(crisisRed.opacity(0.7))
                .padding(.top, 1)
            Text("If you are in immediate danger, call 911. The resources above are for mental health crises and emotional support. Prayer, scripture, and peer support listed in other tabs are not crisis care.")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(inkSecondary)
                .lineSpacing(3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(crisisRed.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(crisisRed.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

// MARK: - Crisis Quick Dial Row

private struct CrisisQuickDialRow: View {
    let icon: String
    let label: String
    let action: String
    let color: Color
    let urlString: String

    var body: some View {
        Button {
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(Color(red: 0.14, green: 0.12, blue: 0.10))
                    Text(action)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(color)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.42, green: 0.38, blue: 0.34))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(SquishButtonStyle())
    }
}

// MARK: - For a Friend Action Button

private struct ForAFriendActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let urlString: String

    var body: some View {
        Button {
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.systemScaled(12, weight: .semibold))
                Text(label)
                    .font(.custom("OpenSans-SemiBold", size: 13))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(color)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - For a Friend Guidance Row

private struct ForAFriendGuidanceRow: View {
    let icon: String
    let color: Color
    let title: String
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(Color(red: 0.14, green: 0.12, blue: 0.10))
                Text(content)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(Color(red: 0.42, green: 0.38, blue: 0.34))
                    .lineSpacing(3)
            }
        }
    }
}

// MARK: - Smart Wellness Tool Card

private struct SmartWellnessToolCard: View {
    let tool: WellnessSmartTool
    let parchment: Color
    let ink: Color
    let inkSecondary: Color

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tool.accent.opacity(0.13))
                        .frame(width: 40, height: 40)
                    Image(systemName: tool.icon)
                        .font(.systemScaled(18, weight: .medium))
                        .foregroundStyle(tool.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.name)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(ink)
                    Text(tool.suggestion)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(inkSecondary)
                        .lineLimit(2)
                    Text(tool.memoryLine)
                        .font(.custom("OpenSans-Regular", size: 10))
                        .foregroundStyle(inkSecondary.opacity(0.70))
                        .lineLimit(1)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .frame(height: 140)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(parchment)
                    .shadow(color: Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.07), radius: 8, y: 2)
            )
        }
        .buttonStyle(SquishButtonStyle())
    }
}

// MARK: - Contemplative Practice Card

private struct ContemplativePracticeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accent.opacity(0.13))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.systemScaled(17, weight: .medium))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(Color(red: 0.14, green: 0.12, blue: 0.10))
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(Color(red: 0.42, green: 0.38, blue: 0.34))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(height: 110)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.97, green: 0.95, blue: 0.91))
                    .shadow(color: Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.06), radius: 6, y: 2)
            )
        }
        .buttonStyle(SquishButtonStyle())
    }
}

// MARK: - Editorial Resource Card

private struct EditorialResourceCard: View {
    let resource: MentalHealthResource
    let ink: Color
    let inkSecondary: Color
    let parchment: Color

    var body: some View {
        Button {
            if let url = URL(string: resource.url) {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(resource.color.opacity(0.13))
                            .frame(width: 48, height: 48)
                        Image(systemName: resource.icon)
                            .font(.systemScaled(20, weight: .medium))
                            .foregroundStyle(resource.color)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(resource.name)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(ink)
                                .multilineTextAlignment(.leading)
                            if resource.isFree {
                                Text("Free")
                                    .font(.custom("OpenSans-SemiBold", size: 10))
                                    .foregroundStyle(Color(red: 0.12, green: 0.52, blue: 0.38))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color(red: 0.12, green: 0.52, blue: 0.38).opacity(0.12))
                                    )
                            }
                        }
                        Text(resource.categoryLabel)
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(inkSecondary)
                            .textCase(.uppercase)
                            .kerning(0.5)
                    }

                    Spacer()

                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ink.opacity(0.88))
                            .frame(width: 34, height: 34)
                        Image(systemName: "arrow.up.right")
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(16)

                Text(resource.description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(inkSecondary)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)

                if !resource.features.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(resource.features.prefix(3), id: \.self) { feature in
                                Text(feature)
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(inkSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.07))
                                    )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                    .shadow(color: Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.07), radius: 10, y: 2)
            )
        }
        .buttonStyle(SquishButtonStyle())
    }
}

// MARK: - Silence Overlay View (Care: Sit in silence)

struct SilenceOverlayView: View {
    let verse: String
    let reference: String
    @Environment(\.dismiss) private var dismiss

    private let wellnessDark = Color(red: 0.06, green: 0.18, blue: 0.20)
    private let wellnessMid  = Color(red: 0.10, green: 0.32, blue: 0.30)

    var body: some View {
        ZStack {
            LinearGradient(colors: [wellnessDark, wellnessMid], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.40))

                    Text("\"\(verse)\"")
                        .font(.custom("Georgia", size: 20))
                        .italic()
                        .foregroundStyle(Color.white.opacity(0.90))
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal, 32)

                    Text("— \(reference)")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                Spacer()

                Button { dismiss() } label: {
                    Text("Close")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(Color.white.opacity(0.60))
                }
                .padding(.bottom, 40)
            }
        }
        .accessibilityLabel("Silence with scripture. \(verse). \(reference). Tap Close to dismiss.")
    }
}

// MARK: - Psalm Focus View (Care: Show Psalm)

struct PsalmFocusView: View {
    let mood: WellnessMood
    @Environment(\.dismiss) private var dismiss

    private let wellnessDark = Color(red: 0.06, green: 0.18, blue: 0.20)
    private let wellnessMid  = Color(red: 0.10, green: 0.32, blue: 0.30)

    // Map mood to a focused Psalm passage
    private var psalmContent: (reference: String, text: String) {
        switch mood {
        case .anxious:
            return ("Psalm 23:1–4", "The Lord is my shepherd; I shall not want. He makes me lie down in green pastures. He leads me beside still waters. He restores my soul. Even though I walk through the valley of the shadow of death, I will fear no evil.")
        case .tired:
            return ("Psalm 62:1–2", "My soul finds rest in God alone; my salvation comes from him. He alone is my rock and my salvation; he is my fortress, I will never be shaken.")
        case .heavy:
            return ("Psalm 34:18", "The Lord is near to the brokenhearted and saves the crushed in spirit.")
        case .numb:
            return ("Psalm 13:1–2", "How long, Lord? Will you forget me forever? How long will you hide your face from me? How long must I wrestle with my thoughts and every day have sorrow in my heart?")
        case .grateful:
            return ("Psalm 103:1–4", "Bless the Lord, O my soul, and all that is within me, bless his holy name. Bless the Lord, O my soul, and forget not all his benefits — who forgives all your iniquity, who heals all your diseases.")
        case .joyful:
            return ("Psalm 118:24", "This is the day the Lord has made; let us rejoice and be glad in it.")
        case .other:
            return ("Psalm 139:1–4", "Lord, you have searched me and known me. You know when I sit down and when I rise up; you discern my thoughts from afar. You search out my path and my lying down and are acquainted with all my ways.")
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [wellnessDark, wellnessMid], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.40))

                    Text(psalmContent.reference)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .kerning(1.5)
                        .foregroundStyle(Color.white.opacity(0.55))
                        .textCase(.uppercase)

                    Text(psalmContent.text)
                        .font(.custom("Georgia", size: 19))
                        .italic()
                        .foregroundStyle(Color.white.opacity(0.90))
                        .multilineTextAlignment(.center)
                        .lineSpacing(7)
                        .padding(.horizontal, 28)
                }

                Spacer()

                Button { dismiss() } label: {
                    Text("Close")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(Color.white.opacity(0.60))
                }
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Data Models

struct MentalHealthResource: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let url: String
    let icon: String
    let color: Color
    let categoryLabel: String
    let isFree: Bool
    let features: [String]

    // Legacy category property for compatibility
    var category: MentalHealthDetailView.WellnessTab {
        switch categoryLabel {
        case "Counseling":       return .counsel
        case "Support Groups":  return .groups
        case "Crisis":          return .crisis
        default:                return .faith
        }
    }

    // MARK: Crisis Resources (Layer 1)
    static let crisisResources = [
        MentalHealthResource(
            name: "988 Suicide & Crisis Lifeline",
            description: "Free, confidential 24/7 support for people in suicidal crisis or emotional distress. Call or text 988 anytime.",
            url: "tel:988",
            icon: "phone.fill",
            color: Color(red: 0.82, green: 0.14, blue: 0.16),
            categoryLabel: "Crisis",
            isFree: true,
            features: ["24/7 availability", "Call or text", "Confidential"]
        ),
        MentalHealthResource(
            name: "SAMHSA Helpline",
            description: "Substance Abuse and Mental Health Services Administration — free treatment referrals and information, 365 days/year.",
            url: "tel:18006624357",
            icon: "cross.case.fill",
            color: Color(red: 0.82, green: 0.40, blue: 0.10),
            categoryLabel: "Crisis",
            isFree: true,
            features: ["1-800-662-4357", "Treatment locator", "Free & confidential"]
        ),
        MentalHealthResource(
            name: "Crisis Text Line",
            description: "Text HOME to 741741 to reach a trained crisis counselor. Free, 24/7 text-based mental health support.",
            url: "sms:741741&body=HOME",
            icon: "message.fill",
            color: Color(red: 0.20, green: 0.44, blue: 0.82),
            categoryLabel: "Crisis",
            isFree: true,
            features: ["Text HOME to 741741", "24/7 coverage", "Free to text"]
        ),
        MentalHealthResource(
            name: "Veterans Crisis Line",
            description: "Dedicated support for veterans, service members, and their families. Dial 988 then press 1, or text 838255.",
            url: "tel:988",
            icon: "shield.fill",
            color: Color(red: 0.14, green: 0.38, blue: 0.62),
            categoryLabel: "Crisis",
            isFree: true,
            features: ["Press 1 after 988", "Text 838255", "For veterans & families"]
        ),
    ]

    // MARK: Counseling Resources (Layer 2)
    static let counselingResources = [
        MentalHealthResource(
            name: "BetterHelp",
            description: "Online therapy with licensed counselors. Get matched in 24 hours. Christian counselor filters available.",
            url: "https://www.betterhelp.com",
            icon: "person.fill.questionmark",
            color: Color(red: 0.22, green: 0.42, blue: 0.72),
            categoryLabel: "Counseling",
            isFree: false,
            features: ["Licensed therapists", "Text, call, or video", "Financial aid"]
        ),
        MentalHealthResource(
            name: "Faithful Counseling",
            description: "Faith-based online therapy connecting you with Christian counselors who integrate scripture into sessions.",
            url: "https://www.faithfulcounseling.com",
            icon: "cross.fill",
            color: Color(red: 0.48, green: 0.22, blue: 0.72),
            categoryLabel: "Counseling",
            isFree: false,
            features: ["Christian-based", "Licensed therapists", "Flexible scheduling"]
        ),
        MentalHealthResource(
            name: "Focus on the Family",
            description: "Free phone consultations with licensed counselors. Referrals to Christian therapists nationwide.",
            url: "https://www.focusonthefamily.com/get-help/counseling-services-and-referrals/",
            icon: "phone.circle.fill",
            color: Color(red: 0.12, green: 0.52, blue: 0.38),
            categoryLabel: "Counseling",
            isFree: true,
            features: ["Free consultations", "Therapist referrals", "Faith-based"]
        ),
        MentalHealthResource(
            name: "Psychology Today",
            description: "Find therapists, psychiatrists, and support groups near you. Filter by specialty, insurance, and faith preference.",
            url: "https://www.psychologytoday.com/us/therapists",
            icon: "magnifyingglass.circle.fill",
            color: Color(red: 0.22, green: 0.48, blue: 0.42),
            categoryLabel: "Counseling",
            isFree: true,
            features: ["Local directory", "Insurance filters", "Faith filter"]
        ),
    ]

    // MARK: Support Group Resources (Layer 2 — Peer)
    static let groupResources = [
        MentalHealthResource(
            name: "Celebrate Recovery",
            description: "Christ-centered 12-step recovery program for hurts, habits, and hang-ups. Thousands of groups nationwide.",
            url: "https://www.celebraterecovery.com",
            icon: "person.3.fill",
            color: Color(red: 0.12, green: 0.52, blue: 0.38),
            categoryLabel: "Support Groups",
            isFree: true,
            features: ["Nationwide groups", "Biblical foundation", "Free to attend"]
        ),
        MentalHealthResource(
            name: "GriefShare",
            description: "Support groups for people grieving the loss of a loved one. Guided by Christian perspectives on grief.",
            url: "https://www.griefshare.org",
            icon: "heart.fill",
            color: Color(red: 0.72, green: 0.32, blue: 0.42),
            categoryLabel: "Support Groups",
            isFree: true,
            features: ["Local grief groups", "Christian perspective", "Workbook included"]
        ),
        MentalHealthResource(
            name: "NAMI Connection",
            description: "Free peer-led support groups for adults living with mental illness. Evidence-based, confidential, and welcoming.",
            url: "https://www.nami.org/Support-Education/Support-Groups/NAMI-Connection-Recovery-Support-Group",
            icon: "person.2.fill",
            color: Color(red: 0.52, green: 0.28, blue: 0.72),
            categoryLabel: "Support Groups",
            isFree: true,
            features: ["Peer-led", "Evidence-based", "Confidential"]
        ),
        MentalHealthResource(
            name: "DivorceCare",
            description: "Support groups and resources for people experiencing separation or divorce. Faith-centered healing.",
            url: "https://www.divorcecare.org",
            icon: "figure.2.arms.open",
            color: Color(red: 0.72, green: 0.46, blue: 0.22),
            categoryLabel: "Support Groups",
            isFree: true,
            features: ["Weekly groups", "Expert teaching", "Workbook"]
        ),
    ]

    // MARK: Faith-Based Organizations (Layer 3 — Spiritual)
    static let faithOrgs = [
        MentalHealthResource(
            name: "NAMI FaithNet",
            description: "A national network within NAMI helping congregations create mental health-friendly communities of faith.",
            url: "https://www.nami.org/Support-Education/Mental-Health-Education/NAMI-FaithNet",
            icon: "building.columns.fill",
            color: Color(red: 0.48, green: 0.22, blue: 0.72),
            categoryLabel: "Faith",
            isFree: true,
            features: ["Church resources", "Congregational support", "Reducing stigma"]
        ),
        MentalHealthResource(
            name: "Mental Health Grace Alliance",
            description: "Equipping the church to bring grace and healing to those with mental illness through biblical and clinical integration.",
            url: "https://www.mentalhealthgracealliance.org",
            icon: "cross.circle.fill",
            color: Color(red: 0.12, green: 0.52, blue: 0.38),
            categoryLabel: "Faith",
            isFree: true,
            features: ["Church support groups", "Family resources", "Biblical + clinical"]
        ),
    ]

    // MARK: Faith Apps & Devotionals (Layer 3 — Wellness)
    static let faithResources = [
        MentalHealthResource(
            name: "Pray.com",
            description: "Christian meditation, prayer, and sleep content designed to reduce anxiety and anchor you in peace.",
            url: "https://www.pray.com",
            icon: "hands.sparkles.fill",
            color: Color(red: 0.48, green: 0.22, blue: 0.72),
            categoryLabel: "Faith",
            isFree: false,
            features: ["Guided prayers", "Bible meditations", "Sleep content"]
        ),
        MentalHealthResource(
            name: "Abide",
            description: "Scripture-based meditation with sleep stories, breathing exercises, and mindfulness grounded in the Word.",
            url: "https://www.abide.co",
            icon: "moon.stars.fill",
            color: Color(red: 0.28, green: 0.32, blue: 0.62),
            categoryLabel: "Faith",
            isFree: false,
            features: ["Scripture-based", "Sleep stories", "Stress relief"]
        ),
        MentalHealthResource(
            name: "YouVersion Bible Plans",
            description: "Free devotional reading plans specifically addressing anxiety, depression, and mental wellness.",
            url: "https://www.bible.com/reading-plans",
            icon: "book.fill",
            color: Color(red: 0.22, green: 0.42, blue: 0.72),
            categoryLabel: "Faith",
            isFree: true,
            features: ["Mental health plans", "Daily devotionals", "100% free"]
        ),
        MentalHealthResource(
            name: "Mental Health America",
            description: "Free screening tools and education. Understanding your mental health is an act of stewardship.",
            url: "https://www.mhanational.org",
            icon: "heart.circle.fill",
            color: Color(red: 0.72, green: 0.22, blue: 0.22),
            categoryLabel: "Faith",
            isFree: true,
            features: ["Free screenings", "Educational articles", "Local resources"]
        ),
    ]

    // All resources combined (used by legacy search code)
    static let allResources: [MentalHealthResource] = crisisResources + counselingResources + groupResources + faithOrgs + faithResources
}

#Preview {
    NavigationStack {
        MentalHealthDetailView()
    }
}

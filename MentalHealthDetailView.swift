//
//  MentalHealthDetailView.swift
//  AMENAPP
//
//  Support Hub — Mental Health & Wellness
//  Three trust layers: Crisis / Professional / Wellness & Spiritual
//  Parchment design language, editorial card UI.
//

import SwiftUI

// MARK: - Mental Health Detail View

struct MentalHealthDetailView: View {
    @State private var selectedTab: WellnessTab = .tools
    @State private var appeared = false
    @Environment(\.dismiss) private var dismiss

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
                                    .font(.system(size: 12, weight: .semibold))
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
                        .font(.system(size: 9, weight: .semibold))
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
                        .font(.system(size: 14, weight: .regular))
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
                    .font(.system(size: 14, weight: .semibold))
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
                        .font(.system(size: 14))
                        .foregroundStyle(crisisRed)
                    Text("Helping someone else? See the \"For a Friend\" guide")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(ink)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
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

    // MARK: Tab Switcher

    private var tabSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(WellnessTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                            selectedTab = tab
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 5) {
                                if tab == .crisis {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 11, weight: .semibold))
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

    // MARK: Tools Tab

    private var wellnessToolsGrid: some View {
        VStack(spacing: 0) {
            scriptureBlockquote
                .padding(.horizontal, 20)

            let tools: [(String, String, String, Color)] = [
                ("wind",                  "Breathing",     "Box-breath exercise",      tealAccent),
                ("brain.head.profile",    "Grounding",     "5-4-3-2-1 technique",      Color(red: 0.52, green: 0.36, blue: 0.72)),
                ("moon.stars.fill",       "Sleep Hygiene", "Rest & restoration tips",  Color(red: 0.28, green: 0.38, blue: 0.62)),
                ("figure.walk",           "Movement",      "Body & mood connection",   Color(red: 0.22, green: 0.52, blue: 0.38)),
                ("book.fill",             "Journaling",    "Reflection prompts",       Color(red: 0.72, green: 0.46, blue: 0.22)),
                ("hands.sparkles.fill",   "Prayer",        "Centering in Christ",      Color(red: 0.62, green: 0.22, blue: 0.42)),
            ]

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                ForEach(tools, id: \.0) { tool in
                    WellnessToolCard(
                        icon: tool.0,
                        title: tool.1,
                        subtitle: tool.2,
                        accent: tool.3,
                        parchment: parchment,
                        ink: ink,
                        inkSecondary: inkSecondary
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            bereanWellnessBridge
                .padding(.horizontal, 20)
                .padding(.top, 20)
        }
    }

    // MARK: Counseling Tab

    private var counselingList: some View {
        VStack(spacing: 0) {
            // Trust layer header
            trustLayerHeader(
                icon: "person.fill.checkmark",
                title: "Professional Support",
                subtitle: "Licensed counselors & therapists",
                color: Color(red: 0.22, green: 0.42, blue: 0.72)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            VStack(spacing: 14) {
                ForEach(MentalHealthResource.counselingResources) { resource in
                    EditorialResourceCard(resource: resource, ink: ink, inkSecondary: inkSecondary, parchment: parchment)
                }
            }
            .padding(.horizontal, 20)

            // Specialty finder
            specialtyFinderCard
                .padding(.horizontal, 20)
                .padding(.top, 14)

            counselingGuardrailNote
                .padding(.horizontal, 20)
                .padding(.top, 20)
        }
    }

    // MARK: Groups Tab

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

    // MARK: Faith Tab

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

            // "For a Friend" card
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
                    .font(.system(size: 18, weight: .medium))
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

    private var scriptureBlockquote: some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle()
                .fill(tealAccent)
                .frame(width: 3)
                .cornerRadius(2)

            VStack(alignment: .leading, spacing: 6) {
                Text("\"Do not be anxious about anything, but in every situation, by prayer and petition, present your requests to God.\"")
                    .font(.custom("Georgia", size: 15))
                    .fontWeight(.regular)
                    .foregroundStyle(ink)
                    .italic()
                    .lineSpacing(4)

                Text("— Philippians 4:6")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(inkSecondary)
            }
        }
        .padding(.top, 4)
    }

    private var bereanWellnessBridge: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tealAccent.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 18, weight: .medium))
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tealAccent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.93, green: 0.97, blue: 0.96))
        )
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
                        .font(.system(size: 18, weight: .medium))
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
                    .font(.system(size: 13, weight: .semibold))
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

    private var forAFriendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(crisisRed)
                Text("Helping Someone Else?")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(ink)
            }

            Text("If someone you know is in crisis, stay with them. Call 988 together, or text on their behalf. You don't need to have all the answers — your presence matters.")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(inkSecondary)
                .lineSpacing(4)

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
                        .font(.system(size: 18, weight: .medium))
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
                    .font(.system(size: 13, weight: .semibold))
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
                .font(.system(size: 13))
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
                .font(.system(size: 13))
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
                .font(.system(size: 13))
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
                .font(.system(size: 13))
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
                        .font(.system(size: 15, weight: .medium))
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
                    .font(.system(size: 12, weight: .semibold))
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
                    .font(.system(size: 12, weight: .semibold))
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

// MARK: - Wellness Tool Card

private struct WellnessToolCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
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
                        .fill(accent.opacity(0.13))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(ink)
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(inkSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                    .shadow(color: Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.07), radius: 8, y: 2)
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
                            .font(.system(size: 20, weight: .medium))
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
                            .font(.system(size: 13, weight: .semibold))
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
